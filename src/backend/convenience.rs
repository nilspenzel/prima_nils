use std::ops::Deref;

use tower_http::follow_redirect::policy::PolicyExt;

use crate::backend::data;
use crate::backend::data::VehicleData;
use crate::backend::interval::Interval;

use crate::backend::data::AssignmentData;

fn trigger_redistribution(
    vehicle_id: i32,
    time_interval: Interval,
    v_vd: Vec<VehicleData>,
) -> () {
    println!("In trigger redistibution");
    println!("vehicle id is: {}", vehicle_id);
    println!("time interval {:?}", time_interval);
    let mut vd_id: VehicleData;
    for vd in v_vd.iter() {
        if vehicle_id == vd.id {
            println!("found matching id!");
            vd_id = vd.clone();
        }
    }
}

#[cfg(test)]
mod test {
    use crate::{
        backend::data::Data,
        constants::{geo_points::TestPoints, gorlitz::GORLITZ},
        dotenv, env,
        init::{self, StopFor::TEST1},
        AppState, Arc, Database, Migrator, Mutex, Tera,
    };
    use axum::extract::State;
    use chrono::NaiveDate;
    use migration::MigratorTrait;

    #[tokio::test]
    async fn test() {
        use crate::backend::convenience;
        use crate::backend::interval::Interval;
        dotenv().ok();
        let db_url = env::var("DATABASE_URL").expect("DATABASE_URL is not set in .env file");
        let conn = Database::connect(db_url)
            .await
            .expect("Database connection failed");
        Migrator::up(&conn, None).await.unwrap();

        let tera = match Tera::new(
            "html/**/
            *.html",
        ) {
            Ok(t) => Arc::new(Mutex::new(t)),
            Err(e) => {
                println!("Parsing error(s): {}", e);
                ::std::process::exit(1);
            }
        };
        let s = AppState {
            tera,
            db: Arc::new(conn),
        };

        let d = init::init(State(&s), true, TEST1).await;
        assert_eq!(d.vehicles.len(), 29);
        assert_eq!(d.zones.len(), 3);
        assert_eq!(d.companies.len(), 8);

        let i: Interval = Interval {
            start_time: NaiveDate::from_ymd_opt(2024, 4, 15)
                .unwrap()
                .and_hms_opt(11, 0, 0)
                .unwrap(),
            end_time: NaiveDate::from_ymd_opt(2024, 4, 15)
                .unwrap()
                .and_hms_opt(12, 0, 0)
                .unwrap(),
        };
        let my_vehicles = &d.vehicles;
        convenience::trigger_redistribution(5, i, my_vehicles.to_vec());
        println!("Test finished");
    }
}
