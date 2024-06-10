use sea_orm::{ActiveValue, EntityTrait};

use crate::{
    backend::{
        data::Data,
        id_types::{CompanyId, Id, VehicleId},
        lib::VehicleCrud,
        vehicle::VehicleData,
    },
    entities::{prelude::Vehicle, vehicle},
    error, StatusCode,
};
use async_trait::async_trait;

#[async_trait]
impl VehicleCrud for Data {
    async fn create_vehicle(
        &mut self,
        license_plate: &str,
        company: CompanyId,
    ) -> StatusCode {
        if self.max_company_id() < company.id() {
            return StatusCode::EXPECTATION_FAILED;
        }
        if self
            .vehicles
            .iter()
            .any(|vehicle| vehicle.license_plate == license_plate)
        {
            return StatusCode::CONFLICT;
        }
        let seats = 3;
        let wheelchair_capacity = 0;
        let storage_space = 0;

        match Vehicle::insert(vehicle::ActiveModel {
            id: ActiveValue::NotSet,
            company: ActiveValue::Set(company.id()),
            license_plate: ActiveValue::Set(license_plate.to_string()),
            seats: ActiveValue::Set(seats),
            wheelchair_capacity: ActiveValue::Set(wheelchair_capacity),
            storage_space: ActiveValue::Set(storage_space),
        })
        .exec(&self.db_connection)
        .await
        {
            Ok(result) => {
                self.vehicles.push(VehicleData::new(
                    VehicleId::new(result.last_insert_id),
                    license_plate,
                    company,
                    seats,
                    wheelchair_capacity,
                    storage_space,
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
