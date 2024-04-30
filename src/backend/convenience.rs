use std::future::IntoFuture;

use super::{
    id_types::{CompanyIdT, VehicleIdT},
    lib::{PrimaEvent, PrimaTour},
};
use crate::backend::{data::Data, lib::PrimaData};
use chrono::{Days, Duration, NaiveDateTime};
use hyper::StatusCode;

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

// 1656
pub async fn trigger_redistribution(
    vehicle_id: VehicleIdT,
    start: NaiveDateTime,
    end: NaiveDateTime,
    data: &Data,
) -> StatusCode {
    let mut red_data = RedistibutionData::default();
    let timeframe = end - start;

    println!("in trigger redistribution");
    println!(
        "Interval: starttime: {}, endtime: {} Duration (timeframe): {:?}",
        start, end, timeframe
    );

    //get tours of this vehicle -> we want to redistibute those
    let tours_or_not = data.get_tours(vehicle_id, start, end).await;
    red_data.tours_to_redistribute = match tours_or_not {
        Ok(tours_or_not) => tours_or_not,
        Err(e) => {
            return e;
        }
    };
    // evtl noch unschön...
    let mut first_start: Vec<NaiveDateTime> = Vec::new();
    let mut last_end: Vec<NaiveDateTime> = Vec::new();
    for t in red_data.tours_to_redistribute.iter() {
        let mut eves = (*t).get_events().await;
        red_data.events_to_redistribute.append(&mut eves);
        first_start.push(eves.first().unwrap().get_scheduled_time().await);
        last_end.push(eves.last().unwrap().get_scheduled_time().await);
    }

    // blocking events_for_vehicle are all events the vehicle has, in a one Day range
    let start_all = start.checked_sub_days(Days::new(1)).unwrap();
    let end_all = end.checked_add_days(Days::new(1)).unwrap();
    println!(
        "New Interval: starttime all: {}, endtime all: {} ",
        start_all, end_all
    );
    let events_or_not = Data::get_events_for_vehicle(data, vehicle_id, start_all, end_all).await;
    let mut blocking_events_for_vehicle = match events_or_not {
        Ok(events_or_not) => events_or_not,
        Err(e) => {
            return e;
        }
    };
    // theoretisch sind hier jetzt auch die drin die redistibuted werden sollen, sortieren!
    // events_to_redistibute abgleichen mit blocking events for vehicle
    let filtered_blocking_events = blocking_events_for_vehicle
        .into_iter()
        .zip(red_data.events_to_redistribute.iter())
        .filter(|(eve, adam)| eve.get_id() != adam.get_id())
        .collect::<Vec<_>>();

    // vector wieder in zwei vectoren aufteilen, siehe beispiel!

    red_data.self_blocking_events = blocking_events_for_vehicle.clone(); // damit blocking_events_for_vehicle nicht zerstört wird? Richtig??

    // get a vector of all blocking events of all vehicles of this company
    let vehicle_or_not = Data::get_vehicle(data, vehicle_id).await;
    let vehicle = match vehicle_or_not {
        Ok(vehicle_or_not) => vehicle_or_not,
        Err(e) => {
            return e;
        }
    };
    red_data.company_id = *(*vehicle).get_company_id().await;
    let all_vehicles_or_none = Data::get_vehicles(data, red_data.company_id).await;
    let all_vehicles = match all_vehicles_or_none {
        Ok(all_vehicles_or_none) => all_vehicles_or_none,
        Err(e) => {
            return e;
        }
    };
    if all_vehicles.len() != 1 {
        for v in all_vehicles.iter() {
            let v_id = *(*v).get_id().await;
            let v_events_or_not =
                Data::get_events_for_vehicle(data, v_id, start_all, end_all).await;
            let mut vehicle_blocking_events = match v_events_or_not {
                Ok(v_events_or_not) => v_events_or_not,
                Err(e) => {
                    return e;
                }
            };
            blocking_events_for_vehicle.append(&mut vehicle_blocking_events);
        }
    }
    red_data.blocking_events = blocking_events_for_vehicle;
    // existiert blocking_events_for_vehicle noch?

    // --- self redistibution ---

    //das müsste jetzt die duration von der gesamten (ersten: index 0) tour sein. Um nachzuschauen, ob die gesamte tour
    //umgeplant werden kann.
    let mut tour_durations: Vec<Duration> = Vec::new();
    for (idx, dur) in first_start.iter().enumerate() {
        let timewindow = (*last_end.get(idx).unwrap()) - *dur;
        tour_durations.push(timewindow);
    }
    for (i, eve) in red_data.self_blocking_events.iter().enumerate() {
        let pickup = eve.get_scheduled_time().await;
        // Fragen über events
    }

    //TODO:Idee war, ein elem weiter schauen, bzw. immer zwei elems/schritte machen, da die eves zusammenhängen, start/ziel
    // Um dann die duration zu bekommen. Evtl geht's einfacher mit duration???? Nochmal Nils fragen, wie die Events sind

    println!("Ende: Trigger Red");
    return StatusCode::OK;
    //Ok(red_data)
}

#[cfg(test)]
mod red_test {
    use crate::backend::convenience;
    use crate::backend::id_types::{IdT, VehicleIdT};
    use crate::{
        //backend::data::Data,
        //constants::{geo_points::TestPoints, gorlitz::GORLITZ},
        dotenv,
        env,
        init::{self, InitType},
        Database,
        Migrator,
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
        let d = init::init(&db_conn, true, 5000, InitType::Convenience).await;

        let start_time = NaiveDate::from_ymd_opt(2024, 4, 19)
            .unwrap()
            .and_hms_opt(11, 0, 0)
            .unwrap();
        let end_time = NaiveDate::from_ymd_opt(2024, 4, 19)
            .unwrap()
            .and_hms_opt(12, 0, 0)
            .unwrap();
        //let my_vehicles = d.get_vehicles(0).await;
        convenience::trigger_redistribution(VehicleIdT::new(1), start_time, end_time, &d).await;
        println!("Test finished");
    }
}
