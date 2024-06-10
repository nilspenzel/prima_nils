use geo::GeodesicDistance;
use tracing::info;

use super::lat_long::{Latitude, Longitude};

#[derive(PartialEq, Clone, Default, Copy)]
pub struct Point {
    p: geo::Point,
}

impl Point {
    pub fn new(
        latitude: Latitude,
        longitude: Longitude,
    ) -> Self {
        #[cfg(test)]
        assert!(latitude > longitude);
        Self {
            p: geo::Point::new(longitude.v64(), latitude.v64()),
        }
    }

    pub fn from(p: geo::Point) -> Self {
        #[cfg(test)]
        assert!(p.y() > p.x());
        if p.x() > p.y() {
            info!("Creating Point with longitude > latiude.");
        }
        Self { p }
    }

    pub fn geodesic_distance(
        &self,
        other: &Point,
    ) -> f64 {
        self.p.geodesic_distance(&other.p)
    }

    #[cfg(test)]
    #[allow(dead_code)]
    pub fn print_point(&self) {
        println!(
            "latitude: {}, longitude: {}",
            self.get_lat(),
            self.get_lng()
        );
    }

    pub fn get_lat(&self) -> Latitude {
        Latitude::from(self.p.y())
    }

    pub fn get_lng(&self) -> Longitude {
        Longitude::from(self.p.x())
    }

    pub fn p(&self) -> geo::Point {
        self.p
    }
}
