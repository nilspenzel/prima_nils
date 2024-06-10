use crate::{
    backend::{
        availability::AvailabilityData,
        id_types::{CompanyId, Id, TourId, VehicleId},
        interval::Interval,
        lib::{PrimaTour, PrimaVehicle},
        tour::TourData,
    },
    entities::availability,
    error, StatusCode,
};
use async_trait::async_trait;
use chrono::NaiveDateTime;
use itertools::Itertools;
use sea_orm::{ActiveModelTrait, ActiveValue, DbConn, TransactionTrait};
use std::collections::HashMap;

use super::id_types::AvailabilityId;

#[derive(Clone, PartialEq, Default)]
pub struct VehicleData {
    pub id: VehicleId,
    pub license_plate: String,
    pub company: CompanyId,
    pub seats: i32,
    pub wheelchair_capacity: i32,
    pub storage_space: i32,
    pub availability: HashMap<i32, AvailabilityData>,
    pub tours: Vec<TourData>,
}

pub enum TravelTimeComparisonMode {
    FromTaxiCentral,
    EventBased,
}

#[async_trait]
impl PrimaVehicle for VehicleData {
    async fn get_id(&self) -> VehicleId {
        self.id
    }

    async fn get_license_plate(&self) -> &str {
        &self.license_plate
    }

    async fn get_company_id(&self) -> CompanyId {
        self.company
    }

    async fn get_tours(&self) -> Vec<Box<&dyn PrimaTour>> {
        self.tours
            .iter()
            .map(|tour| Box::new(tour as &dyn PrimaTour))
            .collect_vec()
    }
}

impl VehicleData {
    pub fn new(
        id: VehicleId,
        license_plate: &str,
        company: CompanyId,
        seats: i32,
        wheelchair_capacity: i32,
        storage_space: i32,
    ) -> Self {
        Self {
            id,
            license_plate: license_plate.to_string(),
            company,
            seats,
            wheelchair_capacity,
            storage_space,
            availability: HashMap::new(),
            tours: Vec::new(),
        }
    }

    pub fn may_vehicle_operate_during(
        &self,
        interval: &Interval,
        start_cmp_mode: TravelTimeComparisonMode,
        target_cmp_mode: TravelTimeComparisonMode,
    ) -> bool {
        self.availability
            .values()
            .any(|availability| availability.contains(interval))
            && !self
                .tours
                .iter()
                .any(|tour| match (&start_cmp_mode, &target_cmp_mode) {
                    (
                        TravelTimeComparisonMode::EventBased,
                        TravelTimeComparisonMode::EventBased,
                    ) => tour
                        .events
                        .iter()
                        .any(|event| interval.contains_point(&event.scheduled_time)),
                    (
                        TravelTimeComparisonMode::FromTaxiCentral,
                        TravelTimeComparisonMode::EventBased,
                    ) => {
                        interval.start_time < tour.departure
                            && tour
                                .events
                                .iter()
                                .any(|event| interval.contains_point(&event.scheduled_time))
                    }
                    (
                        TravelTimeComparisonMode::EventBased,
                        TravelTimeComparisonMode::FromTaxiCentral,
                    ) => {
                        interval.end_time > tour.arrival
                            && tour
                                .events
                                .iter()
                                .any(|event| interval.contains_point(&event.scheduled_time))
                    }
                    (
                        TravelTimeComparisonMode::FromTaxiCentral,
                        TravelTimeComparisonMode::FromTaxiCentral,
                    ) => tour.overlaps(interval),
                })
    }

    pub fn fulfills_requirements(
        &self,
        passengers: i32,
    ) -> bool {
        passengers < 4 //TODO when mvp-restrictions are lifted
    }

    pub async fn get_tour(
        &mut self,
        tour_id: TourId,
    ) -> Result<&mut TourData, StatusCode> {
        match self.tours.iter_mut().find(|tour| tour.get_id() == tour_id) {
            Some(t) => Ok(t),
            None => Err(StatusCode::NOT_FOUND),
        }
    }

    pub async fn add_availability(
        &mut self,
        db_conn: &DbConn,
        new_interval: &mut Interval,
        mut id_or_none: Option<i32>, //None->insert availability into db, this yields the id->create availability in data with this id.  Some->create in data with given id, nothing to do in db
    ) -> StatusCode {
        let mut mark_delete: Vec<i32> = Vec::new();
        for (id, existing) in self.availability.iter() {
            if !existing.overlaps(new_interval) {
                if existing.touches(new_interval) && existing != new_interval {
                    mark_delete.push(*id);
                    *new_interval = existing.merge(new_interval);
                }
                continue;
            }
            if existing.contains(new_interval) {
                return StatusCode::NO_CONTENT; // availability inserted succesfully, but nothing changed
            }
            if existing.contains(new_interval) {
                mark_delete.push(*id);
            }
            if existing.overlaps(new_interval) {
                mark_delete.push(*id);
                *new_interval = existing.merge(new_interval);
            }
        }
        // update database
        let txn = db_conn.begin().await.unwrap();
        let insert_active_model = availability::ActiveModel {
            id: ActiveValue::NotSet,
            start_time: ActiveValue::Set(new_interval.start_time),
            end_time: ActiveValue::Set(new_interval.end_time),
            vehicle: ActiveValue::Set(self.id.id()),
        }
        .save(&txn)
        .await;
        if id_or_none.is_none() {
            if let Ok(mut model) = insert_active_model {
                id_or_none = model.id.take()
            }
        };
        for to_delete in mark_delete.iter() {
            let _ = availability::ActiveModel {
                id: ActiveValue::Set(self.availability[&to_delete].get_id().id()),
                start_time: ActiveValue::Set(NaiveDateTime::MIN),
                end_time: ActiveValue::Set(NaiveDateTime::MIN),
                vehicle: ActiveValue::Set(self.id.id()),
            }
            .save(&txn)
            .await;
            //Availability::delete_by_id(self.availability[&to_delete].get_id().id())
        }
        if let Err(e) = txn.commit().await {
            error!("{e:?}");
            return StatusCode::INTERNAL_SERVER_ERROR;
        }

        // update ram
        for to_delete in mark_delete {
            self.availability.remove(&to_delete);
        }
        let id = match id_or_none {
            Some(i) => i,
            None => {
                error!("Id for inserted availability was none.");
                return StatusCode::INTERNAL_SERVER_ERROR;
            }
        };
        match self.availability.insert(
            id,
            AvailabilityData::new(AvailabilityId::new(id), *new_interval),
        ) {
            None => StatusCode::CREATED,
            Some(_) => {
                error!("Key already existed in availability");
                StatusCode::INTERNAL_SERVER_ERROR
            }
        }
    }

    pub fn get_preceding_tour(
        &self,
        time: &NaiveDateTime,
    ) -> Option<TourId> {
        self.tours
            .iter()
            .filter(|tour| {
                tour.events
                    .iter()
                    .map(|event| event.scheduled_time)
                    .max()
                    .unwrap()
                    < *time
            })
            .max_by_key(|tour| tour.arrival)
            .map(|tour| tour.id)
    }

    pub fn get_succeeding_tour(
        &self,
        time: &NaiveDateTime,
    ) -> Option<TourId> {
        self.tours
            .iter()
            .filter(|tour| {
                tour.events
                    .iter()
                    .map(|event| event.scheduled_time)
                    .max()
                    .unwrap()
                    > *time
            })
            .min_by_key(|tour| tour.departure)
            .map(|tour| tour.id)
    }

    #[allow(dead_code)]
    pub fn print(
        &self,
        indent: &str,
    ) {
        println!(
            "{}id: {}, license: {}, company: {}, seats: {}, wheelchair_capacity: {}, storage_space: {}",indent,
            self.id, self.license_plate, self.company, self.seats, self.wheelchair_capacity, self.storage_space
        );
    }
}
