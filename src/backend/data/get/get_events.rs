use crate::{
    backend::{
        data::Data,
        id_types::{TourId, UserId, VehicleId},
        interval::Interval,
        lib::{GetEvents, PrimaEvent},
    },
    StatusCode,
};
use async_trait::async_trait;
use chrono::NaiveDateTime;
use itertools::Itertools;

#[async_trait]
impl GetEvents for Data {
    async fn get_events_for_vehicle(
        &self,
        vehicle_id: VehicleId,
        time_frame_start: NaiveDateTime,
        time_frame_end: NaiveDateTime,
    ) -> Result<Vec<Box<&'_ dyn PrimaEvent>>, StatusCode> {
        let interval = Interval::new(time_frame_start, time_frame_end);
        Ok(self
            .vehicles
            .get(vehicle_id)
            .tours
            .iter()
            .flat_map(|tour| &tour.events)
            .filter(|event| event.overlaps(&interval))
            .map(|event| Box::new(event as &'_ dyn PrimaEvent))
            .collect_vec())
    }

    async fn get_events_for_user(
        &self,
        user_id: UserId,
        time_frame_start: NaiveDateTime,
        time_frame_end: NaiveDateTime,
    ) -> Result<Vec<Box<&'_ dyn PrimaEvent>>, StatusCode> {
        if !self.users.contains_key(&user_id) {
            return Err(StatusCode::NOT_FOUND);
        }
        Ok(self
            .vehicles
            .iter()
            .flat_map(|vehicle| vehicle.tours.iter().flat_map(|tour| &tour.events))
            .filter(|event| {
                event.overlaps(&Interval::new(time_frame_start, time_frame_end))
                    && event.customer == user_id
            })
            .map(|event| Box::new(event as &dyn PrimaEvent))
            .collect_vec())
    }

    async fn get_events_for_tour(
        &self,
        tour_id: TourId,
    ) -> Result<Vec<Box<&'_ dyn PrimaEvent>>, StatusCode> {
        match self.get_tour(tour_id).await {
            Err(e) => return Err(e),
            Ok(tour) => {
                return Ok(tour
                    .events
                    .iter()
                    .map(|event| Box::new(event as &dyn PrimaEvent))
                    .collect_vec())
            }
        };
    }
}
