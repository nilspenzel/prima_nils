use crate::backend::{
    event::EventData,
    id_types::{TourId, VehicleId},
    interval::Interval,
    lib::{PrimaEvent, PrimaTour},
};
use async_trait::async_trait;
use chrono::NaiveDateTime;
use itertools::Itertools;

#[derive(Clone, PartialEq, Default)]
pub struct TourData {
    pub id: TourId,
    pub departure: NaiveDateTime, // departure from taxi central
    pub arrival: NaiveDateTime,   // arrival at taxi central
    pub vehicle: VehicleId,
    pub events: Vec<EventData>,
}

#[async_trait]
impl PrimaTour for TourData {
    async fn get_events(&self) -> Vec<Box<&dyn PrimaEvent>> {
        self.events
            .iter()
            .map(|event| Box::new(event as &dyn PrimaEvent))
            .collect_vec()
    }

    fn get_id(&self) -> TourId {
        self.id
    }
}

impl TourData {
    pub fn new(
        id: TourId,
        arrival: NaiveDateTime,
        departure: NaiveDateTime,
        vehicle: VehicleId,
    ) -> Self {
        Self {
            arrival,
            departure,
            id,
            vehicle,
            events: Vec::new(),
        }
    }

    pub fn overlaps(
        &self,
        interval: &Interval,
    ) -> bool {
        interval.overlaps(&Interval::new(self.departure, self.arrival))
    }

    #[allow(dead_code)]
    pub fn print(
        &self,
        indent: &str,
    ) {
        println!(
            "{}id: {}, departure: {}, arrival: {}, vehicle: {}",
            indent, self.id, self.departure, self.arrival, self.vehicle
        );
    }
}
