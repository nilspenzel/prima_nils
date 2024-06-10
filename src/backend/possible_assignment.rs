use crate::backend::id_types::{CompanyId, VehicleId};
use chrono::NaiveDateTime;

#[derive(PartialEq, Eq, Hash, Clone)]
pub enum TourConcatCase {
    NewTour {
        company_id: CompanyId,
    },
    Prepend {
        vehicle_id: VehicleId,
        next_event_time: NaiveDateTime,
    },
    Append {
        vehicle_id: VehicleId,
        previous_event_time: NaiveDateTime,
    },
    #[allow(dead_code)]
    Insert {
        vehicle_id: VehicleId,
        previous_event_time: NaiveDateTime,
        next_event_time: NaiveDateTime,
    },
}

#[derive(Hash, PartialEq, Eq, Clone)]
pub struct PossibleAssignment {
    pub case: TourConcatCase,
    cost: i32,
    approach_plus_return_distance: i32, // used as tiebreaker, if costs are equal to decide which company gets an assignment.
}

impl PossibleAssignment {
    pub fn new(case: TourConcatCase) -> Self {
        Self {
            case,
            cost: std::i32::MAX,
            approach_plus_return_distance: std::i32::MAX,
        }
    }

    //#[cfg(test)]
    #[allow(dead_code)]
    pub fn print_case(&self) {
        match self.case {
            TourConcatCase::Append {
                vehicle_id: _,
                previous_event_time: _,
            } => println!("append"),
            TourConcatCase::NewTour { company_id: _ } => println!("new tour"),
            TourConcatCase::Prepend {
                vehicle_id: _,
                next_event_time: _,
            } => println!("prepend"),
            TourConcatCase::Insert {
                vehicle_id: _,
                previous_event_time: _,
                next_event_time: _,
            } => println!("insert"),
        }
    }

    pub fn set_distance(
        &mut self,
        approach_duration: i32,
        return_duration: i32,
    ) {
        self.approach_plus_return_distance = approach_duration + return_duration;
    }

    pub fn compute_cost(
        &mut self,
        approach_duration: i32,
        return_duration: i32,
    ) {
        self.cost = approach_duration + return_duration;
    }
}

impl PartialOrd for PossibleAssignment {
    fn partial_cmp(
        &self,
        other: &Self,
    ) -> Option<std::cmp::Ordering> {
        self.cost.partial_cmp(&other.cost).or(self
            .approach_plus_return_distance
            .partial_cmp(&other.approach_plus_return_distance))
    }
}
