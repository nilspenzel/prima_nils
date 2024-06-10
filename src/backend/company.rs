use crate::backend::{
    id_types::{CompanyId, ZoneId},
    lib::PrimaCompany,
    point::Point,
};
use async_trait::async_trait;

#[derive(PartialEq, Clone, Default)]
#[readonly::make]
pub struct CompanyData {
    pub id: CompanyId,
    pub central_coordinates: Point,
    pub zone: ZoneId,
    pub community: ZoneId,
    pub name: String,
    pub email: String,
}

#[async_trait]
impl PrimaCompany for CompanyData {
    async fn get_id(&self) -> CompanyId {
        self.id
    }

    async fn get_name(&self) -> &str {
        &self.name
    }

    async fn get_email(&self) -> &str {
        &self.email
    }
}

impl CompanyData {
    pub fn new(
        name: &str,
        id: CompanyId,
        central_coordinates: Point,
        zone: ZoneId,
        community: ZoneId,
        email: &str,
    ) -> Self {
        Self {
            name: name.to_string(),
            id,
            central_coordinates,
            zone,
            community,
            email: email.to_string(),
        }
    }

    #[allow(dead_code)]
    pub fn print(
        &self,
        indent: &str,
    ) {
        println!(
            "{}id: {}, lat: {}, lng: {}, zone_id: {}, community: {}, name: {}, email: {}",
            indent,
            self.id,
            self.central_coordinates.get_lat(),
            self.central_coordinates.get_lng(),
            self.zone,
            self.community,
            self.name,
            self.email
        );
    }
}
