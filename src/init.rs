use crate::{
    backend::{
        data::Data,
        id_types::{CompanyId, UserId, VehicleId, ZoneId},
        lat_long::{Latitude, Longitude},
        lib::{
            AvailabilityCrud, CompanyCrud, PrimaData, TourCrud, UserCrud, VehicleCrud, ZoneCrud,
        },
    },
    constants::geojson_strings::{
        bautzen_ost::BAUTZEN_OST, bautzen_west::BAUTZEN_WEST, gorlitz::GORLITZ,
    },
    entities::{
        address, availability, company, event, prelude::User, request, tour, user, vehicle, zone,
    },
    error,
};
use chrono::{Datelike, NaiveDate, Utc};
use migration::ConnectionTrait;
use sea_orm::{DbConn, EntityTrait};

pub enum InitType {
    BackendTest,
    BackendTestWithEvents,
    FrontEnd,
    Default,
}

pub async fn clear(db_conn: &DbConn) {
    match event::Entity::delete_many().exec(db_conn).await {
        Ok(_) => {
            if let Err(e) = db_conn
                .execute_unprepared("ALTER SEQUENCE event_id_seq RESTART WITH 1")
                .await
            {
                error!("{e:?}");
                panic!();
            }
        }
        Err(e) => {
            error!("{e:?}");
            panic!();
        }
    }
    match address::Entity::delete_many().exec(db_conn).await {
        Ok(_) => {
            if let Err(e) = db_conn
                .execute_unprepared("ALTER SEQUENCE address_id_seq RESTART WITH 1")
                .await
            {
                error!("{e:?}");
                panic!();
            }
        }
        Err(e) => {
            error!("{e:?}");
            panic!();
        }
    }
    match request::Entity::delete_many().exec(db_conn).await {
        Ok(_) => {
            if let Err(e) = db_conn
                .execute_unprepared("ALTER SEQUENCE request_id_seq RESTART WITH 1")
                .await
            {
                {
                    error!("{e:?}");
                    panic!();
                }
            }
        }
        Err(e) => {
            error!("{e:?}");
            panic!();
        }
    }
    match tour::Entity::delete_many().exec(db_conn).await {
        Ok(_) => {
            if let Err(e) = db_conn
                .execute_unprepared("ALTER SEQUENCE tour_id_seq RESTART WITH 1")
                .await
            {
                {
                    error!("{e:?}");
                    panic!();
                }
            }
        }
        Err(e) => {
            error!("{e:?}");
            panic!();
        }
    }
    match availability::Entity::delete_many().exec(db_conn).await {
        Ok(_) => {
            if let Err(e) = db_conn
                .execute_unprepared("ALTER SEQUENCE availability_id_seq RESTART WITH 1")
                .await
            {
                {
                    error!("{e:?}");
                    panic!();
                }
            }
        }
        Err(e) => {
            error!("{e:?}");
            panic!();
        }
    }
    match vehicle::Entity::delete_many().exec(db_conn).await {
        Ok(_) => {
            if let Err(e) = db_conn
                .execute_unprepared("ALTER SEQUENCE vehicle_id_seq RESTART WITH 1")
                .await
            {
                {
                    error!("{e:?}");
                    panic!();
                }
            }
        }
        Err(e) => {
            error!("{e:?}");
            panic!();
        }
    }
    match user::Entity::delete_many().exec(db_conn).await {
        Ok(_) => {
            if let Err(e) = db_conn
                .execute_unprepared("ALTER SEQUENCE user_id_seq RESTART WITH 1")
                .await
            {
                {
                    error!("{e:?}");
                    panic!();
                }
            }
        }
        Err(e) => {
            error!("{e:?}");
            panic!();
        }
    }
    match company::Entity::delete_many().exec(db_conn).await {
        Ok(_) => {
            if let Err(e) = db_conn
                .execute_unprepared("ALTER SEQUENCE company_id_seq RESTART WITH 1")
                .await
            {
                {
                    error!("{e:?}");
                    panic!();
                }
            }
        }
        Err(e) => {
            error!("{e:?}");
            panic!();
        }
    }
    match zone::Entity::delete_many().exec(db_conn).await {
        Ok(_) => {
            if let Err(e) = db_conn
                .execute_unprepared("ALTER SEQUENCE zone_id_seq RESTART WITH 1")
                .await
            {
                {
                    error!("{e:?}");
                    panic!();
                }
            }
        }
        Err(e) => {
            error!("{e:?}");
            panic!();
        }
    }
    println!("clear succesful");
}

pub async fn init(
    db_conn: &DbConn,
    clear_tables: bool,
    year: i32,
    t: InitType,
) -> Data {
    if clear_tables {
        clear(db_conn).await;
    }
    if let Ok(u) = User::find().all(db_conn).await {
        if !u.is_empty() {
            println!("users already exist, not running init() again.");
            let mut data = Data::new(db_conn);
            data.read_data_from_db().await;
            return data;
        }
    }
    match t {
        InitType::Default => init_default(db_conn, year).await,
        InitType::FrontEnd => init_frontend(db_conn, year).await,
        InitType::BackendTest => init_backend_test(db_conn, year).await,
        InitType::BackendTestWithEvents => init_backend_test_with_events(db_conn, year).await,
    }
}

async fn init_frontend(
    db_conn: &DbConn,
    _year: i32,
) -> Data {
    Data::new(db_conn)
}

async fn init_backend_test(
    db_conn: &DbConn,
    year: i32,
) -> Data {
    let mut data = Data::new(db_conn);

    data.create_zone("Bautzen Ost", BAUTZEN_OST).await;
    data.create_zone("Bautzen West", BAUTZEN_WEST).await;
    data.create_zone("Görlitz", GORLITZ).await;

    data.create_company(
        "Taxi-Unternehmen Bautzen-1",
        ZoneId::new(1),
        ZoneId::new(1),
        "a@b",
        Latitude::new(51.203935),
        Longitude::new(13.941692),
    )
    .await;
    data.create_company(
        "Taxi-Unternehmen Bautzen-2",
        ZoneId::new(2),
        ZoneId::new(2),
        "b@c",
        Latitude::new(51.31332),
        Longitude::new(14.030458),
    )
    .await;
    data.create_company(
        "Taxi-Unternehmen Görlitz-1",
        ZoneId::new(3),
        ZoneId::new(3),
        "c@d",
        Latitude::new(51.27332),
        Longitude::new(14.031458),
    )
    .await;

    data.create_user(
        "TestDriver1",
        true,
        false,
        Some(CompanyId::new(1)),
        false,
        "test@aol.com",
        Some("".to_string()),
        "",
        Some("".to_string()),
        Some("".to_string()),
    )
    .await;

    data.create_user(
        "TestUser1",
        false,
        false,
        None,
        false,
        "test@web.com",
        Some("".to_string()),
        "",
        Some("".to_string()),
        Some("".to_string()),
    )
    .await;

    data.create_vehicle("TUB1-1", CompanyId::new(1)).await;
    data.create_vehicle("TUB1-2", CompanyId::new(1)).await;
    data.create_vehicle("TUB2-1", CompanyId::new(2)).await;
    data.create_vehicle("TUB2-2", CompanyId::new(2)).await;
    data.create_vehicle("TUG1-1", CompanyId::new(3)).await;

    data.create_availability(
        NaiveDate::from_ymd_opt(year, 4, 19)
            .unwrap()
            .and_hms_opt(10, 10, 0)
            .unwrap(),
        NaiveDate::from_ymd_opt(year, 4, 19)
            .unwrap()
            .and_hms_opt(14, 0, 0)
            .unwrap(),
        VehicleId::new(1),
    )
    .await;

    data.create_availability(
        NaiveDate::from_ymd_opt(year, 4, 19)
            .unwrap()
            .and_hms_opt(10, 10, 0)
            .unwrap(),
        NaiveDate::from_ymd_opt(year, 4, 19)
            .unwrap()
            .and_hms_opt(14, 0, 0)
            .unwrap(),
        VehicleId::new(2),
    )
    .await;

    data.create_availability(
        NaiveDate::from_ymd_opt(year, 4, 19)
            .unwrap()
            .and_hms_opt(10, 10, 0)
            .unwrap(),
        NaiveDate::from_ymd_opt(year, 4, 19)
            .unwrap()
            .and_hms_opt(14, 0, 0)
            .unwrap(),
        VehicleId::new(3),
    )
    .await;

    data
}

async fn init_backend_test_with_events(
    db_conn: &DbConn,
    year: i32,
) -> Data {
    let mut data = Data::new(db_conn);

    data.create_zone("Bautzen Ost", BAUTZEN_OST).await;
    data.create_zone("Bautzen West", BAUTZEN_WEST).await;
    data.create_zone("Görlitz", GORLITZ).await;

    data.create_company(
        "Taxi-Unternehmen Bautzen-1",
        ZoneId::new(1),
        ZoneId::new(1),
        "a@b",
        Latitude::new(51.203935),
        Longitude::new(13.941692),
    )
    .await;
    data.create_company(
        "Taxi-Unternehmen Bautzen-2",
        ZoneId::new(2),
        ZoneId::new(2),
        "b@c",
        Latitude::new(51.31332),
        Longitude::new(14.030458),
    )
    .await;
    data.create_company(
        "Taxi-Unternehmen Görlitz-1",
        ZoneId::new(3),
        ZoneId::new(3),
        "c@d",
        Latitude::new(51.27332),
        Longitude::new(14.031458),
    )
    .await;

    data.create_user(
        "TestDriver1",
        true,
        false,
        Some(CompanyId::new(1)),
        false,
        "test@aol.com",
        Some("".to_string()),
        "",
        Some("".to_string()),
        Some("".to_string()),
    )
    .await;

    data.create_user(
        "TestUser1",
        false,
        false,
        None,
        false,
        "test@web.com",
        Some("".to_string()),
        "",
        Some("".to_string()),
        Some("".to_string()),
    )
    .await;

    data.create_vehicle("TUB1-1", CompanyId::new(1)).await;
    data.create_vehicle("TUB1-2", CompanyId::new(1)).await;
    data.create_vehicle("TUB2-1", CompanyId::new(2)).await;
    data.create_vehicle("TUB2-2", CompanyId::new(2)).await;
    data.create_vehicle("TUG1-1", CompanyId::new(3)).await;

    data.create_availability(
        NaiveDate::from_ymd_opt(year, 4, 19)
            .unwrap()
            .and_hms_opt(10, 10, 0)
            .unwrap(),
        NaiveDate::from_ymd_opt(year, 4, 19)
            .unwrap()
            .and_hms_opt(14, 0, 0)
            .unwrap(),
        VehicleId::new(1),
    )
    .await;

    data.create_availability(
        NaiveDate::from_ymd_opt(year, 4, 19)
            .unwrap()
            .and_hms_opt(10, 10, 0)
            .unwrap(),
        NaiveDate::from_ymd_opt(year, 4, 19)
            .unwrap()
            .and_hms_opt(14, 0, 0)
            .unwrap(),
        VehicleId::new(2),
    )
    .await;

    data.create_availability(
        NaiveDate::from_ymd_opt(year, 4, 19)
            .unwrap()
            .and_hms_opt(10, 10, 0)
            .unwrap(),
        NaiveDate::from_ymd_opt(year, 4, 19)
            .unwrap()
            .and_hms_opt(14, 0, 0)
            .unwrap(),
        VehicleId::new(3),
    )
    .await;

    data.insert_or_addto_tour(
        None,
        NaiveDate::from_ymd_opt(year, 4, 19)
            .unwrap()
            .and_hms_opt(10, 10, 0)
            .unwrap(),
        NaiveDate::from_ymd_opt(year, 4, 19)
            .unwrap()
            .and_hms_opt(11, 00, 0)
            .unwrap(),
        VehicleId::new(1),
        "start_address",
        "target_address",
        Latitude::new(51.203935),
        Longitude::new(13.941692),
        NaiveDate::from_ymd_opt(year, 4, 19)
            .unwrap()
            .and_hms_opt(10, 15, 0)
            .unwrap(),
        NaiveDate::from_ymd_opt(year, 4, 19)
            .unwrap()
            .and_hms_opt(10, 15, 0)
            .unwrap(),
        UserId::new(1),
        1,
        0,
        0,
        Latitude::new(51.203935),
        Longitude::new(13.941692),
        NaiveDate::from_ymd_opt(year, 4, 19)
            .unwrap()
            .and_hms_opt(10, 50, 0)
            .unwrap(),
        NaiveDate::from_ymd_opt(year, 4, 19)
            .unwrap()
            .and_hms_opt(10, 50, 0)
            .unwrap(),
    )
    .await;

    data.insert_or_addto_tour(
        None,
        NaiveDate::from_ymd_opt(year, 4, 19)
            .unwrap()
            .and_hms_opt(12, 10, 0)
            .unwrap(),
        NaiveDate::from_ymd_opt(year, 4, 19)
            .unwrap()
            .and_hms_opt(13, 0, 0)
            .unwrap(),
        VehicleId::new(2),
        "start_address",
        "target_address",
        Latitude::new(51.203935),
        Longitude::new(13.941692),
        NaiveDate::from_ymd_opt(year, 4, 19)
            .unwrap()
            .and_hms_opt(12, 15, 0)
            .unwrap(),
        NaiveDate::from_ymd_opt(year, 4, 19)
            .unwrap()
            .and_hms_opt(12, 15, 0)
            .unwrap(),
        UserId::new(1),
        1,
        0,
        0,
        Latitude::new(51.203935),
        Longitude::new(13.941692),
        NaiveDate::from_ymd_opt(year, 4, 19)
            .unwrap()
            .and_hms_opt(13, 5, 0)
            .unwrap(),
        NaiveDate::from_ymd_opt(year, 4, 19)
            .unwrap()
            .and_hms_opt(13, 5, 0)
            .unwrap(),
    )
    .await;

    data.insert_or_addto_tour(
        None,
        NaiveDate::from_ymd_opt(year, 4, 19)
            .unwrap()
            .and_hms_opt(10, 10, 0)
            .unwrap(),
        NaiveDate::from_ymd_opt(year, 4, 19)
            .unwrap()
            .and_hms_opt(10, 10, 0)
            .unwrap(),
        VehicleId::new(1),
        "start_address",
        "target_address",
        Latitude::new(51.203935),
        Longitude::new(13.941692),
        NaiveDate::from_ymd_opt(year, 4, 19)
            .unwrap()
            .and_hms_opt(10, 10, 0)
            .unwrap(),
        NaiveDate::from_ymd_opt(year, 4, 19)
            .unwrap()
            .and_hms_opt(10, 10, 0)
            .unwrap(),
        UserId::new(2),
        1,
        0,
        0,
        Latitude::new(51.203935),
        Longitude::new(13.941692),
        NaiveDate::from_ymd_opt(year, 4, 19)
            .unwrap()
            .and_hms_opt(10, 50, 0)
            .unwrap(),
        NaiveDate::from_ymd_opt(year, 4, 19)
            .unwrap()
            .and_hms_opt(10, 50, 0)
            .unwrap(),
    )
    .await;

    data
}

async fn init_default(
    db_conn: &DbConn,
    year: i32,
) -> Data {
    let now = Utc::now().naive_utc();
    let this_year = now.year();
    let this_month = now.month();
    let this_day = now.day();
    let today = NaiveDate::from_ymd_opt(this_year, this_month, this_day).unwrap();

    let mut data = Data::new(db_conn);

    data.create_zone("Bautzen Ost", BAUTZEN_OST).await;
    data.create_zone("Bautzen West", BAUTZEN_WEST).await;
    data.create_zone("Görlitz", GORLITZ).await;

    data.create_company(
        "Taxi-Unternehmen Bautzen-1",
        ZoneId::new(2),
        ZoneId::new(2),
        "a@b",
        Latitude::new(51.220826),
        Longitude::new(13.895984),
    )
    .await;
    data.create_company(
        "Taxi-Unternehmen Bautzen-2",
        ZoneId::new(2),
        ZoneId::new(2),
        "b@c",
        Latitude::new(51.316338),
        Longitude::new(14.034681),
    )
    .await;
    data.create_company(
        "Taxi-Unternehmen Bautzen-3",
        ZoneId::new(2),
        ZoneId::new(2),
        "c@d",
        Latitude::new(51.46705),
        Longitude::new(14.179674),
    )
    .await;
    data.create_company(
        "Taxi-Unternehmen Bautzen-4",
        ZoneId::new(1),
        ZoneId::new(1),
        "d@e",
        Latitude::new(51.27251),
        Longitude::new(14.244972),
    )
    .await;
    data.create_company(
        "Taxi-Unternehmen Bautzen-5",
        ZoneId::new(1),
        ZoneId::new(1),
        "e@f",
        Latitude::new(51.169107),
        Longitude::new(14.381821),
    )
    .await;
    data.create_company(
        "Taxi-Unternehmen Görlitz-1",
        ZoneId::new(3),
        ZoneId::new(3),
        "f@g",
        Latitude::new(51.43354),
        Longitude::new(14.70897),
    )
    .await;
    data.create_company(
        "Taxi-Unternehmen Görlitz-2",
        ZoneId::new(3),
        ZoneId::new(3),
        "g@h",
        Latitude::new(51.221655),
        Longitude::new(14.879525),
    )
    .await;
    data.create_company(
        "Taxi-Unternehmen Görlitz-3",
        ZoneId::new(3),
        ZoneId::new(3),
        "h@i",
        Latitude::new(51.0419),
        Longitude::new(14.7537362),
    )
    .await;

    data.create_user(
        "TestDriver1",
        true,
        false,
        Some(CompanyId::new(1)),
        false,
        "test@aol.com",
        Some("".to_string()),
        "",
        Some("".to_string()),
        Some("".to_string()),
    )
    .await;

    data.create_user(
        "TestUser1",
        false,
        false,
        None,
        false,
        "test@web.com",
        Some("".to_string()),
        "",
        Some("".to_string()),
        Some("".to_string()),
    )
    .await;

    data.create_user(
        "TestUser2",
        false,
        false,
        None,
        false,
        "test@mail.com",
        Some("".to_string()),
        "",
        Some("".to_string()),
        Some("".to_string()),
    )
    .await;

    data.create_vehicle("TUB1-1", CompanyId::new(1)).await;
    data.create_vehicle("TUB1-2", CompanyId::new(1)).await;
    data.create_vehicle("TUB1-3", CompanyId::new(1)).await;
    data.create_vehicle("TUB1-4", CompanyId::new(1)).await;
    data.create_vehicle("TUB1-5", CompanyId::new(1)).await;
    data.create_vehicle("TUB2-1", CompanyId::new(2)).await;
    data.create_vehicle("TUB2-2", CompanyId::new(2)).await;
    data.create_vehicle("TUB2-3", CompanyId::new(2)).await;
    data.create_vehicle("TUB3-1", CompanyId::new(3)).await;
    data.create_vehicle("TUB3-2", CompanyId::new(3)).await;
    data.create_vehicle("TUB3-3", CompanyId::new(3)).await;
    data.create_vehicle("TUB3-4", CompanyId::new(3)).await;
    data.create_vehicle("TUB4-1", CompanyId::new(4)).await;
    data.create_vehicle("TUB4-2", CompanyId::new(4)).await;
    data.create_vehicle("TUB5-1", CompanyId::new(5)).await;
    data.create_vehicle("TUB5-2", CompanyId::new(5)).await;
    data.create_vehicle("TUB5-3", CompanyId::new(5)).await;
    data.create_vehicle("TUG1-1", CompanyId::new(6)).await;
    data.create_vehicle("TUG1-2", CompanyId::new(6)).await;
    data.create_vehicle("TUG1-3", CompanyId::new(6)).await;
    data.create_vehicle("TUG2-1", CompanyId::new(7)).await;
    data.create_vehicle("TUG2-2", CompanyId::new(7)).await;
    data.create_vehicle("TUG2-3", CompanyId::new(7)).await;
    data.create_vehicle("TUG2-4", CompanyId::new(7)).await;
    data.create_vehicle("TUG3-1", CompanyId::new(8)).await;
    data.create_vehicle("TUG3-2", CompanyId::new(8)).await;
    data.create_vehicle("TUG3-3", CompanyId::new(8)).await;
    data.create_vehicle("TUG3-4", CompanyId::new(8)).await;
    data.create_vehicle("TUG3-5", CompanyId::new(8)).await;

    data.insert_or_addto_tour(
        None,
        today.and_hms_opt(9, 10, 0).unwrap(),
        today.and_hms_opt(10, 0, 0).unwrap(),
        VehicleId::new(1),
        "karolinenplatz 5",
        "Lichtwiesenweg 3",
        Latitude::new(51.22069),
        Longitude::new(13.867512),
        NaiveDate::from_ymd_opt(year, 4, 19)
            .unwrap()
            .and_hms_opt(9, 15, 0)
            .unwrap(),
        NaiveDate::from_ymd_opt(year, 4, 19)
            .unwrap()
            .and_hms_opt(9, 12, 0)
            .unwrap(),
        UserId::new(2),
        3,
        0,
        0,
        Latitude::new(51.195075),
        Longitude::new(14.025081),
        today.and_hms_opt(9, 55, 0).unwrap(),
        today.and_hms_opt(9, 18, 0).unwrap(),
    )
    .await;

    data.create_availability(
        today.and_hms_opt(10, 10, 0).unwrap(),
        today.and_hms_opt(14, 0, 0).unwrap(),
        VehicleId::new(1),
    )
    .await;

    data.create_availability(
        today.and_hms_opt(10, 10, 0).unwrap(),
        today.and_hms_opt(14, 0, 0).unwrap(),
        VehicleId::new(2),
    )
    .await;

    data.create_availability(
        today.and_hms_opt(10, 10, 0).unwrap(),
        today.and_hms_opt(14, 0, 0).unwrap(),
        VehicleId::new(3),
    )
    .await;
    data
}
