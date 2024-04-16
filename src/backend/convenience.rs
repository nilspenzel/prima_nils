use super::data::{EventData, TourData, VehicleData};
use crate::backend::data;
use chrono::NaiveDateTime;
//use std::collections::HashMap;

/* EventData hat Tour id
 * TourData hat Event Vector
 * mit & arbeiten statt mit clone!
 */

#[derive(Default)]
struct RedistibutionData {
    tour_id_for_events: Vec<i32>,
    //all_assignments: HashMap<i32, AssignmentData>,
    //all_events: HashMap<i32, EventData>,
    events_to_redistribute: Vec<EventData>,
    company_id: i32,
    tours_to_redistribute: Vec<TourData>,
}

// 1656
pub fn trigger_redistribution(
    vehicle_id: i32,
    start: NaiveDateTime,
    end: NaiveDateTime,
) -> () {
    println!("in trigger redistribution");
    let v = vehicle_id + 1;
    println!("vehicle_id: {}, v: {} ", vehicle_id, v);
    println!("Interval: starttime: {}, endtime: {} ", start, end);
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
        let d = init::init(&db_conn, true, 5000, InitType::Default).await;
        let start_time = NaiveDate::from_ymd_opt(2024, 4, 15)
            .unwrap()
            .and_hms_opt(11, 0, 0)
            .unwrap();
        let end_time = NaiveDate::from_ymd_opt(2024, 4, 15)
            .unwrap()
            .and_hms_opt(12, 0, 0)
            .unwrap();
        let my_vehicles = d.get_vehicles(0).await;
        convenience::trigger_redistribution(5, start_time, end_time);
        println!("Test finished");
    }
}
