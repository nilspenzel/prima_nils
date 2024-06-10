use crate::{
    backend::{
        data::Data,
        data::{error, ActiveValue, Point},
        event::EventData,
        helpers::is_valid,
        id_types::{AddressId, EventId, Id, TourId, UserId, VehicleId},
        interval::Interval,
        lat_long::{Latitude, Longitude},
        lib::TourCrud,
        tour::TourData,
    },
    entities::{
        event,
        prelude::{Event, Tour},
        tour,
    },
    StatusCode,
};
use async_trait::async_trait;
use chrono::NaiveDateTime;
use sea_orm::EntityTrait;

#[async_trait]
impl TourCrud for Data {
    #[allow(clippy::too_many_arguments)]
    async fn insert_or_addto_tour(
        &mut self,
        tour_id: Option<TourId>, // tour_id == None <=> tour already exists
        departure: NaiveDateTime,
        arrival: NaiveDateTime,
        vehicle: VehicleId,
        start_address: &str,
        target_address: &str,
        lat_start: Latitude,
        lng_start: Longitude,
        sched_t_start: NaiveDateTime,
        comm_t_start: NaiveDateTime,
        customer: UserId,
        passengers: i32,
        wheelchairs: i32,
        luggage: i32,
        lat_target: Latitude,
        lng_target: Longitude,
        sched_t_target: NaiveDateTime,
        comm_t_target: NaiveDateTime,
    ) -> StatusCode {
        if !is_valid(&Interval::new(departure, arrival))
            || !is_valid(&Interval::new(sched_t_start, sched_t_target))
        {
            return StatusCode::NOT_ACCEPTABLE;
        }
        if !self.users.contains_key(&customer) || self.max_vehicle_id() < vehicle.id() {
            return StatusCode::EXPECTATION_FAILED;
        }
        let id = match tour_id {
            Some(t_id) => {
                if self.get_n_tours() < t_id.id() {
                    return StatusCode::EXPECTATION_FAILED;
                }
                t_id
            }
            None => {
                let t_id = TourId::new(
                    match Tour::insert(tour::ActiveModel {
                        id: ActiveValue::NotSet,
                        departure: ActiveValue::Set(departure),
                        arrival: ActiveValue::Set(arrival),
                        vehicle: ActiveValue::Set(vehicle.id()),
                    })
                    .exec(&self.db_connection)
                    .await
                    {
                        Ok(result) => result.last_insert_id,
                        Err(e) => {
                            error!("Error creating tour: {e:?}");
                            return StatusCode::INTERNAL_SERVER_ERROR;
                        }
                    },
                );
                self.vehicles
                    .get_mut(vehicle)
                    .tours
                    .push(TourData::new(t_id, arrival, departure, vehicle));
                t_id
            }
        };
        let start_address_id = self.find_or_create_address(start_address).await.unwrap();
        let target_address_id = self.find_or_create_address(target_address).await.unwrap();
        let request_id = match self
            .insert_request_into_db(passengers, wheelchairs, luggage, &customer, &id)
            .await
        {
            Err(e) => return e,
            Ok(r_id) => r_id,
        };

        let pickup_event_id = EventId::new(
            match Event::insert(event::ActiveModel {
                id: ActiveValue::NotSet,
                longitude: ActiveValue::Set(lng_start.v()),
                latitude: ActiveValue::Set(lat_start.v()),
                scheduled_time: ActiveValue::Set(sched_t_start),
                communicated_time: ActiveValue::Set(comm_t_start),
                request: ActiveValue::Set(request_id),
                is_pickup: ActiveValue::Set(true),
                address: ActiveValue::Set(start_address_id),
            })
            .exec(&self.db_connection)
            .await
            {
                Ok(pickup_result) => pickup_result.last_insert_id,
                Err(e) => {
                    error!("Error creating event: {e:?}");
                    return StatusCode::INTERNAL_SERVER_ERROR;
                }
            },
        );
        let dropoff_event_id = EventId::new(
            match Event::insert(event::ActiveModel {
                id: ActiveValue::NotSet,
                longitude: ActiveValue::Set(lng_target.v()),
                latitude: ActiveValue::Set(lat_target.v()),
                scheduled_time: ActiveValue::Set(sched_t_target),
                communicated_time: ActiveValue::Set(comm_t_target),
                request: ActiveValue::Set(request_id),
                is_pickup: ActiveValue::Set(false),
                address: ActiveValue::Set(target_address_id),
            })
            .exec(&self.db_connection)
            .await
            {
                Ok(dropoff_result) => dropoff_result.last_insert_id,
                Err(e) => {
                    error!("Error creating event: {e:?}");
                    return StatusCode::INTERNAL_SERVER_ERROR;
                }
            },
        );
        let tour = &mut self.vehicles.get_mut(vehicle).get_tour(id).await.unwrap();
        let events = &mut tour.events;
        //pickup-event
        events.push(EventData::new(
            pickup_event_id,
            Point::new(lat_start, lng_start),
            sched_t_start,
            comm_t_start,
            customer,
            passengers,
            wheelchairs,
            luggage,
            id,
            request_id,
            true,
            AddressId::new(start_address_id),
        ));
        //dropoff-event
        events.push(EventData::new(
            dropoff_event_id,
            Point::new(lat_target, lng_target),
            sched_t_target,
            comm_t_target,
            customer,
            passengers,
            wheelchairs,
            luggage,
            id,
            request_id,
            false,
            AddressId::new(target_address_id),
        ));
        StatusCode::CREATED
    }
}
