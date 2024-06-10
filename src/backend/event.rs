use crate::backend::{
    id_types::{AddressId, EventId, TourId, UserId},
    interval::Interval,
    lib::PrimaEvent,
    point::Point,
};
use async_trait::async_trait;
use chrono::NaiveDateTime;
use core::cmp::{max, min};

use super::lat_long::{Latitude, Longitude};

#[derive(Clone, PartialEq)]
pub struct EventData {
    pub id: EventId,
    pub coordinates: Point,
    pub scheduled_time: NaiveDateTime,
    pub communicated_time: NaiveDateTime,
    pub customer: UserId,
    pub tour: TourId,
    pub passengers: i32,
    pub wheelchairs: i32,
    pub luggage: i32,
    pub request_id: i32,
    pub is_pickup: bool,
    pub address_id: AddressId,
}

#[async_trait]
impl PrimaEvent for EventData {
    async fn get_id(&self) -> EventId {
        self.id
    }

    async fn get_customer_id(&self) -> UserId {
        self.customer
    }

    async fn get_lat(&self) -> Latitude {
        self.coordinates.get_lat()
    }

    async fn get_lng(&self) -> Longitude {
        self.coordinates.get_lng()
    }

    async fn get_address_id(&self) -> AddressId {
        self.address_id
    }
}

impl EventData {
    #[allow(clippy::too_many_arguments)]
    pub fn new(
        id: EventId,
        coordinates: Point,
        scheduled_time: NaiveDateTime,
        communicated_time: NaiveDateTime,
        customer: UserId,
        passengers: i32,
        wheelchairs: i32,
        luggage: i32,
        tour: TourId,
        request_id: i32,
        is_pickup: bool,
        address_id: AddressId,
    ) -> Self {
        Self {
            id,
            coordinates,
            scheduled_time,
            communicated_time,
            customer,
            passengers,
            wheelchairs,
            luggage,
            tour,
            request_id,
            is_pickup,
            address_id,
        }
    }

    pub fn overlaps(
        &self,
        interval: &Interval,
    ) -> bool {
        interval.overlaps(&Interval::new(
            min(self.communicated_time, self.scheduled_time),
            max(self.communicated_time, self.scheduled_time),
        ))
    }

    #[allow(dead_code)]
    pub fn print(
        &self,
        indent: &str,
    ) {
        println!(
            "{}id: {}, scheduled_time: {}, communicated_time: {}, customer: {}, tour: {}, request_id: {}, passengers: {}, wheelchairs: {}, luggage: {}, is_pickup: {}, address_id: {}, lat: {}, lng: {}",
            indent, self.id, self.scheduled_time, self.communicated_time, self.customer, self.tour, self.request_id, self.passengers, self.wheelchairs, self.luggage, self.is_pickup, self.address_id, self.coordinates.get_lat(), self.coordinates.get_lng()
        );
    }
}
