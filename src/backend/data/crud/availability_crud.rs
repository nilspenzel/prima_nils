use crate::{
    backend::{
        data::Data,
        helpers::is_valid,
        id_types::{Id, VehicleId},
        interval::Interval,
        lib::AvailabilityCrud,
    },
    entities::prelude::Availability,
    error, StatusCode,
};
use async_trait::async_trait;
use chrono::NaiveDateTime;
use sea_orm::EntityTrait;

#[async_trait]
impl AvailabilityCrud for Data {
    async fn create_availability(
        &mut self,
        start_time: NaiveDateTime,
        end_time: NaiveDateTime,
        vehicle: VehicleId,
    ) -> StatusCode {
        let mut interval = Interval::new(start_time, end_time);
        if !is_valid(&interval) {
            // return StatusCode::NOT_ACCEPTABLE;
        }
        self.vehicles
            .get_mut(vehicle)
            .add_availability(&self.db_connection, &mut interval, None)
            .await
    }

    async fn remove_availability(
        &mut self,
        start_time: NaiveDateTime,
        end_time: NaiveDateTime,
        vehicle_id: VehicleId,
    ) -> StatusCode {
        let to_remove_interval = Interval::new(start_time, end_time);
        if !is_valid(&to_remove_interval) {
            return StatusCode::NOT_ACCEPTABLE;
        }
        let mut mark_delete: Vec<i32> = Vec::new();
        let mut to_insert = Vec::<Interval>::new();
        let vehicle = &mut self.vehicles.get_mut(vehicle_id);
        let mut altered = false;
        for (id, existing) in vehicle.availability.iter_mut() {
            if !existing.overlaps(&to_remove_interval) {
                continue;
            }
            altered = true;
            if existing.is_contained(&to_remove_interval) {
                mark_delete.push(*id);
                continue;
            }
            if existing.contains(&to_remove_interval) {
                mark_delete.push(*id);
                let (left, right) = existing.split(&to_remove_interval);
                to_insert.push(left);
                to_insert.push(right);
                break;
            }
            if existing.overlaps(&to_remove_interval) {
                mark_delete.push(*id);
                to_insert.push(existing.cut(&to_remove_interval));
            }
        }
        if !altered {
            return StatusCode::NO_CONTENT; //no error occured but the transmitted interval did not touch any availabilites for the transmitted vehicle
        }
        for to_delete in mark_delete {
            match Availability::delete_by_id(vehicle.availability[&to_delete].get_id().id())
                .exec(&self.db_connection)
                .await
            {
                Ok(_) => {
                    vehicle.availability.remove(&to_delete);
                }
                Err(e) => {
                    error!("Error deleting interval: {e:?}");
                    return StatusCode::INTERNAL_SERVER_ERROR;
                }
            }
        }
        for insert_interval in to_insert.iter() {
            self.create_availability(
                insert_interval.start_time,
                insert_interval.end_time,
                vehicle_id,
            )
            .await;
        }
        StatusCode::OK
    }
}
