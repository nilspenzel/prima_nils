use crate::backend::{
    id_types::{IdT, TourIdT, VehicleIdT},
    interval::Interval,
    lib::{PrimaEvent, PrimaTour},
};
use async_trait::async_trait;
use chrono::NaiveDateTime;

#[derive(Clone, PartialEq)]
#[readonly::make]
pub struct TourData {
    id: TourIdT,
    departure: NaiveDateTime, //departure from taxi central
    arrival: NaiveDateTime,   //arrival at taxi central
    vehicle: VehicleIdT,
    events: Vec<EventData>,
}

#[async_trait]
impl PrimaTour for TourData {
    async fn get_events(&self) -> Vec<Box<&dyn PrimaEvent>> {
        self.events
            .iter()
            .map(|event| Box::new(event as &dyn PrimaEvent))
            .collect_vec()
    }
}

impl TourData {
    #[cfg(test)]
    #[allow(dead_code)]
    fn print(
        &self,
        indent: &str,
    ) {
        println!(
            "{}id: {}, departure: {}, arrival: {}, vehicle: {}",
            indent,
            self.id.id(),
            self.departure,
            self.arrival,
            self.vehicle.id()
        );
    }

    fn overlaps(
        &self,
        interval: &Interval,
    ) -> bool {
        interval.overlaps(&Interval::new(self.departure, self.arrival))
    }
}
