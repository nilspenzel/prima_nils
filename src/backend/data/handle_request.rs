use super::Data;
use crate::{
    backend::{
        data::{error, info, Coord, Point},
        helpers::{beeline_duration, seconds_to_minutes, seconds_to_minutes_duration},
        id_types::{CompanyId, Id, TourId, UserId, VehicleId},
        interval::Interval,
        lat_long::{Latitude, Longitude},
        lib::{HandleRequest, TourCrud},
        possible_assignment::{PossibleAssignment, TourConcatCase},
        vehicle::TravelTimeComparisonMode,
    },
    constants::primitives::{MIN_PREP_MINUTES, PASSENGER_CHANGE_MINUTES},
    osrm::{
        Dir::{Backward, Forward},
        DistTime,
    },
    StatusCode,
};
use async_trait::async_trait;
use chrono::{Duration, NaiveDateTime, Utc};
use itertools::Itertools;
use std::collections::HashMap;

#[async_trait]
impl HandleRequest for Data {
    async fn handle_routing_request(
        &mut self,
        fixed_time: NaiveDateTime,
        is_start_time_fixed: bool,
        start_lat: Latitude,
        start_lng: Longitude,
        target_lat: Latitude,
        target_lng: Longitude,
        customer: UserId,
        passengers: i32,
        start_address: &str,
        target_address: &str,
        //wheelchairs: i32, luggage: i32, TODO
    ) -> StatusCode {
        // TODOs:
        //- add buffer based on travel time or duration
        //- compute costs based on distance instead of travel time, when osm provides the distances
        //- manage communicated times and use them to allow more concatenations
        if !self.users.contains_key(&customer) {
            return StatusCode::NOT_FOUND;
        }
        if passengers < 1 {
            return StatusCode::EXPECTATION_FAILED;
        }
        if passengers > 3 {
            // TODO: change when mvp restriction is lifted
            return StatusCode::NO_CONTENT;
        }
        let now: NaiveDateTime = Utc::now().naive_utc();
        if now > fixed_time {
            return StatusCode::NOT_ACCEPTABLE;
        }

        let start = Point::new(start_lat, start_lng);
        let target = Point::new(target_lat, target_lng);

        let start_c = Coord::from(start);
        let target_c = Coord::from(target);

        let osrm_result = match self.osrm.one_to_many(&start_c, &[target_c], Forward).await {
            Ok(r) => r,
            Err(_) => Vec::new(),
        };

        if osrm_result.is_empty() {
            return StatusCode::NOT_FOUND;
        }

        let travel_duration = seconds_to_minutes_duration(osrm_result[0].time);
        let passenger_change_duration = Duration::minutes(PASSENGER_CHANGE_MINUTES);
        let (start_time, target_time) = if is_start_time_fixed {
            (
                fixed_time - passenger_change_duration,
                fixed_time + travel_duration + passenger_change_duration,
            )
        } else {
            (
                fixed_time - travel_duration - passenger_change_duration,
                fixed_time + passenger_change_duration,
            )
        };

        if now + Duration::minutes(MIN_PREP_MINUTES) > start_time {
            return StatusCode::NO_CONTENT;
        }

        let travel_interval = Interval::new(start_time, target_time);

        // Find vehicles that may process the request according to their vehicle-specifics and to the zone of their company.
        let candidate_vehicles = self
            .get_candidate_vehicles(passengers, &start, &target)
            .await;

        let mut candidate_assignments = Vec::<PossibleAssignment>::new();
        let mut start_many_companies = HashMap::<CompanyId, Vec<TourConcatCase>>::new();
        let mut target_many_companies = HashMap::<CompanyId, Vec<TourConcatCase>>::new();
        let mut start_many_assignments_by_vehicles = Vec::<(Coord, TourConcatCase)>::new();
        let mut target_many_assignments_by_vehicles = Vec::<(Coord, TourConcatCase)>::new();
        // there are 4 general cases:
        // Creating a NewTour with only the new request (general case exists per company) or
        // (Prepend, Append, Insert) - the request to/between existing tour(s) (general case exists per vehicle)
        // For each case check wether it can be ruled out based on beeline-travel-durations, otherwise create it.
        // Also collect all the necessary coordinates for the osrm-requests (in start_many and target_many)
        // and link each case to the respective coordinates (in case_idx_to_start_many_idx and case_idx_to_target_many_idx)

        //Insert case is being ignored for now.
        for (company_id, vehicles) in candidate_vehicles
            .iter()
            .into_group_map_by(|vehicle| vehicle.company)
        {
            let company_coordinates = &self.companies.get(company_id).central_coordinates;
            let approach_duration = beeline_duration(company_coordinates, &start);
            let return_duration = beeline_duration(company_coordinates, &target);
            if vehicles.iter().any(|vehicle| {
                vehicle.may_vehicle_operate_during(
                    &travel_interval.expand(approach_duration, return_duration),
                    TravelTimeComparisonMode::FromTaxiCentral,
                    TravelTimeComparisonMode::FromTaxiCentral,
                )
            }) {
                let new_assignment =
                    PossibleAssignment::new(TourConcatCase::NewTour { company_id });
                candidate_assignments.push(new_assignment.clone());
                start_many_companies
                    .entry(company_id)
                    .or_default()
                    .push(new_assignment.case.clone());
                target_many_companies
                    .entry(company_id)
                    .or_default()
                    .push(new_assignment.case);
            }
            for vehicle in vehicles.iter() {
                let vehicle_id = vehicle.id;
                let predecessor_event_opt = vehicle
                    .tours
                    .iter()
                    .filter(|tour| tour.departure < travel_interval.start_time)
                    .flat_map(|tour| &tour.events)
                    .max_by_key(|event| event.scheduled_time);
                let successor_event_opt = vehicle
                    .tours
                    .iter()
                    .filter(|tour| tour.arrival > travel_interval.end_time)
                    .flat_map(|tour| &tour.events)
                    .min_by_key(|event| event.scheduled_time);
                if let Some(pred_event) = predecessor_event_opt {
                    if vehicle.may_vehicle_operate_during(
                        &travel_interval.expand(
                            beeline_duration(&pred_event.coordinates, &start),
                            return_duration,
                        ),
                        TravelTimeComparisonMode::FromTaxiCentral,
                        TravelTimeComparisonMode::EventBased,
                    ) {
                        let new_assignment = PossibleAssignment::new(TourConcatCase::Append {
                            vehicle_id,
                            previous_event_time: pred_event.scheduled_time,
                        });
                        candidate_assignments.push(new_assignment.clone());
                        start_many_assignments_by_vehicles.push((
                            Coord::from(pred_event.coordinates),
                            new_assignment.case.clone(),
                        ));
                        target_many_companies
                            .entry(company_id)
                            .or_default()
                            .push(new_assignment.case);
                    }
                }
                if let Some(succ_event) = successor_event_opt {
                    if vehicle.may_vehicle_operate_during(
                        &travel_interval.expand(
                            approach_duration,
                            beeline_duration(&succ_event.coordinates, &target),
                        ),
                        TravelTimeComparisonMode::EventBased,
                        TravelTimeComparisonMode::FromTaxiCentral,
                    ) {
                        let new_assignment = PossibleAssignment::new(TourConcatCase::Prepend {
                            vehicle_id: vehicle.id,
                            next_event_time: succ_event.scheduled_time,
                        });
                        candidate_assignments.push(new_assignment.clone());
                        start_many_companies
                            .entry(company_id)
                            .or_default()
                            .push(new_assignment.case.clone());
                        target_many_assignments_by_vehicles
                            .push((Coord::from(succ_event.coordinates), new_assignment.case));
                    }
                }
            }
        }

        // Prepare the many vectors for the routing call. These are two vectors for start and target respectively, which contain the coordinates required to decide,
        // which company is assigned the job, and whether the job is being done as new tour or as a concatenation.
        // Depending on the which case of concatenation (new tour, append, prepend or insert) any of the candidate assignments are, the coordinates can be the taxi central coordinates of the company
        // or event coordinates of a predecessor or succesor event for a given vehicle.

        let mut start_many = Vec::<Coord>::new();
        let mut target_many = Vec::<Coord>::new();
        let mut start_idxs_by_candidate_assignment = HashMap::<TourConcatCase, usize>::new();
        let mut target_idxs_by_candidate_assignment = HashMap::<TourConcatCase, usize>::new();

        fn insert_company_coordinates(
            data: &Data,
            assignments_by_company: &HashMap<CompanyId, Vec<TourConcatCase>>,
            many: &mut Vec<Coord>,
            idxs_by_candidate_assignment: &mut HashMap<TourConcatCase, usize>,
        ) -> usize {
            let mut pos = 0;
            for (id, assignments) in assignments_by_company.iter() {
                many.push(Coord::from(data.companies.get(*id).central_coordinates));
                for assignment in assignments.iter() {
                    idxs_by_candidate_assignment.insert(assignment.clone(), pos);
                }
                pos += 1;
            }
            pos
        }

        fn insert_vehicle_coordinates(
            assignment_by_vehicle: &[(Coord, TourConcatCase)],
            many: &mut Vec<Coord>,
            idxs_by_candidate_assignment: &mut HashMap<TourConcatCase, usize>,
            mut pos: usize,
        ) {
            for (coord, assignment) in assignment_by_vehicle.iter() {
                many.push(*coord);
                idxs_by_candidate_assignment.insert(assignment.clone(), pos);
                pos += 1;
            }
        }

        let pos = insert_company_coordinates(
            self,
            &start_many_companies,
            &mut start_many,
            &mut start_idxs_by_candidate_assignment,
        );

        insert_vehicle_coordinates(
            &start_many_assignments_by_vehicles,
            &mut start_many,
            &mut start_idxs_by_candidate_assignment,
            pos,
        );

        let pos = insert_company_coordinates(
            self,
            &target_many_companies,
            &mut target_many,
            &mut target_idxs_by_candidate_assignment,
        );

        insert_vehicle_coordinates(
            &target_many_assignments_by_vehicles,
            &mut target_many,
            &mut target_idxs_by_candidate_assignment,
            pos,
        );

        let distances_to_start: Vec<DistTime> =
            match self.osrm.one_to_many(&start_c, &start_many, Backward).await {
                Ok(r) => r,
                Err(e) => {
                    error!("problem with osrm: {}", e);
                    Vec::new()
                }
            };
        let distances_to_target: Vec<DistTime> = match self
            .osrm
            .one_to_many(&target_c, &target_many, Forward)
            .await
        {
            Ok(r) => r,
            Err(e) => {
                error!("problem with osrm: {}", e);
                Vec::new()
            }
        };

        for candidate in candidate_assignments.iter_mut() {
            candidate.compute_cost(
                seconds_to_minutes(
                    distances_to_start[*(start_idxs_by_candidate_assignment
                        .get(&candidate.case)
                        .unwrap())]
                    .time as i32,
                ),
                seconds_to_minutes(
                    distances_to_target[*target_idxs_by_candidate_assignment
                        .get(&candidate.case)
                        .unwrap()]
                    .time as i32,
                ),
            );
        }

        // sort all possible ways of accepting the request by their cost, then find the cheapest one which fulfills the required time constraints with actual travelling durations instead of beeline-durations
        let mut cost_permutation = (0..candidate_assignments.len()).collect_vec();
        cost_permutation.sort_by(|i, j| {
            candidate_assignments[*i]
                .partial_cmp(&candidate_assignments[*j])
                .unwrap_or(i.cmp(j))
        });
        let mut chosen_tour_id: Option<TourId> = None;
        let mut chosen_vehicle_id: Option<VehicleId> = None;
        for i in cost_permutation.iter() {
            let candidate_assignment = &candidate_assignments[*i].case;
            let distances_to_start_idx = *(start_idxs_by_candidate_assignment
                .get(candidate_assignment)
                .unwrap());
            let distances_to_target_idx = *target_idxs_by_candidate_assignment
                .get(candidate_assignment)
                .unwrap();
            let approach_duration =
                seconds_to_minutes_duration(distances_to_start[distances_to_start_idx].time);
            let return_duration =
                seconds_to_minutes_duration(distances_to_target[distances_to_target_idx].time);
            match candidate_assignments[*i].case {
                TourConcatCase::NewTour { company_id } => {
                    for (candidate_company_id, vehicles) in candidate_vehicles
                        .iter()
                        .into_group_map_by(|vehicle| vehicle.company)
                    {
                        if company_id != candidate_company_id {
                            continue;
                        }
                        chosen_vehicle_id = vehicles
                            .iter()
                            .find(|vehicle| {
                                vehicle.may_vehicle_operate_during(
                                    &travel_interval.expand(approach_duration, return_duration),
                                    TravelTimeComparisonMode::FromTaxiCentral,
                                    TravelTimeComparisonMode::FromTaxiCentral,
                                )
                            })
                            .map(|vehicle| vehicle.id);
                        break;
                    }
                    if chosen_vehicle_id.is_some() {
                        info!(
                            "Request accepted! Case: NewTour for company: {}",
                            company_id.id()
                        );
                        break;
                    }
                }
                TourConcatCase::Append {
                    vehicle_id,
                    previous_event_time: _,
                } => {
                    if self.vehicles.get(vehicle_id).may_vehicle_operate_during(
                        &travel_interval.expand(approach_duration, return_duration),
                        TravelTimeComparisonMode::EventBased,
                        TravelTimeComparisonMode::FromTaxiCentral,
                    ) {
                        chosen_tour_id = self
                            .vehicles
                            .get(vehicle_id)
                            .get_preceding_tour(&start_time);
                        chosen_vehicle_id = Some(vehicle_id);
                        info!(
                            "Request accepted! Case: Append for vehicle: {} and tour: {}",
                            vehicle_id.id(),
                            chosen_tour_id.unwrap().id()
                        );
                        break;
                    }
                }
                TourConcatCase::Prepend {
                    vehicle_id,
                    next_event_time: _,
                } => {
                    if self.vehicles.get(vehicle_id).may_vehicle_operate_during(
                        &travel_interval.expand(approach_duration, return_duration),
                        TravelTimeComparisonMode::FromTaxiCentral,
                        TravelTimeComparisonMode::EventBased,
                    ) {
                        chosen_tour_id = self
                            .vehicles
                            .get(vehicle_id)
                            .get_succeeding_tour(&target_time);
                        chosen_vehicle_id = Some(vehicle_id);
                        info!(
                            "Request accepted! Case: Prepend for vehicle: {} and tour: {}",
                            vehicle_id.id(),
                            chosen_tour_id.unwrap().id()
                        );
                        break;
                    }
                }
                TourConcatCase::Insert {
                    vehicle_id: _,
                    previous_event_time: _,
                    next_event_time: _,
                } => (),
            };
        }

        if chosen_vehicle_id.is_none() {
            return StatusCode::NO_CONTENT;
        }
        return self
            .insert_or_addto_tour(
                chosen_tour_id,
                start_time,
                target_time,
                chosen_vehicle_id.unwrap(),
                start_address,
                target_address,
                start_lat,
                start_lng,
                start_time,
                start_time,
                customer,
                passengers,
                0,
                0,
                target_lat,
                target_lng,
                target_time,
                target_time,
            )
            .await;
    }
}
