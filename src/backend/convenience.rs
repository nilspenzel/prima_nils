use super::{
    id_types::{CompanyIdT, TourIdT, VehicleIdT},
    lib::{PrimaEvent, PrimaTour},
};
use crate::backend::{data::Data, id_types::IdT, lib::PrimaData};
use chrono::{Date, Days, Duration, NaiveDate, NaiveDateTime, NaiveTime};
use hyper::StatusCode;
use sea_orm::prelude::TimeTime;

/* Event Data hat Tour id
 * TourData hat Event Vector
 * mit & arbeiten statt mit clone!
 *
 * Alles in einer Funktion ? Brauche ich da red_data überhaupt?
 */

#[derive(Default)]
struct RedistibutionData<'a> {
    events_to_redistribute: Vec<Box<&'a dyn PrimaEvent>>,
    company_id: CompanyIdT,
    tours_to_redistribute: Vec<Box<&'a dyn PrimaTour>>,
    blocking_events: Vec<Box<&'a dyn PrimaEvent>>,
    self_blocking_events: Vec<Box<&'a dyn PrimaEvent>>,
}

struct Timetable<'a> {
    pickup_event: &'a dyn PrimaEvent,
    dropoff_event: &'a dyn PrimaEvent,
    pickup_time: NaiveDateTime,
    dropoff_time: NaiveDateTime,
    tour_id: TourIdT,
}

// 1656
pub async fn trigger_redistribution(
    vehicle_id: VehicleIdT,
    start: NaiveDateTime,
    end: NaiveDateTime,
    data: &Data,
) -> Option<StatusCode> {
    let mut red_data = RedistibutionData::default();
    let zero_date = NaiveDate::from_ymd_opt(1, 1, 1);
    let zero_time = NaiveTime::from_hms_opt(0, 0, 0);
    let timeframe = end - start;

    println!("<<--in trigger redistribution-->>");
    println!(
        "Interval: starttime: {}, endtime: {} Duration (timeframe): {:?}",
        start, end, timeframe
    );

    //get tours of this vehicle -> we want to redistibute those
    let tours_or_not = data.get_tours(vehicle_id, start, end).await;
    red_data.tours_to_redistribute = match tours_or_not {
        Ok(tours_or_not) => tours_or_not,
        Err(e) => {
            return Some(e);
        }
    };
    println!("LÄNGE! len{:?}", red_data.tours_to_redistribute.len());
    let mut first_start: Vec<NaiveDateTime> = Vec::new();
    let mut last_end: Vec<NaiveDateTime> = Vec::new();
    for t in red_data.tours_to_redistribute.iter() {
        let mut eves = (*t).get_events().await;
        first_start.push(eves.first().unwrap().get_scheduled_time().await); // erstes event der tour startzeit
        last_end.push(eves.last().unwrap().get_scheduled_time().await); // letztes event der tour endzeit
        println!("  eves länge in for: {:?}", eves.len());
        red_data.events_to_redistribute.append(&mut eves);
    }
    // 1105
    println!(
        "  first start: len {:?}; elem 0 {:?}",
        first_start.len(),
        first_start.get(0)
    );
    // 1145
    println!(
        "  last end: len {:?}; elem 0 {:?}",
        last_end.len(),
        last_end.get(0)
    );

    // blocking events_for_vehicle are all events the vehicle has, in a 1 Day range
    let start_all = start.checked_sub_days(Days::new(1)).unwrap();
    let end_all = end.checked_add_days(Days::new(1)).unwrap();
    println!(
        "New Interval: starttime all: {}, endtime all: {} ",
        start_all, end_all
    );
    let events_or_not = Data::get_events_for_vehicle(data, vehicle_id, start_all, end_all).await;
    let blocking_events_for_vehicle = match events_or_not {
        Ok(events_or_not) => events_or_not,
        Err(e) => {
            return Some(e);
        }
    };
    println!(
        "HIER! len blocking evenets: {:?}",
        blocking_events_for_vehicle.len()
    );
    println!(
        "HIER! len events to red: {:?}",
        red_data.events_to_redistribute.len()
    );
    // filter out all events we want to redestibute, to have just the blocking events for this vehicle
    let mut filtered_blocking_events: Vec<Box<&dyn PrimaEvent>> = Vec::new();
    for (i, eve) in blocking_events_for_vehicle.into_iter().enumerate() {
        let adam = match red_data.events_to_redistribute.get(i) {
            Some(event) => event,
            None => {
                println!("in none -> continue");
                continue;
            }
        };
        if eve.get_id().await != adam.get_id().await {
            println!("in if selfblocking write...");
            filtered_blocking_events.push(eve);
        }
        println!("i: {}", i);
    }

    red_data.self_blocking_events = filtered_blocking_events.clone();
    println!(
        "LÄNGE filtered_blocking_events: {:?}",
        filtered_blocking_events.len()
    );
    println!(
        "LÄNGE self_blocking_events: {:?}",
        red_data.self_blocking_events.len()
    );

    // get a vector of all blocking events of all vehicles of this company
    let vehicle_or_not = Data::get_vehicle(data, vehicle_id).await;
    let vehicle = match vehicle_or_not {
        Ok(vehicle_or_not) => vehicle_or_not,
        Err(e) => {
            return Some(e);
        }
    };
    red_data.company_id = *(*vehicle).get_company_id().await;
    let all_vehicles_or_none = Data::get_vehicles(data, red_data.company_id).await;
    let all_vehicles = match all_vehicles_or_none {
        Ok(all_vehicles_or_none) => all_vehicles_or_none,
        Err(e) => {
            return Some(e);
        }
    };
    if all_vehicles.len() > 1 {
        println!("in if all vehicles > 1 len: {:?}", all_vehicles.len());
        for v in all_vehicles.iter() {
            let v_id = *(*v).get_id().await;
            if v_id == vehicle_id {
                continue;
            }
            let v_events_or_not =
                Data::get_events_for_vehicle(data, v_id, start_all, end_all).await;
            let mut vehicle_blocking_events = match v_events_or_not {
                Ok(v_events_or_not) => v_events_or_not,
                Err(e) => {
                    return Some(e);
                }
            };
            filtered_blocking_events.append(&mut vehicle_blocking_events);
        }
    }
    red_data.blocking_events = filtered_blocking_events; //hier auch clone?

    println!(
        "LÄNGE blocking_events: {:?}",
        red_data.blocking_events.len()
    );

    // --- self redistibution ---
    println!("<<--self red-->>");
    // tour to red: 1200 - 1400
    // events: 0 = 1100 pickup
    // events: 1 = 1200 dropoff
    // events: 2 = 1300 pickup
    // events: 3 = 1400 dropoff
    // event is_pickup bool und tour id gleich

    //let mut not_available: Vec<>
    let mut tour_durations: Vec<Duration> = Vec::new();
    for (idx, dur) in first_start.iter().enumerate() {
        let timewindow = (*last_end.get(idx).unwrap()) - *dur;
        tour_durations.push(timewindow);
    }
    // 1105 - 1145 => 40min = 2400 sec
    println!(
        "LÄNGE tour_durations: {:?} dur: {:?}",
        tour_durations.len(),
        tour_durations.get(0)
    );
    let mut tt: Vec<Timetable> = Vec::new();
    let mut pu_e = *(*red_data.self_blocking_events.first().unwrap());
    let mut do_e = *(*red_data.self_blocking_events.first().unwrap());
    let mut pu_t = NaiveDateTime::new(zero_date.unwrap(), zero_time.unwrap());
    let mut do_t = NaiveDateTime::new(zero_date.unwrap(), zero_time.unwrap());
    let mut tour_id = TourIdT::new(0);
    for (i, eve) in red_data.self_blocking_events.iter().enumerate() {
        println!("in self blocking for-Schleife i: {:?}", i);
        if i % 2 == 0 {
            tour_id = (*eve).get_tour_id().await;
            if (*eve).get_is_pickup().await {
                pu_e = *(*eve);
                pu_t = eve.get_scheduled_time().await;
            } else {
                do_e = *(*eve);
                do_t = eve.get_scheduled_time().await;
            }
        } else {
            tour_id = (*eve).get_tour_id().await;
            if (*eve).get_is_pickup().await {
                pu_e = *(*eve);
                pu_t = eve.get_scheduled_time().await;
            } else {
                do_e = *(*eve);
                do_t = eve.get_scheduled_time().await;
            }
            let combine = Timetable {
                pickup_event: pu_e,
                dropoff_event: do_e,
                pickup_time: pu_t,
                dropoff_time: do_t,
                tour_id: tour_id,
            };
            tt.push(combine);
        }
    }

    // -- redistribution --
    println!("<<--Ende: Trigger Red-->>");
    return Some(StatusCode::OK);
}

#[cfg(test)]
mod red_test {
    use crate::backend::convenience;
    use crate::backend::id_types::{IdT, VehicleIdT};
    use crate::backend::lib::PrimaData;
    use crate::{
        dotenv, env,
        init::{self, InitType},
        Database, Migrator,
    };
    use chrono::NaiveDate;
    use migration::MigratorTrait;
    use sea_orm::DbConn;
    use serial_test::serial;

    async fn red_test_main() -> DbConn {
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
    async fn redistibution_test() {
        let db_conn = red_test_main().await;
        let d = init::init(&db_conn, true, 2025, InitType::Convenience).await;

        // self blocking
        // ids: tour 1; vehicle 1
        // dep: 19.04 1030 arr: 19.04 1050
        // scheduled time: 1035
        // passengers 3, wheelchair, luggage

        // to red
        // ids: tour 2; vehicle 1
        // dep: 1100 arr: 1150
        // scheduled time: 1105
        // passengers 3, wheelchair, luggage

        let v_or_not = d.get_vehicle(VehicleIdT::new(1)).await;
        let v = match v_or_not {
            Ok(v_or_not) => v_or_not,
            Err(e) => {
                panic!("Fail: {:?}", e);
            }
        };
        let vid = v.get_id().await;
        println!("VID: {:?} ", *vid);
        let tours_or_not = v.get_tours().await;
        println!("!! tours len: {:?}", tours_or_not.len());

        // 1100 bis 1200 redestibute => 1105 bis 1145 Tour
        let start_time = NaiveDate::from_ymd_opt(2025, 4, 19)
            .unwrap()
            .and_hms_opt(11, 0, 0)
            .unwrap();
        let end_time = NaiveDate::from_ymd_opt(2025, 4, 19)
            .unwrap()
            .and_hms_opt(12, 0, 0)
            .unwrap();
        convenience::trigger_redistribution(VehicleIdT::new(1), start_time, end_time, &d).await;
        println!("Test finished");
    }
}
