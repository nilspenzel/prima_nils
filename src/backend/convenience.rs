use super::data::EventData;
use crate::backend::data::AssignmentData;
use crate::backend::data::VehicleData;
use crate::backend::interval::Interval;
use std::collections::HashMap;

#[derive(Default)]
struct RedistibutionData {
    assignment_id_for_events: Vec<i32>,
    //all_assignments: HashMap<i32, AssignmentData>,
    //all_events: HashMap<i32, EventData>,
    events_to_redistribute: Vec<EventData>,
    company_id: i32,
    assignments_to_redistribute: Vec<AssignmentData>,
}

pub fn trigger_redistribution(
    vehicle_id: i32,
    time_interval: Interval,
    v_vd: &Vec<VehicleData>, // mit & arbeiten statt mit clone!
) -> () {
    println!("In trigger redistibution");
    println!("vehicle id is: {}", vehicle_id);
    println!("time interval {:?}", time_interval);
    let size = v_vd.iter().flat_map(|vehicle| &vehicle.assignments).count();
    println!("Size of assignments {}", size);
    let mut red = RedistibutionData::default();
    for vd in v_vd.iter() {
        if vehicle_id == vd.id {
            println!("found matching id!");
            red.company_id = vd.company;
            println!("company id: {}", red.company_id);
            for (_, ass) in vd.assignments.iter() {
                let dep = ass.departure;
                let arr = ass.arrival;
                let assignment_interval = Interval {
                    start_time: dep,
                    end_time: arr,
                };
                // TODO - Fälle in denen es nicht komplett "contains"... Deswegen Events?
                if time_interval.contains(&assignment_interval) {
                    red.assignments_to_redistribute.push(ass.clone());
                }
                red.assignment_id_for_events.push(ass.id.clone());
            }
        }
    }
}

/*#[cfg(test)]
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
}*/
