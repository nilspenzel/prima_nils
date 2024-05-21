use crate::backend::interval::Interval;

#[derive(Debug, Clone, Eq, PartialEq)]
#[readonly::make]
pub struct AvailabilityData {
    id: i32,
    interval: Interval,
}

#[cfg(test)]
impl AvailabilityData {
    #[cfg(test)]
    #[allow(dead_code)]
    fn print(
        &self,
        indent: &str,
    ) {
        println!("{}id: {}, interval: {}", indent, self.id, self.interval);
    }
}
