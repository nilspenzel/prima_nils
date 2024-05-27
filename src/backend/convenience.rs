use super::{id_types::VehicleIdT, lib::PrimaTour};
use crate::backend::data::Data;
use chrono::{Duration, NaiveDateTime};
use hyper::StatusCode;

/*
 * mit & arbeiten statt mit clone!
 * change_vehicle_for_tour aufrufen
 * may_vehicle_operate_during funktion die evtl. nützlich ist
 */

struct Intervals {
    start_time: NaiveDateTime,
    duration: Duration,
    vehicle_idx: VehicleIdT,
}

// Fehler wegen zweimal mut ref: Ich denke es liegt evtl daran, dass data get tours &self erwartet
// und change vehicle natürlich &mut self. Deswegen brauche ich theoretisch zwei refs und das geht nicht
// so wie ich es versucht habe zu umgehen, mit zweimal dieselbe Variable zu verwenden,
// verstehe ich nicht warum das nicht geht????

pub async fn trigger_redistribution(
    from_vehicle_id: VehicleIdT,
    start: NaiveDateTime,
    end: NaiveDateTime,
    data: &mut Data,
) -> Result<Vec<Box<&dyn PrimaTour>>, StatusCode> {
    let red_dur = end - start;

    println!("<<--in trigger redistribution-->>");
    println!(
        "Interval: starttime: {}, endtime: {} Duration (timeframe): {:?}",
        start, end, red_dur
    );
    //get tours of this vehicle -> we want to redistibute those
    let tours_or_not =
        crate::backend::lib::PrimaData::get_tours(data, from_vehicle_id, start, end).await;
    let tours_to_redistribute = match tours_or_not {
        Ok(tours_or_not) => tours_or_not,
        Err(e) => {
            return Err(e);
        }
    };
    // get vehicle and company infos
    /*let vehicle_or_not = Data::get_vehicle(data, from_vehicle_id).await;
    let vehicle = match vehicle_or_not {
        Ok(vehicle_or_not) => vehicle_or_not,
        Err(e) => {
            return Some(e);
        }
    };
    let company_id = *(*vehicle).get_company_id().await;
    let all_vehicles_or_none = Data::get_vehicles(data, company_id).await;
    let all_vehicles = match all_vehicles_or_none {
        Ok(all_vehicles_or_none) => all_vehicles_or_none,
        Err(e) => {
            return Some(e);
        }
    };*/
    return Ok(tours_to_redistribute);
}
// ----------------------------------- redistibution -------------------------------------------------------------
// Tour 0: dep: 1030, arr: 1050, sched_start: 1035, comm_start: 1032, sched_end: 1045. comm_end: 1048; VID: 1
// Tour 1: dep: 1100, arr: 1150, sched_start: 1105, comm_start: 1110, sched_end: 1145. comm_end: 1148; VID: 1
// Tour 2: dep: 1030, arr: 1050, sched_start: 1035, comm_start: 1032, sched_end: 1045. comm_end: 1048; VID: 2
// Alle selbe Company

async fn redistribute(
    to_vehicle_id: VehicleIdT,
    tours: Vec<Box<&dyn PrimaTour>>,
    data: &mut Data,
) -> StatusCode {
    let mut return_value = StatusCode::OK;
    for t in tours.iter() {
        let t_id = (*t).get_id().await;
        let status =
            crate::backend::lib::PrimaData::change_vehicle_for_tour(data, t_id, to_vehicle_id)
                .await;
        if status != StatusCode::OK {
            return_value = StatusCode::NOT_ACCEPTABLE;
        }
        if status == StatusCode::INTERNAL_SERVER_ERROR {
            return_value = StatusCode::INTERNAL_SERVER_ERROR;
        }
    }
    println!("<<--Ende: Trigger Red-->>");
    return return_value;
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
        let mut d = init::init(&db_conn, true, 2025, InitType::Convenience).await;
        let d_mut_ref = &mut d;
        // self blocking
        // ids: tour 1; vehicle 1
        // dep: 1030 arr: 1050
        // scheduled time: 1035
        // passengers 3, wheelchair, luggage

        // to red
        // ids: tour 2; vehicle 1
        // dep: 1100 arr: 1150
        // scheduled time: 1105
        // passengers 3, wheelchair, luggage

        /*let v_or_not = d.get_vehicle(VehicleIdT::new(1)).await;
        let v = match v_or_not {
            Ok(v_or_not) => v_or_not,
            Err(e) => {
                panic!("Fail: {:?}", e);
            }
        };
        let vid = v.get_id().await;
        println!("VID: {:?} ", *vid);
        let mut trigger = Ok(v.get_tours().await);
        println!("!! tours len: {:?}", tours_or_not.len());
        */

        //let d_ref = &d;
        // 1100 bis 1200 redestibute => 1105 bis 1145 Tour
        let start_time = NaiveDate::from_ymd_opt(2025, 4, 19)
            .unwrap()
            .and_hms_opt(11, 0, 0)
            .unwrap();
        let end_time = NaiveDate::from_ymd_opt(2025, 4, 19)
            .unwrap()
            .and_hms_opt(12, 0, 0)
            .unwrap();
        let trigger = convenience::trigger_redistribution(
            VehicleIdT::new(1),
            start_time,
            end_time,
            d_mut_ref,
        )
        .await;

        //let d_mut_ref = &mut d;
        if trigger.is_ok() {
            convenience::redistribute(VehicleIdT::new(2), trigger.unwrap(), d_mut_ref).await;
        }
        println!("Test finished");
    }
}
