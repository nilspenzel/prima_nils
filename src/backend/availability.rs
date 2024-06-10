use crate::backend::{id_types::AvailabilityId, interval::Interval};

#[derive(Debug, Clone, Eq, PartialEq)]
#[readonly::make]
pub struct AvailabilityData {
    id: AvailabilityId,
    interval: Interval,
}

impl AvailabilityData {
    pub fn new(
        id: AvailabilityId,
        interval: Interval,
    ) -> Self {
        Self { id, interval }
    }

    pub fn get_id(&self) -> AvailabilityId {
        self.id
    }

    pub fn overlaps(
        &self,
        interval: &Interval,
    ) -> bool {
        self.interval.overlaps(interval)
    }

    pub fn contains(
        &self,
        interval: &Interval,
    ) -> bool {
        self.interval.contains(interval)
    }

    pub fn is_contained(
        &self,
        interval: &Interval,
    ) -> bool {
        interval.contains(&self.interval)
    }

    pub fn split(
        &self,
        interval: &Interval,
    ) -> (Interval, Interval) {
        self.interval.split(interval)
    }

    pub fn cut(
        &self,
        interval: &Interval,
    ) -> Interval {
        self.interval.cut(interval)
    }

    pub fn merge(
        &self,
        interval: &Interval,
    ) -> Interval {
        self.interval.merge(interval)
    }

    pub fn touches(
        &self,
        interval: &Interval,
    ) -> bool {
        self.interval.touches(interval)
    }

    #[allow(dead_code)]
    pub fn print(
        &self,
        indent: &str,
    ) {
        println!("{}id: {}, interval: {}", indent, self.id, self.interval);
    }
}

impl std::cmp::PartialEq<Interval> for AvailabilityData {
    fn eq(
        &self,
        other: &Interval,
    ) -> bool {
        self.interval == *other
    }
}
