use super::data::{EventData, TourData, VehicleData};
use crate::backend::{data::Data, lib::PrimaData};
use crate::error;
use chrono::NaiveDateTime;
use std::ops::Deref;
//use std::collections::HashMap;

/* EventData hat Tour id
 * TourData hat Event Vector
 * mit & arbeiten statt mit clone!
 */

#[derive(Default)]
struct RedistibutionData<'a> {
    tour_id_for_events: Vec<i32>,
    //all_events: HashMap<i32, EventData>,
    events_to_redistribute: Vec<EventData>,
    company_id: i32,
    tours_to_redistribute: Vec<&'a TourData>,
}

// 1656
pub async fn trigger_redistribution(
    vehicle_id: i32,
    start: NaiveDateTime,
    end: NaiveDateTime,
    data: &Data,
) -> () {
    let mut red_data = RedistibutionData::default();
    println!("in trigger redistribution");
    let v = vehicle_id + 1;
    println!("vehicle_id: {}, v: {} ", vehicle_id, v);
    println!("Interval: starttime: {}, endtime: {} ", start, end);
    let tours = data.get_tours(vehicle_id, start, end).await;
    match tours {
        Ok(tours) => {
            println!("in match ok");
            for t in tours.into_iter() {
                println!("in for");
                let tour_or_none = t.as_any().downcast_ref::<TourData>();
                let tour = match tour_or_none {
                    Some(tour) => red_data.tours_to_redistribute.push(tour),
                    None => (),
                };
            }
            println!("vec hat länge: {}", red_data.tours_to_redistribute.len());
            // Länge ist 0
        }
        Err(e) => {
            error!("{e:?}");
        }
    }
    println!("match tours fertig");
    println!("Ende");

    //data.get_vehicles();
}

#[cfg(test)]
mod red_test {
    use crate::backend::convenience;
    use crate::backend::lib::PrimaData;
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
        convenience::trigger_redistribution(1, start_time, end_time, &d).await;
        println!("Test finished");
    }
}
