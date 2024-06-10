use crate::{
    backend::{
        data::Data,
        id_types::{CompanyId, TourId, VehicleId},
        interval::Interval,
        lib::{GetVehicle, PrimaVehicle},
    },
    StatusCode,
};
use async_trait::async_trait;
use itertools::Itertools;

#[async_trait]
impl GetVehicle for Data {
    async fn get_vehicles(
        &self,
        company_id: CompanyId,
    ) -> Result<Vec<Box<&'_ dyn PrimaVehicle>>, StatusCode> {
        Ok(self
            .vehicles
            .iter()
            .filter(|vehicle| vehicle.company == company_id)
            .map(|vehicle| Box::new(vehicle as &'_ dyn PrimaVehicle))
            .collect_vec())
    }

    async fn get_idle_vehicles(
        &self,
        company_id: CompanyId,
        tour_id: TourId,
        consider_provided_tour_conflict: bool,
    ) -> Result<Vec<Box<&'_ dyn PrimaVehicle>>, StatusCode> {
        let tour_interval = match self.get_tour(tour_id).await {
            Ok(t) => Interval::new(t.departure, t.arrival),
            Err(code) => return Err(code),
        };
        Ok(self
            .vehicles
            .iter()
            .filter(|vehicle| {
                vehicle.company == company_id
                    && !vehicle
                        .tours
                        .iter()
                        .filter(|tour| (consider_provided_tour_conflict || tour_id != tour.id))
                        .any(|tour| tour.overlaps(&tour_interval))
            })
            .map(|vehicle| Box::new(vehicle as &dyn PrimaVehicle))
            .collect_vec())
    }

    async fn is_vehicle_idle(
        &self,
        vehicle_id: VehicleId,
        tour_id: TourId,
        consider_provided_tour_conflict: bool,
    ) -> Result<bool, StatusCode> {
        let tour_interval = match self.get_tour(tour_id).await {
            Ok(t) => Interval::new(t.departure, t.arrival),
            Err(code) => return Err(code),
        };
        Ok(!self
            .vehicles
            .get(vehicle_id)
            .tours
            .iter()
            .filter(|tour| (consider_provided_tour_conflict || tour_id != tour.id))
            .any(|tour| tour.overlaps(&tour_interval)))
    }

    async fn is_vehicle_available(
        &self,
        vehicle_id: VehicleId,
        tour_id: TourId,
    ) -> Result<bool, StatusCode> {
        let vehicle = &self.vehicles.get(vehicle_id);
        let tour = match vehicle.tours.iter().find(|tour| tour.id == tour_id) {
            Some(t) => t,
            None => return Err(StatusCode::NOT_FOUND),
        };
        let tour_interval = Interval::new(tour.departure, tour.arrival);
        Ok(vehicle
            .availability
            .iter()
            .any(|(_, availability)| availability.contains(&tour_interval)))
    }
}
