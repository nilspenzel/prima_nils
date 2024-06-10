use super::{
    geo_from_str::multi_polygon_from_str,
    lat_long::{Latitude, Longitude},
};
use crate::{
    backend::{
        address::AddressData,
        company::CompanyData,
        coord::Coord,
        event::EventData,
        id_types::{AddressId, CompanyId, EventId, Id, TourId, UserId, VecMap, VehicleId, ZoneId},
        interval::Interval,
        lib::{PrimaData, PrimaTour, PrimaUser},
        point::Point,
        tour::TourData,
        user::UserData,
        vehicle::VehicleData,
        zone::ZoneData,
    },
    entities::{
        address, availability, company, event,
        prelude::{Address, Availability, Company, Event, Request, Tour, User, Vehicle, Zone},
        request, tour, vehicle, zone,
    },
    error,
    osrm::OSRM,
    StatusCode,
};
use ::anyhow::Result;
use async_trait::async_trait;
use chrono::NaiveDateTime;
use itertools::Itertools;
use sea_orm::DbConn;
use sea_orm::{ActiveModelTrait, ActiveValue, EntityTrait};
use std::collections::HashMap;
use tracing::info;

mod crud;
mod get;
mod handle_request;

#[readonly::make]
pub struct Data {
    users: HashMap<UserId, UserData>,
    zones: VecMap<ZoneId, ZoneData>,
    companies: VecMap<CompanyId, CompanyData>,
    vehicles: VecMap<VehicleId, VehicleData>,
    addresses: VecMap<AddressId, AddressData>,
    db_connection: DbConn,
    osrm: OSRM,
}

impl PartialEq for Data {
    fn eq(
        &self,
        other: &Data,
    ) -> bool {
        self.users == other.users
            && self.zones == other.zones
            && self.companies == other.companies
            && self.vehicles == other.vehicles
    }
}

#[async_trait]
impl PrimaData for Data {
    async fn get_address(
        &self,
        address_id: AddressId,
    ) -> &str {
        &self.addresses.get(address_id).address
    }

    async fn read_data_from_db(&mut self) {
        let mut address_models: Vec<address::Model> = Address::find()
            .all(&self.db_connection)
            .await
            .expect("Error while reading from Database.");
        address_models.sort_by_key(|a| a.id);
        for a in address_models.iter() {
            self.addresses.push(AddressData {
                id: AddressId::new(a.id),
                address: a.address_string.to_string(),
            });
        }

        let mut zones: Vec<zone::Model> = Zone::find()
            .all(&self.db_connection)
            .await
            .expect("Error while reading from Database.");
        zones.sort_by_key(|z| z.id);
        for zone in zones.iter() {
            match multi_polygon_from_str(&zone.area) {
                Err(e) => error!("{e:?}"),
                Ok(mp) => self
                    .zones
                    .push(ZoneData::new(mp, &zone.name, ZoneId::new(zone.id))),
            }
        }

        let company_models: Vec<<company::Entity as sea_orm::EntityTrait>::Model> = Company::find()
            .all(&self.db_connection)
            .await
            .expect("Error while reading from Database.");
        self.companies
            .resize(company_models.len(), CompanyData::default());
        for company_model in company_models {
            let company_id = CompanyId::new(company_model.id);
            self.companies.set(
                company_id,
                CompanyData::new(
                    &company_model.display_name,
                    company_id,
                    Point::new(
                        Latitude::new(company_model.latitude),
                        Longitude::new(company_model.longitude),
                    ),
                    ZoneId::new(company_model.zone),
                    ZoneId::new(company_model.community_area),
                    &company_model.email,
                ),
            );
        }

        let mut vehicle_models: Vec<<vehicle::Entity as sea_orm::EntityTrait>::Model> =
            Vehicle::find()
                .all(&self.db_connection)
                .await
                .expect("Error while reading from Database.");
        self.vehicles
            .resize(vehicle_models.len(), VehicleData::default());
        vehicle_models.sort_by_key(|v| v.id);
        for vehicle in vehicle_models.iter() {
            let vehicle_id = VehicleId::new(vehicle.id);
            self.vehicles.set(
                vehicle_id,
                VehicleData::new(
                    vehicle_id,
                    &vehicle.license_plate,
                    CompanyId::new(vehicle.company),
                    vehicle.seats,
                    vehicle.wheelchair_capacity,
                    vehicle.storage_space,
                ),
            );
        }

        let availability_models: Vec<<availability::Entity as sea_orm::EntityTrait>::Model> =
            Availability::find()
                .all(&self.db_connection)
                .await
                .expect("Error while reading from Database.");
        for availability in availability_models.iter() {
            self.vehicles
                .get_mut(VehicleId::new(availability.vehicle))
                .add_availability(
                    &self.db_connection,
                    &mut Interval::new(availability.start_time, availability.end_time),
                    Some(availability.id),
                )
                .await;
        }

        let tour_models: Vec<<tour::Entity as sea_orm::EntityTrait>::Model> = Tour::find()
            .all(&self.db_connection)
            .await
            .expect("Error while reading from Database.");
        for tour in tour_models {
            let vehicle_id = VehicleId::new(tour.vehicle);
            self.vehicles.get_mut(vehicle_id).tours.push(TourData::new(
                TourId::new(tour.id),
                tour.arrival,
                tour.departure,
                vehicle_id,
            ));
        }
        let event_models: Vec<<event::Entity as sea_orm::EntityTrait>::Model> = Event::find()
            .all(&self.db_connection)
            .await
            .expect("Error while reading from Database.");
        for event_m in event_models {
            let request_m: <request::Entity as sea_orm::EntityTrait>::Model =
                Request::find_by_id(event_m.request)
                    .one(&self.db_connection)
                    .await
                    .expect("Error while reading from Database.")
                    .unwrap();
            let tour_id = TourId::new(request_m.tour);
            let vehicle_id = self.get_tour(tour_id).await.unwrap().vehicle;
            self.vehicles
                .get_mut(vehicle_id)
                .get_tour(tour_id)
                .await
                .unwrap()
                .events
                .push(EventData::new(
                    EventId::new(event_m.id),
                    Point::new(
                        Latitude::new(event_m.latitude),
                        Longitude::new(event_m.longitude),
                    ),
                    event_m.scheduled_time,
                    event_m.communicated_time,
                    UserId::new(request_m.customer),
                    request_m.passengers,
                    request_m.wheelchairs,
                    request_m.luggage,
                    tour_id,
                    event_m.request,
                    event_m.is_pickup,
                    AddressId::new(event_m.address),
                ));
        }

        let user_models = User::find()
            .all(&self.db_connection)
            .await
            .expect("Error while reading from Database.");
        for user_model in user_models {
            let user_id = UserId::new(user_model.id);
            self.users.insert(
                user_id,
                UserData::new(
                    user_id,
                    &user_model.display_name,
                    user_model.is_driver,
                    user_model.is_disponent,
                    user_model.company.map(CompanyId::new),
                    user_model.is_admin,
                    &user_model.email,
                    user_model.password,
                    &user_model.salt,
                    user_model.o_auth_id,
                    user_model.o_auth_provider,
                ),
            );
        }
    }

    async fn change_vehicle_for_tour(
        &mut self,
        tour_id: TourId,
        new_vehicle_id: VehicleId,
    ) -> StatusCode {
        let old_vehicle_id = match self.get_tour(tour_id).await {
            Ok(tour) => tour.vehicle,
            Err(e) => return e,
        };
        if old_vehicle_id == new_vehicle_id {
            return StatusCode::NO_CONTENT;
        }
        let tour_idx = self
            .vehicles
            .get(old_vehicle_id)
            .tours
            .iter()
            .enumerate()
            .find(|(_, tour)| tour.id == tour_id)
            .map(|(pos, _)| pos)
            .unwrap();
        let mut moved_tour = self.vehicles.get_mut(old_vehicle_id).tours.remove(tour_idx);
        moved_tour.vehicle = new_vehicle_id;
        self.vehicles.get_mut(new_vehicle_id).tours.push(moved_tour);

        let mut active_m: tour::ActiveModel = match Tour::find_by_id(tour_id.id())
            .one(&self.db_connection)
            .await
        {
            Err(e) => {
                error!("{e:?}");
                return StatusCode::INTERNAL_SERVER_ERROR;
            }
            Ok(m) => match m {
                None => return StatusCode::INTERNAL_SERVER_ERROR,
                Some(model) => (model as tour::Model).into(),
            },
        };
        active_m.vehicle = ActiveValue::Set(new_vehicle_id.id());
        match active_m.update(&self.db_connection).await {
            Ok(_) => (),
            Err(e) => {
                error!("{}", e);
                return StatusCode::INTERNAL_SERVER_ERROR;
            }
        }
        StatusCode::OK
    }

    async fn get_user(
        &self,
        user_id: UserId,
    ) -> Result<Box<&dyn PrimaUser>, StatusCode> {
        if !self.users.contains_key(&user_id) {
            return Err(StatusCode::NOT_FOUND);
        }
        Ok(Box::new(&self.users[&user_id]))
    }

    async fn get_tours(
        &self,
        vehicle_id: VehicleId,
        time_frame_start: NaiveDateTime,
        time_frame_end: NaiveDateTime,
    ) -> Result<Vec<Box<&'_ dyn PrimaTour>>, StatusCode> {
        Ok(self
            .vehicles
            .get(vehicle_id)
            .tours
            .iter()
            .filter(|tour| tour.overlaps(&Interval::new(time_frame_start, time_frame_end)))
            .map(|tour| Box::new(tour as &dyn PrimaTour))
            .collect_vec())
    }
} // end of PrimaData Trait implementation

impl Data {
    pub fn new(db_connection: &DbConn) -> Self {
        Self {
            zones: VecMap::<ZoneId, ZoneData>::new(),
            companies: VecMap::<CompanyId, CompanyData>::new(),
            vehicles: VecMap::<VehicleId, VehicleData>::new(),
            users: HashMap::<UserId, UserData>::new(),
            addresses: VecMap::<AddressId, AddressData>::new(),
            db_connection: db_connection.clone(),
            osrm: OSRM::new(),
        }
    }

    async fn insert_request_into_db(
        &mut self,
        passengers: i32,
        wheelchairs: i32,
        luggage: i32,
        customer: &UserId,
        tour: &TourId,
    ) -> Result<i32, StatusCode> {
        if passengers < 0 || wheelchairs < 0 || luggage < 0 {
            return Err(StatusCode::EXPECTATION_FAILED);
        }
        if !self.users.keys().contains(&customer) {
            return Err(StatusCode::CONFLICT);
        }
        match Request::insert(request::ActiveModel {
            id: ActiveValue::NotSet,
            tour: ActiveValue::Set(tour.id()),
            customer: ActiveValue::Set(customer.id()),
            passengers: ActiveValue::Set(passengers),
            wheelchairs: ActiveValue::Set(wheelchairs),
            luggage: ActiveValue::Set(luggage),
        })
        .exec(&self.db_connection)
        .await
        {
            Ok(result) => Ok(result.last_insert_id),
            Err(e) => {
                error!("{e:?}");
                Err(StatusCode::INTERNAL_SERVER_ERROR)
            }
        }
    }

    #[cfg(test)]
    fn max_event_id(&self) -> i32 {
        self.vehicles
            .iter()
            .flat_map(|vehicle| vehicle.tours.iter().flat_map(|tour| &tour.events))
            .map(|event| event.id.id())
            .max()
            .unwrap_or(0)
    }

    fn max_company_id(&self) -> i32 {
        self.companies.len() as i32
    }

    fn max_zone_id(&self) -> i32 {
        self.zones.len() as i32
    }

    fn max_vehicle_id(&self) -> i32 {
        self.vehicles.len() as i32
    }

    #[cfg(test)]
    fn get_n_availabilities(&self) -> usize {
        self.vehicles
            .iter()
            .flat_map(|vehicle| &vehicle.availability)
            .count()
    }

    fn get_n_tours(&self) -> i32 {
        self.vehicles
            .iter()
            .flat_map(|vehicle| &vehicle.tours)
            .count() as i32
    }

    async fn find_or_create_address(
        &mut self,
        address: &str,
    ) -> Result<i32, StatusCode> {
        match self.addresses.iter().find(|a| a.address == address) {
            Some(a) => Ok(a.id.id()),
            None => {
                match Address::insert(address::ActiveModel {
                    id: ActiveValue::NotSet,
                    address_string: ActiveValue::Set(address.to_string()),
                })
                .exec(&self.db_connection)
                .await
                {
                    Err(e) => {
                        error!("error: {}", e);
                        Err(StatusCode::BAD_GATEWAY)
                    }
                    Ok(result) => {
                        let id = result.last_insert_id;
                        self.addresses.push(AddressData {
                            id: AddressId::new(id),
                            address: address.to_string(),
                        });
                        Ok(id)
                    }
                }
            }
        }
    }

    async fn get_candidate_vehicles(
        &self,
        passengers: i32,
        start: &Point,
        target: &Point,
    ) -> Vec<&VehicleData> {
        let zones_containing_both_points_ids = self
            .zones
            .iter()
            .filter(|zone| zone.contains(&start.p()) && zone.contains(&target.p()))
            .map(|zone| &zone.id)
            .collect_vec();
        let mut candidate_vehicles = Vec::<&VehicleData>::new();
        for (company_id, vehicles) in self
            .vehicles
            .iter()
            .group_by(|vehicle| &vehicle.company)
            .into_iter()
        {
            if !zones_containing_both_points_ids.contains(&&self.companies.get(*company_id).zone) {
                continue;
            }
            candidate_vehicles.append(
                &mut vehicles
                    .filter(|vehicle| vehicle.fulfills_requirements(passengers))
                    .collect_vec(),
            );
        }
        candidate_vehicles
    }

    #[cfg(test)]
    async fn get_start_point_viable_companies(
        &self,
        start: &Point,
    ) -> Vec<&CompanyData> {
        let viable_zone_ids = self.get_zones_containing_point_ids(start).await;
        self.companies
            .iter()
            .filter(|company| viable_zone_ids.contains(&&company.zone))
            .collect_vec()
    }

    #[cfg(test)]
    async fn get_zones_containing_point_ids(
        &self,
        start: &Point,
    ) -> Vec<&ZoneId> {
        self.zones
            .iter()
            .filter(|zone| zone.contains(&start.p()))
            .map(|zone| &zone.id)
            .collect_vec()
    }

    async fn get_tour(
        &self,
        tour_id: TourId,
    ) -> Result<&TourData, StatusCode> {
        match self
            .vehicles
            .iter()
            .flat_map(|vehicle| &vehicle.tours)
            .find(|tour| tour.id == tour_id)
        {
            Some(t) => Ok(t),
            None => Err(StatusCode::NOT_FOUND),
        }
    }

    async fn find_event(
        &self,
        event_id: EventId,
    ) -> Option<&EventData> {
        self.vehicles
            .iter()
            .flat_map(|vehicle| vehicle.tours.iter().flat_map(|tour| &tour.events))
            .find(|event| event.id == event_id)
    }

    #[allow(dead_code)]
    fn tour_count(&self) -> usize {
        self.vehicles.iter().flat_map(|v| &v.tours).count()
    }

    #[allow(dead_code)]
    pub fn print(&self) {
        let indent = "  ";
        println!("printing zones:");
        self.print_zones(indent);
        println!("printing companies:");
        self.print_companies(indent);
        println!("printing vehicles:");
        self.print_vehicles(true, indent);
        println!("printing tours:");
        self.print_tours(true, indent);
        println!("printing addresses:");
        self.print_addresses(indent);
    }

    #[allow(dead_code)]
    pub fn print_addresses(
        &self,
        indent: &str,
    ) {
        for a in self.addresses.iter() {
            a.print(indent);
        }
    }

    #[allow(dead_code)]
    fn print_tours(
        &self,
        print_events: bool,
        indent: &str,
    ) {
        let mut event_indent = "  ".to_string();
        event_indent.push_str(indent);
        for tour in self.vehicles.iter().flat_map(|vehicle| &vehicle.tours) {
            tour.print(indent);
            if print_events {
                println!("{}printing events:", event_indent);
                for event in tour.events.iter() {
                    if tour.id != event.tour {
                        continue;
                    }

                    event.print(&event_indent);
                }
            }
        }
    }

    #[allow(dead_code)]
    pub fn print_zones(
        &self,
        indent: &str,
    ) {
        for z in self.zones.iter() {
            z.print(indent);
        }
    }

    #[allow(dead_code)]
    pub fn print_companies(
        &self,
        indent: &str,
    ) {
        for c in self.companies.iter() {
            c.print(indent);
        }
    }

    #[allow(dead_code)]
    pub fn print_vehicles(
        &self,
        print_availabilities: bool,
        indent: &str,
    ) {
        let mut availabilit_text_indent = "  ".to_string();
        availabilit_text_indent.push_str(indent);
        let mut availability_indent = "  ".to_string();
        availability_indent.push_str(&availabilit_text_indent);
        for v in self.vehicles.iter() {
            v.print(indent);
            if print_availabilities {
                println!("{}printing availabilites:", availabilit_text_indent);
                for availability in v.availability.values() {
                    availability.print(&availability_indent);
                }
            }
        }
    }
}

#[cfg(test)]
mod test {
    use super::ZoneData;
    use crate::{
        backend::{
            data::Data,
            helpers::beeline_duration,
            id_types::{CompanyId, Id, TourId, UserId, VehicleId, ZoneId},
            lat_long::{Latitude, Longitude},
            lib::{
                AvailabilityCrud, CompanyCrud, GetCompany, GetEvents, GetVehicle, HandleRequest,
                PrimaData, TourCrud, UserCrud, VehicleCrud, ZoneCrud,
            },
            point::Point,
        },
        constants::geojson_strings::{geo_points::TestPoints, gorlitz::GORLITZ},
        dotenv, env,
        init::{init, InitType},
        Database, Migrator,
    };
    use chrono::{Duration, NaiveDate, NaiveDateTime, Utc};
    use geo::Contains;
    use hyper::StatusCode;
    use itertools::Itertools;
    use migration::MigratorTrait;
    use sea_orm::DbConn;
    use serial_test::serial;
    use tracing_test::traced_test;

    async fn check_zones_contain_correct_points(
        d: &Data,
        points: &[Point],
        expected_zones: i32,
    ) {
        for point in points.iter() {
            let companies_containing_point = d.get_start_point_viable_companies(point).await;
            for company in d.companies.iter() {
                if companies_containing_point.contains(&company) {
                    assert!(company.zone.id() == expected_zones);
                } else {
                    assert!(company.zone.id() != expected_zones);
                }
            }
        }
    }

    fn check_points_in_zone(
        expect: bool,
        zone: &ZoneData,
        points: &[Point],
    ) {
        for point in points.iter() {
            assert_eq!(zone.area.contains(&point.p()), expect);
        }
    }

    async fn check_data_db_synchronized(data: &Data) {
        let mut read_data = Data::new(&data.db_connection);
        read_data.read_data_from_db().await;
        assert!(read_data == *data);
    }

    async fn insert_or_add_test_tour(
        data: &mut Data,
        vehicle_id: VehicleId,
    ) -> StatusCode {
        data.insert_or_addto_tour(
            None,
            NaiveDate::from_ymd_opt(5000, 4, 15)
                .unwrap()
                .and_hms_opt(9, 10, 0)
                .unwrap(),
            NaiveDate::from_ymd_opt(5000, 4, 15)
                .unwrap()
                .and_hms_opt(10, 0, 0)
                .unwrap(),
            vehicle_id,
            "karolinenplatz 5",
            "Lichtwiesenweg 3",
            Latitude::new(13.867512),
            Longitude::new(51.22069),
            NaiveDate::from_ymd_opt(5000, 4, 15)
                .unwrap()
                .and_hms_opt(9, 15, 0)
                .unwrap(),
            NaiveDate::from_ymd_opt(5000, 4, 15)
                .unwrap()
                .and_hms_opt(9, 12, 0)
                .unwrap(),
            UserId::new(2),
            3,
            0,
            0,
            Latitude::new(14.025081),
            Longitude::new(51.195075),
            NaiveDate::from_ymd_opt(5000, 4, 15)
                .unwrap()
                .and_hms_opt(9, 55, 0)
                .unwrap(),
            NaiveDate::from_ymd_opt(5000, 4, 15)
                .unwrap()
                .and_hms_opt(9, 18, 0)
                .unwrap(),
        )
        .await
    }

    async fn test_main() -> DbConn {
        dotenv().ok();
        let db_url = env::var("DATABASE_URL").expect("DATABASE_URL is not set in .env file");
        let conn = Database::connect(db_url)
            .await
            .expect("Database connection failed");
        Migrator::up(&conn, None).await.unwrap();
        conn
    }

    #[tokio::test]
    #[serial]
    async fn test_zones() {
        let db_conn = test_main().await;
        let mut d = init(&db_conn, true, 5000, InitType::BackendTest).await;
        let test_points = TestPoints::new();
        //Validate invalid multipolygon handling when creating zone (expect StatusCode::BAD_REQUEST)
        assert_eq!(
            d.create_zone("some new zone name", "invalid multipolygon")
                .await,
            StatusCode::BAD_REQUEST
        );
        //zonen tests:
        //0->Bautzen Ost
        check_points_in_zone(true, d.zones.get(ZoneId::new(1)), &test_points.bautzen_ost);
        check_points_in_zone(
            false,
            d.zones.get(ZoneId::new(1)),
            &test_points.bautzen_west,
        );
        check_points_in_zone(false, d.zones.get(ZoneId::new(1)), &test_points.gorlitz);
        check_points_in_zone(false, d.zones.get(ZoneId::new(1)), &test_points.outside);
        //1->Bautzen West
        check_points_in_zone(false, d.zones.get(ZoneId::new(2)), &test_points.bautzen_ost);
        check_points_in_zone(true, d.zones.get(ZoneId::new(2)), &test_points.bautzen_west);
        check_points_in_zone(false, d.zones.get(ZoneId::new(2)), &test_points.gorlitz);
        check_points_in_zone(false, d.zones.get(ZoneId::new(2)), &test_points.outside);
        //2->Görlitz
        check_points_in_zone(false, d.zones.get(ZoneId::new(3)), &test_points.bautzen_ost);
        check_points_in_zone(
            false,
            d.zones.get(ZoneId::new(3)),
            &test_points.bautzen_west,
        );
        check_points_in_zone(true, d.zones.get(ZoneId::new(3)), &test_points.gorlitz);
        check_points_in_zone(false, d.zones.get(ZoneId::new(3)), &test_points.outside);

        check_zones_contain_correct_points(&d, &test_points.bautzen_ost, 1).await;
        check_zones_contain_correct_points(&d, &test_points.bautzen_west, 2).await;
        check_zones_contain_correct_points(&d, &test_points.gorlitz, 3).await;
        check_zones_contain_correct_points(&d, &test_points.outside, -1).await;
    }

    #[tokio::test]
    #[serial]
    async fn test_synchronization() {
        let db_conn = test_main().await;
        let d = init(&db_conn, true, 5000, InitType::BackendTest).await;
        check_data_db_synchronized(&d).await;
    }

    #[tokio::test]
    #[serial]
    async fn test_key_violations() {
        let db_conn = test_main().await;
        let mut d = init(&db_conn, true, 5000, InitType::BackendTest).await;
        //validate UniqueKeyViolation handling when creating data (expect StatusCode::CONFLICT)
        //unique keys:  table               keys
        //              user                name, email
        //              zone                name
        //              company             name
        //              vehicle             license-plate
        let mut n_users = d.users.len();
        //insert user with existing name
        assert_eq!(
            d.create_user(
                "TestDriver1",
                true,
                false,
                Some(CompanyId::new(1)),
                false,
                "test@gmail.com",
                Some("".to_string()),
                "",
                Some("".to_string()),
                Some("".to_string()),
            )
            .await,
            StatusCode::CREATED
        );
        assert_eq!(d.users.len(), n_users + 1);
        n_users = d.users.len();
        //insert user with existing email
        assert_eq!(
            d.create_user(
                "TestDriver2",
                true,
                false,
                Some(CompanyId::new(2)),
                false,
                "test@aol.com",
                Some("".to_string()),
                "",
                Some("".to_string()),
                Some("".to_string()),
            )
            .await,
            StatusCode::CONFLICT
        );
        assert_eq!(d.users.len(), n_users);
        //insert user with new name and email
        assert_eq!(
            d.create_user(
                "TestDriver2",
                false,
                false,
                None,
                false,
                "test@gmail2.com",
                Some("".to_string()),
                "",
                Some("".to_string()),
                Some("".to_string()),
            )
            .await,
            StatusCode::CREATED
        );
        assert_eq!(d.users.len(), n_users + 1);

        //insert zone with existing name
        let n_zones = d.zones.len();
        assert_eq!(
            d.create_zone("Görlitz", GORLITZ).await,
            StatusCode::CONFLICT
        );
        assert_eq!(d.zones.len(), n_zones);

        //insert company with existing name
        let mut n_companies = d.companies.len();
        assert_eq!(
            d.create_company(
                "Taxi-Unternehmen Bautzen-1",
                ZoneId::new(1),
                ZoneId::new(1),
                "mustermann@web.de",
                Latitude::new(2.0),
                Longitude::new(1.0)
            )
            .await,
            StatusCode::CREATED
        );

        //insert vehicle with existing license plate
        let n_vehicles = d.vehicles.len();
        assert_eq!(
            d.create_vehicle("TUB1-1", CompanyId::new(1)).await,
            StatusCode::CONFLICT
        );
        assert_eq!(d.vehicles.len(), n_vehicles);

        //Validate ForeignKeyViolation handling when creating data (expect StatusCode::EXPECTATION_FAILED)
        //foreign keys: table               keys
        //              company             zone
        //              vehicle             company
        //              availability        vehicle
        //              tour                vehicle
        //              event               user tour
        let n_tours = d.get_n_tours();
        let n_events = d.max_event_id();
        assert_eq!(
            insert_or_add_test_tour(&mut d, VehicleId::new(100)).await,
            StatusCode::EXPECTATION_FAILED
        );
        assert_eq!(
            insert_or_add_test_tour(&mut d, VehicleId::new(100)).await,
            StatusCode::EXPECTATION_FAILED
        );
        assert_eq!(n_events, d.max_event_id());
        assert_eq!(n_tours, d.get_n_tours());
        //insert company with non-existing zone
        assert_eq!(
            d.create_company(
                "some new name",
                ZoneId::new(1 + n_zones as i32),
                ZoneId::new(1 + n_zones as i32),
                "y@x",
                Latitude::new(2.0),
                Longitude::new(1.0)
            )
            .await,
            StatusCode::EXPECTATION_FAILED
        );
        assert_eq!(d.companies.len(), n_companies + 1);
        n_companies = d.companies.len();
        //insert company with existing zone
        assert_eq!(
            d.create_company(
                "some new name",
                ZoneId::new(n_zones as i32),
                ZoneId::new(n_zones as i32),
                "x@z",
                Latitude::new(2.0),
                Longitude::new(1.0)
            )
            .await,
            StatusCode::CREATED
        );
        assert_eq!(d.companies.len(), n_companies + 1);
        let n_companies = d.companies.len();

        //insert company with existing email
        assert_eq!(
            d.create_company(
                "some new name",
                ZoneId::new(n_zones as i32),
                ZoneId::new(n_zones as i32),
                "a@b",
                Latitude::new(2.0),
                Longitude::new(1.0)
            )
            .await,
            StatusCode::CONFLICT
        );
        //insert vehicle with non-existing company
        assert_eq!(
            d.create_vehicle(
                "some new license plate",
                CompanyId::new(1 + n_companies as i32)
            )
            .await,
            StatusCode::EXPECTATION_FAILED
        );
        assert_eq!(d.vehicles.len(), n_vehicles);
        //insert vehicle with existing company
        assert_eq!(
            d.create_vehicle("some new license plate", CompanyId::new(n_companies as i32))
                .await,
            StatusCode::CREATED
        );
        assert_eq!(d.vehicles.len(), n_vehicles + 1);

        check_data_db_synchronized(&d).await;
    }

    #[tokio::test]
    #[serial]
    async fn test_invalid_interval_parameter_handling() {
        let db_conn = test_main().await;
        let mut d = init(&db_conn, true, 5000, InitType::BackendTest).await;

        let base_time = NaiveDate::from_ymd_opt(5000, 1, 1)
            .unwrap()
            .and_hms_opt(10, 0, 0)
            .unwrap();

        //interval range not limited
        assert!(d
            .get_tours(VehicleId::new(1), NaiveDateTime::MIN, NaiveDateTime::MAX)
            .await
            .is_ok());
        //interval range not limited
        assert!(d
            .get_events_for_user(UserId::new(1), NaiveDateTime::MIN, NaiveDateTime::MAX)
            .await
            .is_ok());

        //interval range not limited
        //assert!(d.get_events_for_tour(1).await.is_ok()); no tour right now

        //interval range not limited
        assert!(d
            .get_events_for_vehicle(VehicleId::new(1), NaiveDateTime::MIN, NaiveDateTime::MAX)
            .await
            .is_ok());
        let n_availabilities = d.get_n_availabilities();
        //starttime before year 2024
        assert_eq!(
            d.create_availability(
                NaiveDateTime::MIN,
                base_time + Duration::hours(1),
                VehicleId::new(1)
            )
            .await,
            StatusCode::NOT_ACCEPTABLE
        );
        assert_eq!(d.get_n_availabilities(), n_availabilities);
        //endtime after year 100000
        assert_eq!(
            d.create_availability(
                base_time,
                NaiveDate::from_ymd_opt(100000, 4, 15)
                    .unwrap()
                    .and_hms_opt(10, 0, 0)
                    .unwrap(),
                VehicleId::new(1)
            )
            .await,
            StatusCode::NOT_ACCEPTABLE
        );
        assert_eq!(d.get_n_availabilities(), n_availabilities);
        //starttime before year 2024
        assert_eq!(
            d.remove_availability(
                NaiveDate::from_ymd_opt(2023, 4, 15)
                    .unwrap()
                    .and_hms_opt(11, 10, 0)
                    .unwrap(),
                NaiveDate::from_ymd_opt(2024, 4, 15)
                    .unwrap()
                    .and_hms_opt(10, 0, 0)
                    .unwrap(),
                VehicleId::new(1)
            )
            .await,
            StatusCode::NOT_ACCEPTABLE
        );
        //endtime after year 100000
        assert_eq!(
            d.remove_availability(
                NaiveDate::from_ymd_opt(2024, 4, 15)
                    .unwrap()
                    .and_hms_opt(11, 10, 0)
                    .unwrap(),
                NaiveDate::from_ymd_opt(100000, 4, 15)
                    .unwrap()
                    .and_hms_opt(10, 0, 0)
                    .unwrap(),
                VehicleId::new(1)
            )
            .await,
            StatusCode::NOT_ACCEPTABLE
        );
        assert_eq!(d.get_n_availabilities(), n_availabilities);

        check_data_db_synchronized(&d).await;
    }

    #[tokio::test]
    #[serial]
    async fn test_init() {
        let db_conn = test_main().await;
        let d = init(&db_conn, true, 5000, InitType::BackendTest).await;

        assert_eq!(d.vehicles.len(), 5);
        assert_eq!(d.zones.len(), 3);
        assert_eq!(d.companies.len(), 3);
        assert_eq!(d.vehicles.iter().flat_map(|v| &v.availability).count(), 3);
    }

    #[tokio::test]
    #[serial]
    async fn availability_test() {
        let db_conn = test_main().await;
        let mut d = init(&db_conn, true, 5000, InitType::BackendTest).await;

        let base_time = NaiveDate::from_ymd_opt(5000, 4, 15)
            .unwrap()
            .and_hms_opt(9, 10, 0)
            .unwrap();
        let in_2_hours = base_time + Duration::hours(2);
        let in_3_hours = base_time + Duration::hours(3);

        assert_eq!(d.vehicles.get(VehicleId::new(1)).availability.len(), 1);
        //try removing availability created in init (needed for tour)
        assert_eq!(
            d.remove_availability(
                NaiveDate::from_ymd_opt(5000, 1, 1)
                    .unwrap()
                    .and_hms_opt(0, 0, 0)
                    .unwrap(),
                NaiveDate::from_ymd_opt(5005, 1, 1)
                    .unwrap()
                    .and_hms_opt(0, 0, 0)
                    .unwrap(),
                VehicleId::new(1),
            )
            .await,
            StatusCode::OK
        );

        assert_eq!(d.vehicles.get(VehicleId::new(1)).availability.len(), 0);
        //add non-touching
        assert_eq!(
            d.create_availability(in_2_hours, in_3_hours, VehicleId::new(1))
                .await,
            StatusCode::CREATED
        );
        assert_eq!(d.vehicles.get(VehicleId::new(1)).availability.len(), 1);
        //add touching
        assert_eq!(
            d.create_availability(
                in_2_hours + Duration::hours(1),
                in_3_hours + Duration::hours(1),
                VehicleId::new(1),
            )
            .await,
            StatusCode::CREATED
        );
        assert_eq!(d.vehicles.get(VehicleId::new(1)).availability.len(), 1);
        //add containing/contained (equal)
        assert_eq!(
            d.create_availability(in_2_hours, in_3_hours, VehicleId::new(1))
                .await,
            StatusCode::NO_CONTENT
        );
        assert_eq!(d.vehicles.get(VehicleId::new(1)).availability.len(), 1);

        //remove non-touching
        d.remove_availability(
            base_time + Duration::weeks(1),
            base_time + Duration::weeks(2),
            VehicleId::new(1),
        )
        .await;
        assert_eq!(d.vehicles.get(VehicleId::new(1)).availability.len(), 1);
        //remove split
        d.remove_availability(
            in_2_hours + Duration::minutes(5),
            in_3_hours - Duration::minutes(5),
            VehicleId::new(1),
        )
        .await;
        assert_eq!(d.vehicles.get(VehicleId::new(1)).availability.len(), 2);
        //remove overlapping
        d.remove_availability(
            in_2_hours - Duration::minutes(90),
            in_3_hours - Duration::minutes(100),
            VehicleId::new(1),
        )
        .await;
        assert_eq!(d.vehicles.get(VehicleId::new(1)).availability.len(), 2);
        //remove containing
        d.remove_availability(
            in_2_hours,
            in_2_hours + Duration::minutes(5),
            VehicleId::new(1),
        )
        .await;
        assert_eq!(d.vehicles.get(VehicleId::new(1)).availability.len(), 1);
    }

    #[tokio::test]
    #[serial]
    async fn availability_test2() {
        let db_conn = test_main().await;
        let mut d = init(&db_conn, true, 5000, InitType::BackendTest).await;

        let base_time = NaiveDate::from_ymd_opt(5000, 4, 15)
            .unwrap()
            .and_hms_opt(9, 10, 0)
            .unwrap();
        let in_2_hours = base_time + Duration::hours(2);
        let in_3_hours = base_time + Duration::hours(3);
        d.vehicles.get_mut(VehicleId::new(1)).availability.clear();

        let vehicle_id = VehicleId::new(1);
        assert_eq!(
            d.create_availability(in_2_hours, in_3_hours, vehicle_id)
                .await,
            StatusCode::CREATED
        );
        assert_eq!(d.vehicles.get(VehicleId::new(1)).availability.len(), 1);
        assert_eq!(
            d.remove_availability(
                in_2_hours + Duration::minutes(30),
                in_2_hours + Duration::minutes(45),
                vehicle_id
            )
            .await,
            StatusCode::OK
        );
        assert_eq!(d.vehicles.get(VehicleId::new(1)).availability.len(), 2);
        assert_eq!(
            d.remove_availability(in_2_hours + Duration::minutes(45), in_3_hours, vehicle_id)
                .await,
            StatusCode::OK
        );
        assert_eq!(d.vehicles.get(VehicleId::new(1)).availability.len(), 1);
    }

    #[tokio::test]
    #[serial]
    async fn get_events_for_vehicle_test() {
        let db_conn = test_main().await;
        let d = init(&db_conn, true, 5000, InitType::BackendTestWithEvents).await;

        // vehicle       # of events created in init
        //   1                  4
        //   2                  2
        //   3                  0
        //   4                  0

        /*
        let not_found_result = d
            .get_events_for_vehicle(
                VehicleId::new(1 + d.vehicles.len() as i32),
                NaiveDateTime::MIN,
                NaiveDateTime::MAX,
            )
            .await;
        assert!(not_found_result.is_err());
        assert_eq!(not_found_result.err(), Some(StatusCode::NOT_FOUND));
         */

        let result_v1 = d
            .get_events_for_vehicle(VehicleId::new(1), NaiveDateTime::MIN, NaiveDateTime::MAX)
            .await;
        assert!(result_v1.is_ok());
        assert_eq!(result_v1.unwrap().len(), 4);

        let result_v2 = d
            .get_events_for_vehicle(VehicleId::new(2), NaiveDateTime::MIN, NaiveDateTime::MAX)
            .await;
        assert!(result_v2.is_ok());
        assert_eq!(result_v2.unwrap().len(), 2);

        // events are not in requested interval
        let emtpy_result_v1 = d
            .get_events_for_vehicle(
                VehicleId::new(1),
                NaiveDateTime::MIN,
                Utc::now().naive_utc(),
            )
            .await;
        assert!(emtpy_result_v1.is_ok());
        assert!(emtpy_result_v1.unwrap().is_empty());
        for i in 3..d.max_vehicle_id() {
            let result = d
                .get_events_for_vehicle(VehicleId::new(i), NaiveDateTime::MIN, NaiveDateTime::MAX)
                .await;
            assert!(result.is_ok());
            assert!(result.unwrap().is_empty());
        }
    }

    #[tokio::test]
    #[serial]
    async fn get_events_for_user_test() {
        let db_conn = test_main().await;
        let d = init(&db_conn, true, 5000, InitType::BackendTestWithEvents).await;

        let not_found_result = d
            .get_events_for_user(
                UserId::new(1 + d.users.len() as i32),
                NaiveDateTime::MIN,
                NaiveDateTime::MAX,
            )
            .await;
        assert!(not_found_result.is_err());
        assert_eq!(not_found_result.err(), Some(StatusCode::NOT_FOUND));

        // user         # of events created in init
        //   1                  4
        //   2                  2
        //   3                  0
        //   4                  0
        let result_v1 = d
            .get_events_for_user(UserId::new(1), NaiveDateTime::MIN, NaiveDateTime::MAX)
            .await;
        assert!(result_v1.is_ok());
        assert_eq!(result_v1.unwrap().len(), 4);

        let result_v2 = d
            .get_events_for_user(UserId::new(2), NaiveDateTime::MIN, NaiveDateTime::MAX)
            .await;
        assert!(result_v2.is_ok());
        assert_eq!(result_v2.unwrap().len(), 2);

        // events are not in requested interval
        let emtpy_result_v1 = d
            .get_events_for_user(UserId::new(1), NaiveDateTime::MIN, Utc::now().naive_utc())
            .await;
        assert!(emtpy_result_v1.is_ok());
        assert!(emtpy_result_v1.unwrap().is_empty());

        for i in 3..d.users.len() {
            let result = d
                .get_events_for_user(
                    UserId::new(i as i32),
                    NaiveDateTime::MIN,
                    NaiveDateTime::MAX,
                )
                .await;
            assert!(result.is_ok());
            assert!(result.unwrap().is_empty());
        }
    }

    #[tokio::test]
    #[serial]
    async fn get_events_for_tour_test() {
        let db_conn = test_main().await;
        let d = init(&db_conn, true, 5000, InitType::BackendTestWithEvents).await;

        // Init creates 3 tours with ids 1,2,3. Each has 2 events.
        let t1_result = d.get_events_for_tour(TourId::new(1)).await;
        assert!(t1_result.is_ok());
        assert!(t1_result.clone().unwrap().len() == 2);
        let first_event = *(t1_result.unwrap()[0]);
        assert_eq!(first_event.get_customer_id().await, UserId::new(1));

        let t2_result = d.get_events_for_tour(TourId::new(2)).await;
        assert!(t2_result.is_ok());
        assert!(t2_result.clone().unwrap().len() == 2);
        let first_event = *(t2_result.unwrap()[0]);
        assert_eq!(first_event.get_customer_id().await, UserId::new(1));

        let t3_result = d.get_events_for_tour(TourId::new(3)).await;
        assert!(t3_result.is_ok());
        assert!(t3_result.clone().unwrap().len() == 2);
        let first_event = *(t3_result.unwrap()[0]);
        assert_eq!(first_event.get_customer_id().await, UserId::new(2));

        let t4_result = d.get_events_for_tour(TourId::new(4)).await;
        assert!(t4_result.is_err());
        assert_eq!(t4_result.err(), Some(StatusCode::NOT_FOUND));
    }

    #[tokio::test]
    #[serial]
    async fn availability_statuscode_test() {
        let db_conn = test_main().await;
        let mut d = init(&db_conn, true, 5000, InitType::BackendTest).await;

        let base_time = NaiveDate::from_ymd_opt(5000, 4, 15)
            .unwrap()
            .and_hms_opt(9, 10, 0)
            .unwrap();

        //Validate StatusCode cases
        //insert availability with non-existing vehicle
        let n_availabilities = d.get_n_availabilities();
        let n_vehicles = d.vehicles.len();
        assert_eq!(d.get_n_availabilities(), n_availabilities);
        //insert availability with existing vehicle
        let n_availabilities = d.get_n_availabilities();
        assert_eq!(
            d.create_availability(
                base_time,
                base_time + Duration::hours(1),
                VehicleId::new(n_vehicles as i32)
            )
            .await,
            StatusCode::CREATED
        );
        assert_eq!(d.get_n_availabilities(), n_availabilities + 1);
        let n_availabilities = d.get_n_availabilities();

        //Validate nothing happened case handling when removing availabilies (expect StatusCode::NO_CONTENT)
        //endtime after year 100000
        assert_eq!(
            d.remove_availability(
                NaiveDate::from_ymd_opt(2025, 4, 15)
                    .unwrap()
                    .and_hms_opt(11, 10, 0)
                    .unwrap(),
                NaiveDate::from_ymd_opt(2026, 4, 15)
                    .unwrap()
                    .and_hms_opt(10, 0, 0)
                    .unwrap(),
                VehicleId::new(1)
            )
            .await,
            StatusCode::NO_CONTENT
        );
        assert_eq!(d.get_n_availabilities(), n_availabilities);
    }
    /*
    #[tokio::test]
    #[serial]
    async fn tour_test() {
        let db_conn = test_main().await;
        let mut d = init(&db_conn, true, 5000, InitType::BackendTest).await;
        d.insert_or_addto_tour(
            None,
            NaiveDate::from_ymd_opt(2024, 4, 15)
                .unwrap()
                .and_hms_opt(9, 10, 0)
                .unwrap(),
            NaiveDate::from_ymd_opt(2024, 4, 15)
                .unwrap()
                .and_hms_opt(10, 0, 0)
                .unwrap(),
            1,
            "karolinenplatz 5",
            "Lichtwiesenweg 3",
            13.867512,
            51.22069,
            NaiveDate::from_ymd_opt(2024, 4, 15)
                .unwrap()
                .and_hms_opt(9, 15, 0)
                .unwrap(),
            NaiveDate::from_ymd_opt(2024, 4, 15)
                .unwrap()
                .and_hms_opt(9, 12, 0)
                .unwrap(),
            2,
            3,
            0,
            0,
            14.025081,
            51.195075,
            NaiveDate::from_ymd_opt(2024, 4, 15)
                .unwrap()
                .and_hms_opt(9, 55, 0)
                .unwrap(),
            NaiveDate::from_ymd_opt(2024, 4, 15)
                .unwrap()
                .and_hms_opt(9, 18, 0)
                .unwrap(),
        )
        .await;

        d.insert_or_addto_tour(
            None,
            NaiveDate::from_ymd_opt(2024, 4, 15)
                .unwrap()
                .and_hms_opt(9, 10, 0)
                .unwrap(),
            NaiveDate::from_ymd_opt(2024, 4, 15)
                .unwrap()
                .and_hms_opt(10, 0, 0)
                .unwrap(),
            1,
            "karolinenplatz 5",
            "Lichtwiesenweg 3",
            13.867512,
            51.22069,
            NaiveDate::from_ymd_opt(2024, 4, 15)
                .unwrap()
                .and_hms_opt(9, 15, 0)
                .unwrap(),
            NaiveDate::from_ymd_opt(2024, 4, 15)
                .unwrap()
                .and_hms_opt(9, 12, 0)
                .unwrap(),
            2,
            3,
            0,
            0,
            14.025081,
            51.195075,
            NaiveDate::from_ymd_opt(2024, 4, 15)
                .unwrap()
                .and_hms_opt(9, 55, 0)
                .unwrap(),
            NaiveDate::from_ymd_opt(2024, 4, 15)
                .unwrap()
                .and_hms_opt(9, 18, 0)
                .unwrap(),
        )
        .await;

        d.insert_or_addto_tour(
            None,
            NaiveDate::from_ymd_opt(2024, 4, 15)
                .unwrap()
                .and_hms_opt(9, 10, 0)
                .unwrap(),
            NaiveDate::from_ymd_opt(2024, 4, 15)
                .unwrap()
                .and_hms_opt(10, 0, 0)
                .unwrap(),
            1,
            "karolinenplatz 5",
            "Lichtwiesenweg 3",
            13.867512,
            51.22069,
            NaiveDate::from_ymd_opt(2024, 4, 15)
                .unwrap()
                .and_hms_opt(9, 15, 0)
                .unwrap(),
            NaiveDate::from_ymd_opt(2024, 4, 15)
                .unwrap()
                .and_hms_opt(9, 12, 0)
                .unwrap(),
            2,
            3,
            0,
            0,
            14.025081,
            51.195075,
            NaiveDate::from_ymd_opt(2024, 4, 15)
                .unwrap()
                .and_hms_opt(9, 55, 0)
                .unwrap(),
            NaiveDate::from_ymd_opt(2024, 4, 15)
                .unwrap()
                .and_hms_opt(9, 18, 0)
                .unwrap(),
        )
        .await;

        d.insert_or_addto_tour(
            None,
            NaiveDate::from_ymd_opt(2024, 4, 15)
                .unwrap()
                .and_hms_opt(9, 10, 0)
                .unwrap(),
            NaiveDate::from_ymd_opt(2024, 4, 15)
                .unwrap()
                .and_hms_opt(10, 0, 0)
                .unwrap(),
            1,
            "karolinenplatz 5",
            "Lichtwiesenweg 3",
            13.867512,
            51.22069,
            NaiveDate::from_ymd_opt(2024, 4, 15)
                .unwrap()
                .and_hms_opt(9, 15, 0)
                .unwrap(),
            NaiveDate::from_ymd_opt(2024, 4, 15)
                .unwrap()
                .and_hms_opt(9, 12, 0)
                .unwrap(),
            2,
            3,
            0,
            0,
            14.025081,
            51.195075,
            NaiveDate::from_ymd_opt(2024, 4, 15)
                .unwrap()
                .and_hms_opt(9, 55, 0)
                .unwrap(),
            NaiveDate::from_ymd_opt(2024, 4, 15)
                .unwrap()
                .and_hms_opt(9, 18, 0)
                .unwrap(),
        )
        .await;

        check_data_db_synchronized(&d).await;
    } */

    #[tokio::test]
    #[serial]
    async fn test_handle_request_statuscodes() {
        let db_conn = test_main().await;
        let mut d = init(&db_conn, true, 5000, InitType::BackendTest).await;

        let base_time = NaiveDate::from_ymd_opt(5000, 1, 1)
            .unwrap()
            .and_hms_opt(10, 0, 0)
            .unwrap();

        let test_points = TestPoints::new();

        // non-existing user
        assert_eq!(
            d.handle_routing_request(
                base_time,
                true,
                test_points.bautzen_ost[0].get_lat(),
                test_points.bautzen_ost[0].get_lng(),
                test_points.bautzen_ost[1].get_lat(),
                test_points.bautzen_ost[1].get_lng(),
                UserId::new(1 + d.users.len() as i32),
                1,
                "start_address",
                "target_address",
            )
            .await,
            StatusCode::NOT_FOUND
        );

        // no passengers
        assert_eq!(
            d.handle_routing_request(
                base_time,
                true,
                test_points.bautzen_ost[0].get_lat(),
                test_points.bautzen_ost[0].get_lng(),
                test_points.bautzen_ost[1].get_lat(),
                test_points.bautzen_ost[1].get_lng(),
                UserId::new(1),
                0,
                "start_address",
                "target_address",
            )
            .await,
            StatusCode::EXPECTATION_FAILED
        );

        // negative passenger count
        assert_eq!(
            d.handle_routing_request(
                base_time,
                true,
                test_points.bautzen_ost[0].get_lat(),
                test_points.bautzen_ost[0].get_lng(),
                test_points.bautzen_ost[1].get_lat(),
                test_points.bautzen_ost[1].get_lng(),
                UserId::new(1),
                -1,
                "start_address",
                "target_address",
            )
            .await,
            StatusCode::EXPECTATION_FAILED
        );

        // too many passengers TODO change when mvp restriction is lifted
        assert_eq!(
            d.handle_routing_request(
                base_time,
                true,
                test_points.bautzen_ost[0].get_lat(),
                test_points.bautzen_ost[0].get_lng(),
                test_points.bautzen_ost[1].get_lat(),
                test_points.bautzen_ost[1].get_lng(),
                UserId::new(1),
                4,
                "start_address",
                "target_address",
            )
            .await,
            StatusCode::NO_CONTENT
        );

        // request with start in the past
        assert_eq!(
            d.handle_routing_request(
                Utc::now().naive_utc() - Duration::minutes(1),
                true,
                test_points.bautzen_ost[0].get_lat(),
                test_points.bautzen_ost[0].get_lng(),
                test_points.bautzen_ost[1].get_lat(),
                test_points.bautzen_ost[1].get_lng(),
                UserId::new(1),
                1,
                "start_address",
                "target_address",
            )
            .await,
            StatusCode::NOT_ACCEPTABLE
        );

        // request denied (no available vehicle)
        assert_eq!(
            d.handle_routing_request(
                base_time,
                true,
                test_points.bautzen_ost[0].get_lat(),
                test_points.bautzen_ost[0].get_lng(),
                test_points.bautzen_ost[1].get_lat(),
                test_points.bautzen_ost[1].get_lng(),
                UserId::new(1),
                1,
                "start_address",
                "target_address",
            )
            .await,
            StatusCode::NO_CONTENT
        );

        // request with start in the future, but before MIN_PREP_TIME
        assert_eq!(
            d.handle_routing_request(
                Utc::now().naive_utc() + Duration::minutes(5),
                true,
                test_points.bautzen_ost[0].get_lat(),
                test_points.bautzen_ost[0].get_lng(),
                test_points.bautzen_ost[1].get_lat(),
                test_points.bautzen_ost[1].get_lng(),
                UserId::new(1),
                1,
                "start_address",
                "target_address",
            )
            .await,
            StatusCode::NO_CONTENT
        );

        //accepted_request
        assert_eq!(
            d.handle_routing_request(
                NaiveDate::from_ymd_opt(5000, 4, 19)
                    .unwrap()
                    .and_hms_opt(11, 5, 0)
                    .unwrap(),
                true,
                test_points.bautzen_ost[0].get_lat(),
                test_points.bautzen_ost[0].get_lng(),
                test_points.bautzen_ost[1].get_lat(),
                test_points.bautzen_ost[1].get_lng(),
                UserId::new(1),
                1,
                "start_address",
                "target_address",
            )
            .await,
            StatusCode::CREATED
        );
    }

    #[tokio::test]
    #[serial]
    async fn test_beeline_duration_companies() {
        //Test may fail, if constant/primitives/BEELINE_KMH is changed.
        let db_conn = test_main().await;
        let d = init(&db_conn, true, 5000, InitType::BackendTest).await;

        let mut test_points = TestPoints::new();
        let mut all_test_points = Vec::<Point>::new();
        all_test_points.append(&mut test_points.bautzen_ost);
        all_test_points.append(&mut test_points.bautzen_west);
        all_test_points.append(&mut test_points.gorlitz);
        for (p, company) in all_test_points.iter().cartesian_product(d.companies.iter()) {
            assert!(beeline_duration(p, &company.central_coordinates) < Duration::hours(1));
        }
    }

    #[tokio::test]
    #[serial]
    async fn test_candidate_vehicles() {
        let db_conn = test_main().await;
        let d = init(&db_conn, true, 5000, InitType::BackendTest).await;

        let test_points = TestPoints::new();

        let candidate_ids_bautzen_ost = d
            .get_candidate_vehicles(1, &test_points.bautzen_ost[0], &test_points.bautzen_ost[1])
            .await
            .iter()
            .map(|vehicle| vehicle.id)
            .collect_vec();

        assert!(candidate_ids_bautzen_ost.contains(&VehicleId::new(1)));
        assert!(candidate_ids_bautzen_ost.contains(&VehicleId::new(2)));
        assert!(!candidate_ids_bautzen_ost.contains(&VehicleId::new(3)));
        assert!(!candidate_ids_bautzen_ost.contains(&VehicleId::new(4)));
        assert!(!candidate_ids_bautzen_ost.contains(&VehicleId::new(5)));

        let candidate_ids_bautzen_west = d
            .get_candidate_vehicles(
                1,
                &test_points.bautzen_west[0],
                &test_points.bautzen_west[1],
            )
            .await
            .iter()
            .map(|vehicle| vehicle.id)
            .collect_vec();

        assert!(!candidate_ids_bautzen_west.contains(&VehicleId::new(1)));
        assert!(!candidate_ids_bautzen_west.contains(&VehicleId::new(2)));
        assert!(candidate_ids_bautzen_west.contains(&VehicleId::new(3)));
        assert!(candidate_ids_bautzen_west.contains(&VehicleId::new(4)));
        assert!(!candidate_ids_bautzen_west.contains(&VehicleId::new(5)));

        let candidate_ids_too_many_passengers = d
            .get_candidate_vehicles(4, &test_points.bautzen_ost[0], &test_points.bautzen_ost[1])
            .await
            .iter()
            .map(|vehicle| vehicle.id)
            .collect_vec();

        assert!(!candidate_ids_too_many_passengers.contains(&VehicleId::new(1)));
        assert!(!candidate_ids_too_many_passengers.contains(&VehicleId::new(2)));
        assert!(!candidate_ids_too_many_passengers.contains(&VehicleId::new(3)));
        assert!(!candidate_ids_too_many_passengers.contains(&VehicleId::new(4)));
        assert!(!candidate_ids_too_many_passengers.contains(&VehicleId::new(5)));

        let candidate_ids_non_matching_start_and_target = d
            .get_candidate_vehicles(4, &test_points.bautzen_ost[0], &test_points.bautzen_west[1])
            .await
            .iter()
            .map(|vehicle| vehicle.id)
            .collect_vec();

        assert!(!candidate_ids_non_matching_start_and_target.contains(&VehicleId::new(1)));
        assert!(!candidate_ids_non_matching_start_and_target.contains(&VehicleId::new(2)));
        assert!(!candidate_ids_non_matching_start_and_target.contains(&VehicleId::new(3)));
        assert!(!candidate_ids_non_matching_start_and_target.contains(&VehicleId::new(4)));
        assert!(!candidate_ids_non_matching_start_and_target.contains(&VehicleId::new(5)));
    }

    #[traced_test]
    #[tokio::test]
    #[serial]
    async fn test_handle_request_concrete() {
        let db_conn = test_main().await;
        let mut d = init(&db_conn, true, 5000, InitType::BackendTest).await;

        let start_time = NaiveDate::from_ymd_opt(5000, 4, 19)
            .unwrap()
            .and_hms_opt(11, 5, 0)
            .unwrap();
        let test_points = TestPoints::new();

        assert_eq!(
            d.handle_routing_request(
                start_time,
                true,
                test_points.bautzen_ost[0].get_lat(),
                test_points.bautzen_ost[0].get_lng(),
                test_points.bautzen_ost[1].get_lat(),
                test_points.bautzen_ost[1].get_lng(),
                UserId::new(1),
                1,
                "start_address",
                "target_address",
            )
            .await,
            StatusCode::CREATED
        );

        assert_eq!(d.tour_count(), 1);
        assert_eq!(
            d.vehicles
                .iter()
                .flat_map(|v| v.tours.iter().flat_map(|t| &t.events))
                .count(),
            2
        );
        //reversed start and target coordinates in time for concatenation
        assert_eq!(
            d.handle_routing_request(
                start_time + Duration::minutes(55),
                true,
                test_points.bautzen_ost[0].get_lat(),
                test_points.bautzen_ost[0].get_lng(),
                test_points.bautzen_ost[1].get_lat(),
                test_points.bautzen_ost[1].get_lng(),
                UserId::new(1),
                1,
                "start_address",
                "target_address",
            )
            .await,
            StatusCode::CREATED
        );
        assert_eq!(d.tour_count(), 1);
        assert_eq!(
            d.vehicles
                .iter()
                .flat_map(|v| v.tours.iter().flat_map(|t| &t.events))
                .count(),
            4
        );

        assert_eq!(
            d.handle_routing_request(
                start_time,
                true,
                test_points.bautzen_ost[0].get_lat(),
                test_points.bautzen_ost[0].get_lng(),
                test_points.bautzen_ost[1].get_lat(),
                test_points.bautzen_ost[1].get_lng(),
                UserId::new(1),
                1,
                "start_address",
                "target_address",
            )
            .await,
            StatusCode::CREATED
        );

        //repeat first request - no tour-concatenation and out of availability for other vehicles -> request denied
        assert_eq!(
            d.handle_routing_request(
                start_time,
                true,
                test_points.bautzen_ost[0].get_lat(),
                test_points.bautzen_ost[0].get_lng(),
                test_points.bautzen_ost[1].get_lat(),
                test_points.bautzen_ost[1].get_lng(),
                UserId::new(1),
                1,
                "start_address",
                "target_address",
            )
            .await,
            StatusCode::NO_CONTENT
        );
        check_data_db_synchronized(&d).await;
    }

    #[traced_test]
    #[tokio::test]
    #[serial]
    async fn test_handle_request_append() {
        let db_conn = test_main().await;
        let mut d = init(&db_conn, true, 5000, InitType::BackendTest).await;

        let start_time = NaiveDate::from_ymd_opt(5000, 4, 19)
            .unwrap()
            .and_hms_opt(11, 15, 0)
            .unwrap();
        let test_points = TestPoints::new();

        assert_eq!(
            d.handle_routing_request(
                start_time,
                true,
                test_points.bautzen_ost[0].get_lat(),
                test_points.bautzen_ost[0].get_lng(),
                test_points.bautzen_ost[2].get_lat(),
                test_points.bautzen_ost[2].get_lng(),
                UserId::new(1),
                1,
                "start_address",
                "target_address",
            )
            .await,
            StatusCode::CREATED
        );
        assert_eq!(d.tour_count(), 1);
        assert_eq!(
            d.vehicles
                .iter()
                .flat_map(|v| v.tours.iter().flat_map(|t| &t.events))
                .count(),
            2
        );
        //reversed start and target coordinates in time for concatenation
        assert_eq!(
            d.handle_routing_request(
                start_time + Duration::minutes(55),
                true,
                test_points.bautzen_ost[2].get_lat(),
                test_points.bautzen_ost[2].get_lng(),
                test_points.bautzen_ost[0].get_lat(),
                test_points.bautzen_ost[0].get_lng(),
                UserId::new(1),
                1,
                "start_address",
                "target_address",
            )
            .await,
            StatusCode::CREATED
        );
        assert_eq!(d.tour_count(), 1);
        assert_eq!(
            d.vehicles
                .iter()
                .flat_map(|v| v.tours.iter().flat_map(|t| &t.events))
                .count(),
            4
        );
    }

    #[traced_test]
    #[tokio::test]
    #[serial]
    async fn test_handle_request_prepend() {
        let db_conn = test_main().await;
        let mut d = init(&db_conn, true, 5000, InitType::BackendTest).await;

        let start_time = NaiveDate::from_ymd_opt(5000, 4, 19)
            .unwrap()
            .and_hms_opt(12, 30, 0)
            .unwrap();
        let test_points = TestPoints::new();

        assert_eq!(
            d.handle_routing_request(
                start_time,
                true,
                test_points.bautzen_ost[0].get_lat(),
                test_points.bautzen_ost[0].get_lng(),
                test_points.bautzen_ost[1].get_lat(),
                test_points.bautzen_ost[1].get_lng(),
                UserId::new(1),
                1,
                "start_address",
                "target_address",
            )
            .await,
            StatusCode::CREATED
        );
        assert_eq!(d.tour_count(), 1);
        assert_eq!(
            d.vehicles
                .iter()
                .flat_map(|v| v.tours.iter().flat_map(|t| &t.events))
                .count(),
            2
        );
        //reversed start and target coordinates with fixed target time instead of fixed start time, in time for prepend
        assert_eq!(
            d.handle_routing_request(
                start_time - Duration::minutes(15),
                false,
                test_points.bautzen_ost[1].get_lat(),
                test_points.bautzen_ost[1].get_lng(),
                test_points.bautzen_ost[0].get_lat(),
                test_points.bautzen_ost[0].get_lng(),
                UserId::new(1),
                2,
                "target_address",
                "start_address",
            )
            .await,
            StatusCode::CREATED
        );
        // since there are only 2 requests and those were concatenated, there must be 1 vehicle doing 1 tour with 4 events all other vehicles must not have any tours.
        let mut vehicle_with_tours_found = false;
        for v in d.vehicles.iter() {
            if vehicle_with_tours_found {
                assert!(v.tours.is_empty());
            }
            if !v.tours.is_empty() {
                assert_eq!(v.tours.len(), 1);
                assert_eq!(v.tours.iter().flat_map(|t| &t.events).count(), 4);
                vehicle_with_tours_found = true;
            }
        }
        // since the second request was prepended to the first one, the earliest event must be part of the 2nd request.
        assert_eq!(
            d.vehicles
                .iter()
                .filter(|v| !v.tours.is_empty())
                .flat_map(|v| &v.tours)
                .flat_map(|t| &t.events)
                .min_by_key(|ev| ev.scheduled_time)
                .unwrap()
                .request_id,
            2,
        );
    }

    #[tokio::test]
    #[serial]
    async fn test_change_vehicle_concrete() {
        let db_conn = test_main().await;
        let mut d = init(&db_conn, true, 5000, InitType::BackendTestWithEvents).await;

        // verify that tour with id 1 is done by vehicle with id 1
        let tour = d.get_tour(TourId::new(1)).await;
        assert!(tour.is_ok());
        let tour = tour.unwrap();
        assert_eq!(tour.vehicle, VehicleId::new(1));

        // old and new vehicle are the same
        assert_eq!(
            d.change_vehicle_for_tour(TourId::new(1), VehicleId::new(1))
                .await,
            StatusCode::NO_CONTENT
        );

        // change possible
        assert_eq!(
            d.change_vehicle_for_tour(TourId::new(1), VehicleId::new(2))
                .await,
            StatusCode::OK
        )
    }

    #[traced_test]
    #[tokio::test]
    #[serial]
    async fn test_change_vehicle_statuscodes() {
        let db_conn = test_main().await;
        let mut d = init(&db_conn, true, 5000, InitType::BackendTest).await;

        let start_time = NaiveDate::from_ymd_opt(5000, 4, 19)
            .unwrap()
            .and_hms_opt(12, 20, 0)
            .unwrap();
        let test_points = TestPoints::new();

        assert_eq!(
            d.handle_routing_request(
                start_time,
                true,
                test_points.bautzen_ost[0].get_lat(),
                test_points.bautzen_ost[0].get_lng(),
                test_points.bautzen_ost[2].get_lat(),
                test_points.bautzen_ost[2].get_lng(),
                UserId::new(1),
                1,
                "start_address",
                "target_address",
            )
            .await,
            StatusCode::CREATED
        );
    }

    #[tokio::test]
    #[serial]
    async fn get_vehicles_test() {
        let db_conn = test_main().await;
        let d = init(&db_conn, true, 5000, InitType::BackendTest).await;

        let c1_license_plates = ["TUB1-1", "TUB1-2"];
        let c2_license_plates = ["TUB2-1", "TUB2-2"];
        let c3_license_plates = ["TUG1-1"];

        let c1_res = d.get_vehicles(CompanyId::new(1)).await;
        assert!(c1_res.is_ok());
        let c1 = c1_res.unwrap();
        assert_eq!(c1.len(), 2);
        assert!(c1_license_plates.contains(&(*c1[0]).get_license_plate().await));
        assert!(c1_license_plates.contains(&(*c1[1]).get_license_plate().await));

        let c2_res = d.get_vehicles(CompanyId::new(2)).await;
        assert!(c2_res.is_ok());
        let c2 = c2_res.unwrap();
        assert_eq!(c2.len(), 2);
        assert!(c2_license_plates.contains(&(*c2[0]).get_license_plate().await));
        assert!(c2_license_plates.contains(&(*c2[1]).get_license_plate().await));

        let c3_res = d.get_vehicles(CompanyId::new(3)).await;
        assert!(c3_res.is_ok());
        let c3 = c3_res.unwrap();
        assert_eq!(c3.len(), 1);
        assert!(c3_license_plates.contains(&(*c3[0]).get_license_plate().await));
        /*
        let c4_res = d.get_vehicles(CompanyId::new(4)).await;
        assert!(c4_res.is_err());
        assert_eq!(c4_res.err(), Some(StatusCode::NOT_FOUND));
         */
    }

    #[tokio::test]
    #[serial]
    async fn get_company_for_user_test() {
        let db_conn = test_main().await;
        let d = init(&db_conn, true, 5000, InitType::BackendTest).await;

        let c1 = d.get_company_for_user(&d.users[&UserId::new(1)]).await;
        assert!(c1.is_some());
        let c1 = c1.unwrap();
        assert!(c1.is_ok());
        let c1 = *c1.unwrap();
        assert_eq!(c1.get_name().await, "Taxi-Unternehmen Bautzen-1");

        let c2 = d.get_company_for_user(&d.users[&UserId::new(2)]).await;
        assert!(c2.is_none());
    }

    #[tokio::test]
    #[serial]
    async fn get_company_for_vehicle_test() {
        let db_conn = test_main().await;
        let d = init(&db_conn, true, 5000, InitType::BackendTest).await;

        let c1 = d
            .get_company_for_vehicle(d.vehicles.get(VehicleId::new(1)))
            .await;
        assert!(c1.is_ok());
        let c1 = *c1.unwrap();
        assert_eq!(c1.get_name().await, "Taxi-Unternehmen Bautzen-1");

        let c2 = d
            .get_company_for_vehicle(d.vehicles.get(VehicleId::new(2)))
            .await;
        assert!(c2.is_ok());
        let c2 = *c2.unwrap();
        assert_eq!(c2.get_name().await, "Taxi-Unternehmen Bautzen-1");

        let c3 = d
            .get_company_for_vehicle(d.vehicles.get(VehicleId::new(3)))
            .await;
        assert!(c3.is_ok());
        let c3 = *c3.unwrap();
        assert_eq!(c3.get_name().await, "Taxi-Unternehmen Bautzen-2");

        let c4 = d
            .get_company_for_vehicle(d.vehicles.get(VehicleId::new(4)))
            .await;
        assert!(c4.is_ok());
        let c4 = *c4.unwrap();
        assert_eq!(c4.get_name().await, "Taxi-Unternehmen Bautzen-2");

        let c5 = d
            .get_company_for_vehicle(d.vehicles.get(VehicleId::new(5)))
            .await;
        assert!(c5.is_ok());
        let c5 = *c5.unwrap();
        assert_eq!(c5.get_name().await, "Taxi-Unternehmen Görlitz-1");
    }

    #[tokio::test]
    #[serial]
    async fn get_customer_for_event_test() {
        let db_conn = test_main().await;
        let d = init(&db_conn, true, 5000, InitType::BackendTestWithEvents).await;

        let events = d
            .vehicles
            .iter()
            .flat_map(|v| v.tours.iter().flat_map(|t| &t.events))
            .sorted_by_key(|event| &event.id)
            .collect_vec();

        let u1 = d.get_customer_for_event(events[0]).await;
        assert!(u1.is_ok());
        let u1 = u1.unwrap();
        assert_eq!(u1.get_name().await, "TestDriver1");
        assert_eq!(u1.get_id().await, UserId::new(1));

        let u2 = d.get_customer_for_event(events[1]).await;
        assert!(u2.is_ok());
        let u2 = u2.unwrap();
        assert_eq!(u2.get_name().await, "TestDriver1");
        assert_eq!(u2.get_id().await, UserId::new(1));

        let u3 = d.get_customer_for_event(events[2]).await;
        assert!(u3.is_ok());
        let u3 = u3.unwrap();
        assert_eq!(u3.get_name().await, "TestDriver1");
        assert_eq!(u3.get_id().await, UserId::new(1));

        let u4 = d.get_customer_for_event(events[3]).await;
        assert!(u4.is_ok());
        let u4 = u4.unwrap();
        assert_eq!(u4.get_name().await, "TestDriver1");
        assert_eq!(u4.get_id().await, UserId::new(1));

        let u5 = d.get_customer_for_event(events[4]).await;
        assert!(u5.is_ok());
        let u5 = u5.unwrap();
        assert_eq!(u5.get_name().await, "TestUser1");
        assert_eq!(u5.get_id().await, UserId::new(2));

        let u6 = d.get_customer_for_event(events[5]).await;
        assert!(u6.is_ok());
        let u6 = u6.unwrap();
        assert_eq!(u6.get_name().await, "TestUser1");
        assert_eq!(u6.get_id().await, UserId::new(2));
    }

    #[tokio::test]
    #[serial]
    async fn get_address_for_event_test() {
        let db_conn = test_main().await;
        let d = init(&db_conn, true, 5000, InitType::BackendTestWithEvents).await;

        let events = d
            .vehicles
            .iter()
            .flat_map(|v| v.tours.iter().flat_map(|t| &t.events))
            .sorted_by_key(|event| &event.id)
            .collect_vec();

        assert_eq!(d.get_address_for_event(events[0]).await, "start_address");
        assert_eq!(d.get_address_for_event(events[1]).await, "target_address");
        assert_eq!(d.get_address_for_event(events[2]).await, "start_address");
        assert_eq!(d.get_address_for_event(events[3]).await, "target_address");
        assert_eq!(d.get_address_for_event(events[4]).await, "start_address");
        assert_eq!(d.get_address_for_event(events[5]).await, "target_address");
    }
}
