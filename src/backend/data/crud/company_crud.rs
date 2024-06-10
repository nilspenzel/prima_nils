use crate::{
    backend::{
        company::CompanyData,
        data::ActiveValue,
        data::Data,
        id_types::ZoneId,
        id_types::{CompanyId, Id},
        lat_long::{Latitude, Longitude},
        lib::CompanyCrud,
        point::Point,
    },
    entities::{company, prelude::Company},
    error, StatusCode,
};
use async_trait::async_trait;
use sea_orm::EntityTrait;

#[async_trait]
impl CompanyCrud for Data {
    async fn create_company(
        &mut self,
        name: &str,
        zone: ZoneId,
        community_area: ZoneId,
        email: &str,
        lat: Latitude,
        lng: Longitude,
    ) -> StatusCode {
        if self.max_zone_id() < zone.id() {
            return StatusCode::EXPECTATION_FAILED;
        }
        if self.companies.iter().any(|company| company.email == email) {
            return StatusCode::CONFLICT;
        }
        match Company::insert(company::ActiveModel {
            id: ActiveValue::NotSet,
            longitude: ActiveValue::Set(lng.v()),
            latitude: ActiveValue::Set(lat.v()),
            display_name: ActiveValue::Set(name.to_string()),
            zone: ActiveValue::Set(zone.id()),
            email: ActiveValue::Set(email.to_string()),
            community_area: ActiveValue::Set(community_area.id()),
        })
        .exec(&self.db_connection)
        .await
        {
            Ok(result) => {
                self.companies.push(CompanyData::new(
                    name,
                    CompanyId::new(result.last_insert_id),
                    Point::new(lat, lng),
                    zone,
                    community_area,
                    email,
                ));
                StatusCode::CREATED
            }
            Err(e) => {
                error!("{e:?}");
                StatusCode::INTERNAL_SERVER_ERROR
            }
        }
    }
}
