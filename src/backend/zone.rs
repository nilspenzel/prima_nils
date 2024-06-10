use crate::backend::id_types::ZoneId;
use geo::{Contains, MultiPolygon, Point};

#[derive(PartialEq, Clone)]
#[readonly::make]
pub struct ZoneData {
    pub area: MultiPolygon,
    pub name: String,
    pub id: ZoneId,
}

impl ZoneData {
    pub fn new(
        area: MultiPolygon,
        name: &str,
        id: ZoneId,
    ) -> Self {
        Self {
            area,
            name: name.to_string(),
            id,
        }
    }

    pub fn contains(
        &self,
        p: &Point,
    ) -> bool {
        self.area.contains(p)
    }

    #[allow(dead_code)]
    pub fn print(
        &self,
        indent: &str,
    ) {
        println!("{}id: {}, name: {}", indent, self.id, self.name);
    }
}
