use crate::backend::data::ActiveValue;
use crate::backend::data::Data;
use crate::backend::geo_from_str::multi_polygon_from_str;
use crate::backend::id_types::ZoneId;
use crate::backend::lib::ZoneCrud;
use crate::backend::zone::ZoneData;
use crate::entities::prelude::Zone;
use crate::entities::zone;
use crate::error;
use crate::StatusCode;
use async_trait::async_trait;
use sea_orm::EntityTrait;

#[async_trait]
impl ZoneCrud for Data {
    async fn create_zone(
        &mut self,
        name: &str,
        area_str: &str,
    ) -> StatusCode {
        if self.zones.iter().any(|zone| zone.name == name) {
            return StatusCode::CONFLICT;
        }
        let area = match multi_polygon_from_str(area_str) {
            Err(_) => {
                return StatusCode::BAD_REQUEST;
            }
            Ok(mp) => mp,
        };
        match Zone::insert(zone::ActiveModel {
            id: ActiveValue::NotSet,
            name: ActiveValue::Set(name.to_string()),
            area: ActiveValue::Set(area_str.to_string()),
        })
        .exec(&self.db_connection)
        .await
        {
            Err(e) => {
                error!("{e:?}");
                StatusCode::INTERNAL_SERVER_ERROR
            }
            Ok(result) => {
                self.zones.push(ZoneData::new(
                    area,
                    name,
                    ZoneId::new(result.last_insert_id),
                ));
                StatusCode::CREATED
            }
        }
    }
}
