use serde::Serialize;

use crate::backend::point::Point;

use super::lat_long::{Latitude, Longitude};

#[derive(Serialize, Clone, Copy)]
pub struct Coord {
    coordinates: geo::Coord,
}

impl Coord {
    pub fn from(p: Point) -> Self {
        Self {
            coordinates: geo::Coord::from(p.p()),
        }
    }

    #[allow(dead_code)]
    pub fn new(
        lat: Latitude,
        lng: Longitude,
    ) -> Self {
        Self::from(Point::new(lat, lng))
    }

    pub fn get_coord(&self) -> geo::Coord {
        self.coordinates
    }
}
