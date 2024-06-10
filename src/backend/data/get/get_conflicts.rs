use crate::backend::data::HashMap;
use crate::{
    backend::{
        data::Data,
        id_types::{CompanyId, EventId, TourId, VehicleId},
        interval::Interval,
        lib::{GetConflicts, PrimaTour},
    },
    StatusCode,
};
use async_trait::async_trait;
use itertools::Itertools;

#[async_trait]
impl GetConflicts for Data {
    //return vectors of conflicting tours by vehicle ids as keys
    //does not consider the provided tour_id as a conflict
    async fn get_company_conflicts(
        &self,
        company_id: CompanyId,
        tour_id: TourId,
        consider_provided_tour_conflict: bool,
    ) -> Result<HashMap<VehicleId, Vec<Box<&'_ dyn PrimaTour>>>, StatusCode> {
        let provided_tour_interval = match self.get_tour(tour_id).await {
            Ok(t) => Interval::new(t.departure, t.arrival),
            Err(code) => return Err(code),
        };

        let mut ret = HashMap::<VehicleId, Vec<Box<&dyn PrimaTour>>>::new();
        self.vehicles
            .iter()
            .filter(|vehicle| vehicle.company == company_id)
            .for_each(|vehicle| {
                let conflicts = vehicle
                    .tours
                    .iter()
                    .filter(|tour| {
                        (consider_provided_tour_conflict || tour_id != tour.id)
                            && tour.overlaps(&provided_tour_interval)
                    })
                    .map(|tour| Box::new(tour as &dyn PrimaTour))
                    .collect_vec();
                if !conflicts.is_empty() {
                    ret.insert(vehicle.id, conflicts);
                }
            });
        Ok(ret)
    }

    //does not consider the provided tour_id as a conflict
    async fn get_vehicle_conflicts(
        &self,
        vehicle_id: VehicleId,
        tour_id: TourId,
        consider_provided_tour_conflict: bool,
    ) -> Result<Vec<Box<&'_ dyn PrimaTour>>, StatusCode> {
        let tour_interval = match self.get_tour(tour_id).await {
            Ok(t) => Interval::new(t.departure, t.arrival),
            Err(code) => return Err(code),
        };
        Ok(self
            .vehicles
            .get(vehicle_id)
            .tours
            .iter()
            .filter(|tour| {
                (consider_provided_tour_conflict || tour_id != tour.id)
                    && tour.overlaps(&tour_interval)
            })
            .map(|tour| Box::new(tour as &dyn PrimaTour))
            .collect_vec())
    }

    async fn get_tour_conflicts(
        &self,
        event_id: EventId,
        company_id: Option<CompanyId>,
    ) -> Result<Vec<Box<&'_ dyn PrimaTour>>, StatusCode> {
        if self
            .vehicles
            .iter()
            .flat_map(|vehicle| vehicle.tours.iter().flat_map(|tour| &tour.events))
            .any(|event| event_id == event.id)
        {
            return Err(StatusCode::NOT_FOUND);
        }
        let event = match self.find_event(event_id).await {
            None => return Err(StatusCode::NOT_FOUND),
            Some(e) => e,
        };
        Ok(self
            .vehicles
            .iter()
            .filter(|vehicle| match company_id {
                None => true,
                Some(id) => vehicle.company == id,
            })
            .flat_map(|vehicle| &vehicle.tours)
            .filter(|tour| {
                tour.overlaps(&Interval::new(
                    event.communicated_time,
                    event.scheduled_time,
                ))
            })
            .map(|tour| Box::new(tour as &dyn PrimaTour))
            .collect_vec())
    }
}
