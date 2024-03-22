use crate::{
    be::backend::Data,
    constants::{
        bautzen_split_ost::BAUTZEN_OST, bautzen_split_west::BAUTZEN_WEST, gorlitz::GORLITZ,
    },
    entities::{
        assignment, availability, company, event, prelude::User, user, vehicle, vehicle_specifics,
        zone,
    },
    AppState,
};
use sea_orm::EntityTrait;

use axum::extract::State;
use chrono::NaiveDate;
use migration::ConnectionTrait;

async fn clear(State(s): State<AppState>) {
    match event::Entity::delete_many().exec(s.db()).await {
        Ok(_) => match State(s.clone())
            .db()
            .execute_unprepared("ALTER SEQUENCE event_id_seq RESTART WITH 1")
            .await
        {
            Ok(_) => (),
            Err(e) => println!("{}", e),
        },
        Err(e) => println!("{}", e),
    }
    match assignment::Entity::delete_many().exec(s.db()).await {
        Ok(_) => match State(s.clone())
            .db()
            .execute_unprepared("ALTER SEQUENCE assignment_id_seq RESTART WITH 1")
            .await
        {
            Ok(_) => (),
            Err(e) => println!("{}", e),
        },
        Err(e) => println!("{}", e),
    }
    match availability::Entity::delete_many().exec(s.db()).await {
        Ok(_) => match State(s.clone())
            .db()
            .execute_unprepared("ALTER SEQUENCE availability_id_seq RESTART WITH 1")
            .await
        {
            Ok(_) => (),
            Err(e) => println!("{}", e),
        },
        Err(e) => println!("{}", e),
    }
    match vehicle::Entity::delete_many().exec(s.db()).await {
        Ok(_) => match State(s.clone())
            .db()
            .execute_unprepared("ALTER SEQUENCE vehicle_id_seq RESTART WITH 1")
            .await
        {
            Ok(_) => (),
            Err(e) => println!("{}", e),
        },
        Err(e) => println!("{}", e),
    }
    match company::Entity::delete_many().exec(s.db()).await {
        Ok(_) => match State(s.clone())
            .db()
            .execute_unprepared("ALTER SEQUENCE company_id_seq RESTART WITH 1")
            .await
        {
            Ok(_) => (),
            Err(e) => println!("{}", e),
        },
        Err(e) => println!("{}", e),
    }
    match zone::Entity::delete_many().exec(s.db()).await {
        Ok(_) => match State(s.clone())
            .db()
            .execute_unprepared("ALTER SEQUENCE zone_id_seq RESTART WITH 1")
            .await
        {
            Ok(_) => (),
            Err(e) => println!("{}", e),
        },
        Err(e) => println!("{}", e),
    }
    match vehicle_specifics::Entity::delete_many().exec(s.db()).await {
        Ok(_) => match State(s.clone())
            .db()
            .execute_unprepared("ALTER SEQUENCE vehicle_specifics_id_seq RESTART WITH 1")
            .await
        {
            Ok(_) => (),
            Err(e) => println!("{}", e),
        },
        Err(e) => println!("{}", e),
    }
    match user::Entity::delete_many().exec(s.db()).await {
        Ok(_) => match State(s.clone())
            .db()
            .execute_unprepared("ALTER SEQUENCE user_id_seq RESTART WITH 1")
            .await
        {
            Ok(_) => (),
            Err(e) => println!("{}", e),
        },
        Err(e) => println!("{}", e),
    }
    println!("clear succesful");
}

pub async fn init(
    State(s): State<AppState>,
    clear_tables: bool,
) {
    if clear_tables {
        clear(State(s.clone())).await;
    } else {
        match User::find().all(s.clone().db()).await {
            Ok(u) => {
                if !u.is_empty() {
                    println!("users already exist, not running init() again.");
                    return;
                }
            }
            Err(_) => (),
        }
    }
    let mut data = Data::new();
    let mut read_from_db_data = Data::new();
    data.create_user(
        State(s.clone()),
        "TestDriver1".to_string(),
        true,
        false,
        "".to_string(),
        Some("".to_string()),
        "".to_string(),
        Some("".to_string()),
        Some("".to_string()),
    )
    .await;

    data.create_user(
        State(s.clone()),
        "TestUser1".to_string(),
        false,
        false,
        "".to_string(),
        Some("".to_string()),
        "".to_string(),
        Some("".to_string()),
        Some("".to_string()),
    )
    .await;

    data.create_user(
        State(s.clone()),
        "TestUser2".to_string(),
        false,
        false,
        "".to_string(),
        Some("".to_string()),
        "".to_string(),
        Some("".to_string()),
        Some("".to_string()),
    )
    .await;

    read_from_db_data.clear();
    read_from_db_data.read_data(State(s.clone())).await;
    println!(
        "=_=_=__=__=_=_=_=_=_==_=_=_==_=====_=_=_=_=_==___________________________________________________________________________________________________is data synchronized after creating user: {}",
        read_from_db_data == data
    );

    data.create_zone(
        State(s.clone()),
        "Bautzen Ost".to_string(),
        BAUTZEN_OST.to_string(),
    )
    .await;
    data.create_zone(
        State(s.clone()),
        "Bautzen West".to_string(),
        BAUTZEN_WEST.to_string(),
    )
    .await;
    data.create_zone(State(s.clone()), "Görlitz".to_string(), GORLITZ.to_string())
        .await;

    read_from_db_data.clear();
    read_from_db_data.read_data(State(s.clone())).await;
    println!(
        "=_=_=__=__=_=_=_=_=_==_=_=_==_=====_=_=_=_=_==___________________________________________________________________________________________________is data synchronized after creating zones: {}",
        read_from_db_data == data
    );

    data.create_company(
        State(s.clone()),
        "Taxi-Unternehmen Bautzen-1".to_string(),
        2,
        13.895983751721786,
        51.220826461859644,
    )
    .await;
    data.create_company(
        State(s.clone()),
        "Taxi-Unternehmen Bautzen-2".to_string(),
        2,
        14.034681384488607,
        51.31633774366952,
    )
    .await;
    data.create_company(
        State(s.clone()),
        "Taxi-Unternehmen Bautzen-3".to_string(),
        2,
        14.179674338162073,
        51.46704814415014,
    )
    .await;
    data.create_company(
        State(s.clone()),
        "Taxi-Unternehmen Bautzen-4".to_string(),
        1,
        14.244972698642613,
        51.27251252133357,
    )
    .await;
    data.create_company(
        State(s.clone()),
        "Taxi-Unternehmen Bautzen-5".to_string(),
        1,
        14.381821307922678,
        51.169106961190806,
    )
    .await;
    data.create_company(
        State(s.clone()),
        "Taxi-Unternehmen Görlitz-1".to_string(),
        3,
        14.708969872564097,
        51.43354047439519,
    )
    .await;
    data.create_company(
        State(s.clone()),
        "Taxi-Unternehmen Görlitz-2".to_string(),
        3,
        14.879525132220152,
        51.22165543174137,
    )
    .await;
    data.create_company(
        State(s.clone()),
        "Taxi-Unternehmen Görlitz-3".to_string(),
        3,
        14.753736228472121,
        51.04190085802671,
    )
    .await;

    read_from_db_data.clear();
    read_from_db_data.read_data(State(s.clone())).await;
    println!(
        "=_=_=__=__=_=_=_=_=_==_=_=_==_=====_=_=_=_=_==___________________________________________________________________________________________________is data synchronized after creating companies: {}",
        read_from_db_data == data
    );

    data.create_vehicle(State(s.clone()), "TUB1-1".to_string(), 1)
        .await;
    data.create_vehicle(State(s.clone()), "TUB1-2".to_string(), 1)
        .await;
    data.create_vehicle(State(s.clone()), "TUB1-3".to_string(), 1)
        .await;
    data.create_vehicle(State(s.clone()), "TUB1-4".to_string(), 1)
        .await;
    data.create_vehicle(State(s.clone()), "TUB1-5".to_string(), 1)
        .await;
    data.create_vehicle(State(s.clone()), "TUB2-1".to_string(), 2)
        .await;
    data.create_vehicle(State(s.clone()), "TUB2-2".to_string(), 2)
        .await;
    data.create_vehicle(State(s.clone()), "TUB2-3".to_string(), 2)
        .await;
    data.create_vehicle(State(s.clone()), "TUB3-1".to_string(), 3)
        .await;
    data.create_vehicle(State(s.clone()), "TUB3-2".to_string(), 3)
        .await;
    data.create_vehicle(State(s.clone()), "TUB3-3".to_string(), 3)
        .await;
    data.create_vehicle(State(s.clone()), "TUB3-4".to_string(), 3)
        .await;
    data.create_vehicle(State(s.clone()), "TUB4-1".to_string(), 4)
        .await;
    data.create_vehicle(State(s.clone()), "TUB4-2".to_string(), 4)
        .await;
    data.create_vehicle(State(s.clone()), "TUB5-1".to_string(), 5)
        .await;
    data.create_vehicle(State(s.clone()), "TUB5-2".to_string(), 5)
        .await;
    data.create_vehicle(State(s.clone()), "TUB5-3".to_string(), 5)
        .await;
    data.create_vehicle(State(s.clone()), "TUG1-1".to_string(), 6)
        .await;
    data.create_vehicle(State(s.clone()), "TUG1-2".to_string(), 6)
        .await;
    data.create_vehicle(State(s.clone()), "TUG1-3".to_string(), 6)
        .await;
    data.create_vehicle(State(s.clone()), "TUG2-1".to_string(), 7)
        .await;
    data.create_vehicle(State(s.clone()), "TUG2-2".to_string(), 7)
        .await;
    data.create_vehicle(State(s.clone()), "TUG2-3".to_string(), 7)
        .await;
    data.create_vehicle(State(s.clone()), "TUG2-4".to_string(), 7)
        .await;
    data.create_vehicle(State(s.clone()), "TUG3-1".to_string(), 8)
        .await;
    data.create_vehicle(State(s.clone()), "TUG3-2".to_string(), 8)
        .await;
    data.create_vehicle(State(s.clone()), "TUG3-3".to_string(), 8)
        .await;
    data.create_vehicle(State(s.clone()), "TUG3-4".to_string(), 8)
        .await;
    data.create_vehicle(State(s.clone()), "TUG3-5".to_string(), 8)
        .await;

    read_from_db_data.clear();
    read_from_db_data.read_data(State(s.clone())).await;
    println!(
        "=_=_=__=__=_=_=_=_=_==_=_=_==_=====_=_=_=_=_==___________________________________________________________________________________________________is data synchronized after creating vehicles: {}",
        read_from_db_data == data
    );

    data.create_availability(
        State(s.clone()),
        NaiveDate::from_ymd_opt(2024, 4, 15)
            .unwrap()
            .and_hms_opt(9, 10, 0)
            .unwrap(),
        NaiveDate::from_ymd_opt(2024, 4, 15)
            .unwrap()
            .and_hms_opt(9, 11, 0)
            .unwrap(),
        1,
    )
    .await;

    data.create_availability(
        State(s.clone()),
        NaiveDate::from_ymd_opt(2024, 4, 15)
            .unwrap()
            .and_hms_opt(9, 11, 0)
            .unwrap(),
        NaiveDate::from_ymd_opt(2024, 4, 15)
            .unwrap()
            .and_hms_opt(9, 12, 0)
            .unwrap(),
        1,
    )
    .await;

    read_from_db_data.clear();
    read_from_db_data.read_data(State(s.clone())).await;
    println!(
        "=_=_=__=__=_=_=_=_=_==_=_=_==_=====_=_=_=_=_==___________________________________________________________________________________________________is data synchronized after creating availabilites: {}",
        read_from_db_data == data
    );

    let assignments = data.get_assignments_for_vehicle(1, None, None).await;

    println!("assignments size: {}", assignments.len());
    for assignment in assignments.iter() {
        println!("id: {}", assignment.id);
    }

    for i in 1..9 {
        print_vehicles_of_company(&data, i);
    }

    data.insert_or_add_assignment(
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
        1,
        State(s.clone()),
        &"karolinenplatz 5".to_string(),
        &"Lichtwiesenweg 3".to_string(),
        13.867512445295205,
        51.22069201951501,
        NaiveDate::from_ymd_opt(2024, 4, 15)
            .unwrap()
            .and_hms_opt(9, 15, 0)
            .unwrap(),
        NaiveDate::from_ymd_opt(2024, 4, 15)
            .unwrap()
            .and_hms_opt(9, 12, 0)
            .unwrap(),
        2,
        1,
        1,
        false,
        false,
        14.025081097762154,
        51.195075641827316,
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

    read_from_db_data.clear();
    read_from_db_data.read_data(State(s.clone())).await;
    println!(
        "=_=_=__=__=_=_=_=_=_==_=_=_==_=====_=_=_=_=_==___________________________________________________________________________________________________is data synchronized after creating assignment: {}",
        read_from_db_data == data
    );

    for v in data.vehicles.iter() {
        println!(
            "id: {}: number of assignments: {}",
            v.id,
            v.assignments.len()
        );
    }

    println!(
        "number of assignments for vehicle 1: {} and number of the first assignments events: {}, departure: {}, arrival: {}, company: {}, vehicle: {}, id: {}",
        data.vehicles[0].assignments.len(),
        data.vehicles[0].assignments[0].events.len(),
        data.vehicles[0].assignments[0].departure,
        data.vehicles[0].assignments[0].arrival,
        data.vehicles[0].assignments[0].company,
        data.vehicles[0].assignments[0].vehicle,
        data.vehicles[0].assignments[0].id
    );
    println!(
        "event1: assginment:{},communicated_time:{},scheduled_time:{},x:{},y:{},company:{},id:{},customer:{},is_pickup:{},request_id:{},required_specs:{}",
        data.vehicles[0].assignments[0].events[0].assignment,
        data.vehicles[0].assignments[0].events[0].communicated_time,
        data.vehicles[0].assignments[0].events[0].scheduled_time,
        data.vehicles[0].assignments[0].events[0].coordinates.x(),
        data.vehicles[0].assignments[0].events[0].coordinates.y(),
        data.vehicles[0].assignments[0].events[0].company,
        data.vehicles[0].assignments[0].events[0].id,
        data.vehicles[0].assignments[0].events[0].customer,
        data.vehicles[0].assignments[0].events[0].is_pickup,
        data.vehicles[0].assignments[0].events[0].request_id,
        data.vehicles[0].assignments[0].events[0].required_specs,
    );

    println!("for read data: ");

    println!(
        "number of assignments for vehicle 1: {} and number of the first assignments events: {}, departure: {}, arrival: {}, company: {}, vehicle: {}, id: {}",
        read_from_db_data.vehicles[0].assignments.len(),
        read_from_db_data.vehicles[0].assignments[0].events.len(),
        read_from_db_data.vehicles[0].assignments[0].departure,
        read_from_db_data.vehicles[0].assignments[0].arrival,
        read_from_db_data.vehicles[0].assignments[0].company,
        read_from_db_data.vehicles[0].assignments[0].vehicle,
        read_from_db_data.vehicles[0].assignments[0].id
    );
    println!(
        "event1: assginment:{},communicated_time:{},scheduled_time:{},x:{},y:{},company:{},id:{},customer:{},is_pickup:{},request_id:{},required_specs:{}",
        read_from_db_data.vehicles[0].assignments[0].events[0].assignment,
        read_from_db_data.vehicles[0].assignments[0].events[0].communicated_time,
        read_from_db_data.vehicles[0].assignments[0].events[0].scheduled_time,
        read_from_db_data.vehicles[0].assignments[0].events[0].coordinates.x(),
        read_from_db_data.vehicles[0].assignments[0].events[0].coordinates.y(),
        read_from_db_data.vehicles[0].assignments[0].events[0].company,
        read_from_db_data.vehicles[0].assignments[0].events[0].id,
        read_from_db_data.vehicles[0].assignments[0].events[0].customer,
        read_from_db_data.vehicles[0].assignments[0].events[0].is_pickup,
        read_from_db_data.vehicles[0].assignments[0].events[0].request_id,
        read_from_db_data.vehicles[0].assignments[0].events[0].required_specs,
    );

    data.create_availability(
        State(s.clone()),
        NaiveDate::from_ymd_opt(2024, 4, 15)
            .unwrap()
            .and_hms_opt(10, 10, 0)
            .unwrap(),
        NaiveDate::from_ymd_opt(2024, 4, 15)
            .unwrap()
            .and_hms_opt(14, 0, 0)
            .unwrap(),
        1,
    )
    .await;

    data.create_availability(
        State(s.clone()),
        NaiveDate::from_ymd_opt(2024, 4, 15)
            .unwrap()
            .and_hms_opt(10, 10, 0)
            .unwrap(),
        NaiveDate::from_ymd_opt(2024, 4, 15)
            .unwrap()
            .and_hms_opt(14, 0, 0)
            .unwrap(),
        2,
    )
    .await;

    data.create_availability(
        State(s.clone()),
        NaiveDate::from_ymd_opt(2024, 4, 15)
            .unwrap()
            .and_hms_opt(10, 10, 0)
            .unwrap(),
        NaiveDate::from_ymd_opt(2024, 4, 15)
            .unwrap()
            .and_hms_opt(14, 0, 0)
            .unwrap(),
        3,
    )
    .await;

    read_from_db_data.clear();
    read_from_db_data.read_data(State(s.clone())).await;
    println!(
        "=_=_=__=__=_=_=_=_=_==_=_=_==_=====_=_=_=_=_==___________________________________________________________________________________________________is data synchronized after creating availabilites: {}",
        read_from_db_data == data
    );

    println!("event ids of user with id 1:");
    for ev in data.get_events_for_user(1, None, None).await.iter() {
        println!("  event id: {}", ev.id);
    }

    println!("event ids of user with id 2:");
    for ev in data.get_events_for_user(2, None, None).await.iter() {
        println!("  event id: {}", ev.id);
    }

    println!("event ids of user with id 3:");
    for ev in data.get_events_for_user(3, None, None).await.iter() {
        println!("  event id: {}", ev.id);
    }

    for (v, assignments) in data.get_company_conflicts_for_assignment(1, 1).await.iter() {
        println!(
            "assignment id conflicts for company 1 and assignment 1 and vehicle {}",
            v
        );
        for assignment in assignments.iter() {
            print!("{}", assignment.id);
        }
    }

    println!("handle routing request output:");
    data.handle_routing_request(
        State(s.clone()),
        NaiveDate::from_ymd_opt(2024, 4, 15)
            .unwrap()
            .and_hms_opt(10, 55, 0)
            .unwrap(),
        true,
        14.025081097762154,
        51.195075641827316,
        13.867512445295205,
        51.22069201951501,
        2,
        2,
    )
    .await;

    println!(
        "assignment count for vehicle 1 before change: {}",
        data.vehicles[0].assignments.len()
    );
    println!(
        "assignment count for vehicle 2 before change: {}",
        data.vehicles[1].assignments.len()
    );
    println!(
        "assignment1 vehicle: {}",
        data.vehicles[0].assignments[0].vehicle
    );
    data.change_vehicle_for_assignment(State(s.clone()), 1, 2)
        .await;
    println!(
        "assignment count for vehicle 1 after change: {}",
        data.vehicles[0].assignments.len()
    );
    println!(
        "assignment count for vehicle 2 after change: {}",
        data.vehicles[1].assignments.len()
    );
    println!(
        "assignment1 vehicle: {}",
        data.vehicles[1].assignments[0].vehicle
    );
}

fn print_vehicles_of_company(
    data: &Data,
    company_id: i32,
) {
    let vehicles_company = data.get_vehicles(company_id, None);

    println!("vehicles of company {}:", company_id);
    for (vs_id, vehicles) in vehicles_company.iter() {
        println!("vehicle specs id: {}", vs_id);
        for vehicle in vehicles.iter() {
            println!("  id: {}", vehicle.id);
        }
    }
}
