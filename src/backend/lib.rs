use crate::backend::id_types::{AddressId, CompanyId, EventId, TourId, UserId, VehicleId, ZoneId};
use async_trait::async_trait;
use chrono::NaiveDateTime;
use hyper::StatusCode;
use std::collections::HashMap;

use super::lat_long::{Latitude, Longitude};

/*
StatusCode and associated errors/results:
INTERNAL_SERVER_ERROR           something bad happened
BAD_REQUEST                     invalid geojson for multipolygon (area of zone), or provided ids do not match, or invalid user role
EXPECTATION_FAILED              foreign key violation
CONFLICT                        unique key violation
NO_CONTENT                      used in remove_interval and handle_request, request did not produce an error but did not change anything either (in case of request->denied)
NOT_ACCEPTABLE                  provided interval is not valid, or request is in the past, or trying to remove availability needed for a tour
NOT_FOUND                       data with provided id was not found
CREATED                         request processed succesfully, data has been created
OK                              request processed succesfully
*/

#[async_trait]
pub trait PrimaTour {
    async fn get_events(&self) -> Vec<Box<&dyn PrimaEvent>>;
    fn get_id(&self) -> TourId;
}

#[async_trait]
pub trait PrimaEvent: Send + Sync {
    async fn get_id(&self) -> EventId;
    async fn get_lat(&self) -> Latitude;
    async fn get_lng(&self) -> Longitude;
    async fn get_customer_id(&self) -> UserId;
    async fn get_address_id(&self) -> AddressId;
}

#[async_trait]
pub trait PrimaVehicle: Send + Sync {
    async fn get_id(&self) -> VehicleId;
    async fn get_license_plate(&self) -> &str;
    async fn get_company_id(&self) -> CompanyId;
    async fn get_tours(&self) -> Vec<Box<&dyn PrimaTour>>;
}

#[async_trait]
pub trait PrimaUser: Send + Sync {
    async fn get_id(&self) -> UserId;
    async fn get_name(&self) -> &str;
    async fn is_driver(&self) -> bool;
    async fn is_disponent(&self) -> bool;
    async fn is_admin(&self) -> bool;
    async fn get_company_id(&self) -> &Option<CompanyId>;
    async fn get_email(&self) -> &str;
}

#[async_trait]
pub trait PrimaCompany {
    async fn get_id(&self) -> CompanyId;
    async fn get_name(&self) -> &str;
    async fn get_email(&self) -> &str;
}

#[async_trait]
pub trait PrimaData:
    Send
    + Sync
    + ZoneCrud
    + CompanyCrud
    + VehicleCrud
    + UserCrud
    + AvailabilityCrud
    + GetEvents
    + GetConflicts
    + GetVehicle
{
    async fn read_data_from_db(&mut self);

    async fn change_vehicle_for_tour(
        &mut self,
        tour_id: TourId,
        new_vehicle_id: VehicleId,
    ) -> StatusCode;

    async fn get_user(
        &self,
        user_id: UserId,
    ) -> Result<Box<&dyn PrimaUser>, StatusCode>;

    async fn get_address(
        &self,
        address_id: AddressId,
    ) -> &str;

    async fn get_tours(
        &self,
        vehicle_id: VehicleId,
        time_frame_start: NaiveDateTime,
        time_frame_end: NaiveDateTime,
    ) -> Result<Vec<Box<&dyn PrimaTour>>, StatusCode>;

    async fn get_customer_for_event(
        &self,
        event: &dyn PrimaEvent,
    ) -> Result<Box<&dyn PrimaUser>, StatusCode> {
        self.get_user(event.get_customer_id().await).await
    }

    async fn get_address_for_event(
        &self,
        event: &dyn PrimaEvent,
    ) -> &str {
        self.get_address(event.get_address_id().await).await
    }
}

#[async_trait]
pub trait ZoneCrud {
    async fn create_zone(
        &mut self,
        name: &str,
        area_str: &str,
    ) -> StatusCode;
}

#[async_trait]
pub trait CompanyCrud {
    async fn create_company(
        &mut self,
        name: &str,
        zone: ZoneId,
        community_area: ZoneId,
        email: &str,
        lat: Latitude,
        lng: Longitude,
    ) -> StatusCode;
}

#[async_trait]
pub trait VehicleCrud {
    async fn create_vehicle(
        &mut self,
        license_plate: &str,
        company: CompanyId,
    ) -> StatusCode;
}

#[async_trait]
pub trait UserCrud {
    #[allow(clippy::too_many_arguments)]
    async fn create_user(
        &mut self,
        name: &str,
        is_driver: bool,
        is_disponent: bool,
        company: Option<CompanyId>,
        is_admin: bool,
        email: &str,
        password: Option<String>,
        salt: &str,
        o_auth_id: Option<String>,
        o_auth_provider: Option<String>,
    ) -> StatusCode;
}

#[async_trait]
pub trait AvailabilityCrud {
    async fn create_availability(
        &mut self,
        start_time: NaiveDateTime,
        end_time: NaiveDateTime,
        vehicle: VehicleId,
    ) -> StatusCode;

    async fn remove_availability(
        &mut self,
        start_time: NaiveDateTime,
        end_time: NaiveDateTime,
        vehicle_id: VehicleId,
    ) -> StatusCode;
}

#[async_trait]
pub trait GetEvents {
    async fn get_events_for_vehicle(
        &self,
        vehicle_id: VehicleId,
        time_frame_start: NaiveDateTime,
        time_frame_end: NaiveDateTime,
    ) -> Result<Vec<Box<&dyn PrimaEvent>>, StatusCode>;

    async fn get_events_for_user(
        &self,
        user_id: UserId,
        time_frame_start: NaiveDateTime,
        time_frame_end: NaiveDateTime,
    ) -> Result<Vec<Box<&dyn PrimaEvent>>, StatusCode>;

    async fn get_events_for_tour(
        &self,
        tour_id: TourId,
    ) -> Result<Vec<Box<&dyn PrimaEvent>>, StatusCode>;
}

#[async_trait]
pub trait GetConflicts {
    async fn get_company_conflicts(
        &self,
        company_id: CompanyId,
        tour_id: TourId,
        consider_provided_tour_conflict: bool,
    ) -> Result<HashMap<VehicleId, Vec<Box<&dyn PrimaTour>>>, StatusCode>;

    async fn get_vehicle_conflicts(
        &self,
        vehicle_id: VehicleId,
        tour_id: TourId,
        consider_provided_tour_conflict: bool,
    ) -> Result<Vec<Box<&dyn PrimaTour>>, StatusCode>;

    async fn get_tour_conflicts(
        &self,
        event_id: EventId,
        company_id: Option<CompanyId>,
    ) -> Result<Vec<Box<&dyn PrimaTour>>, StatusCode>;
}

#[async_trait]
pub trait GetCompany {
    async fn get_company(
        &self,
        company_id: CompanyId,
    ) -> Result<Box<&dyn PrimaCompany>, StatusCode>;

    async fn get_company_for_user(
        &self,
        user: &dyn PrimaUser,
    ) -> Option<Result<Box<&dyn PrimaCompany>, StatusCode>> {
        match user.get_company_id().await {
            None => None,
            Some(company_id) => Some(self.get_company(*company_id).await),
        }
    }

    async fn get_company_for_vehicle(
        &self,
        vehicle: &dyn PrimaVehicle,
    ) -> Result<Box<&dyn PrimaCompany>, StatusCode> {
        self.get_company(vehicle.get_company_id().await).await
    }
}

#[async_trait]
pub trait GetVehicle {
    async fn get_vehicles(
        &self,
        company_id: CompanyId,
    ) -> Result<Vec<Box<&dyn PrimaVehicle>>, StatusCode>;

    async fn get_idle_vehicles(
        &self,
        company_id: CompanyId,
        tour_id: TourId,
        consider_provided_tour_conflict: bool,
    ) -> Result<Vec<Box<&dyn PrimaVehicle>>, StatusCode>;

    async fn is_vehicle_idle(
        &self,
        vehicle_id: VehicleId,
        tour_id: TourId,
        consider_provided_tour_conflict: bool,
    ) -> Result<bool, StatusCode>;

    async fn is_vehicle_available(
        &self,
        vehicle: VehicleId,
        tour_id: TourId,
    ) -> Result<bool, StatusCode>;
}

#[async_trait]
pub trait HandleRequest {
    #[allow(clippy::too_many_arguments)]
    async fn handle_routing_request(
        &mut self,
        fixed_time: NaiveDateTime,
        is_start_time_fixed: bool,
        start_lat: Latitude,
        start_lng: Longitude,
        target_lat: Latitude,
        target_lng: Longitude,
        customer: UserId,
        passengers: i32,
        start_address: &str,
        target_address: &str,
    ) -> StatusCode;
}

#[async_trait]
pub trait TourCrud {
    #[allow(clippy::too_many_arguments)]
    async fn insert_or_addto_tour(
        &mut self,
        tour_id: Option<TourId>, // tour_id == None <=> tour already exists
        departure: NaiveDateTime,
        arrival: NaiveDateTime,
        vehicle: VehicleId,
        start_address: &str,
        target_address: &str,
        lat_start: Latitude,
        lng_start: Longitude,
        sched_t_start: NaiveDateTime,
        comm_t_start: NaiveDateTime,
        customer: UserId,
        passengers: i32,
        wheelchairs: i32,
        luggage: i32,
        lat_target: Latitude,
        lng_target: Longitude,
        sched_t_target: NaiveDateTime,
        comm_t_target: NaiveDateTime,
    ) -> StatusCode;
}
