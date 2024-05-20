use super::{
    id_types::{CompanyIdT, TourIdT, VehicleIdT},
    lib::{PrimaEvent, PrimaTour},
};
use crate::backend::{data::Data, id_types::IdT, interval::Interval, lib::PrimaData};
use chrono::{Days, Duration, NaiveDate, NaiveDateTime, NaiveTime};
use hyper::StatusCode;

/* Event Data hat Tour id
 * TourData hat Event Vector
 * mit & arbeiten statt mit clone!
 *
 * Alles in einer Funktion ? Brauche ich da red_data überhaupt?
 *
 * may_vehicle_operate_during funktion die evtl. nützlich ist
 */

struct Intervals {
    start_time: NaiveDateTime,
    duration: Duration,
    vehicle_idx: VehicleIdT,
}

//#[derive(Default)]
/*struct RedistibutionData<'a> {
    events_to_redistribute: Vec<Box<&'a dyn PrimaEvent>>,
    company_id: CompanyIdT,
    tours_to_redistribute: Vec<Box<&'a dyn PrimaTour>>,
    blocking_events: Vec<Box<&'a dyn PrimaEvent>>,
    self_blocking_events: Vec<Box<&'a dyn PrimaEvent>>,
}*/

/*struct Timetable<'a> {
    pickup_event: &'a dyn PrimaEvent,
    dropoff_event: &'a dyn PrimaEvent,
    pickup_time: NaiveDateTime,
    dropoff_time: NaiveDateTime,
    tour_id: TourIdT,
}*/

// 1656
pub async fn trigger_redistribution(
    vehicle_id: VehicleIdT,
    start: NaiveDateTime,
    end: NaiveDateTime,
    data: &Data,
) -> Option<StatusCode> {
    //rückgabetyp dann Result<Tour, StatusCode>
    //let mut red_data = RedistibutionData::default();
    //let zero_date = NaiveDate::from_ymd_opt(1, 1, 1);
    //let zero_time = NaiveTime::from_hms_opt(0, 0, 0);
    let red_dur = end - start;

    println!("<<--in trigger redistribution-->>");
    println!(
        "Interval: starttime: {}, endtime: {} Duration (timeframe): {:?}",
        start, end, red_dur
    );

    // Wenn die Tour angekratzt nicht gemacht werden kann, dann komplett umverteilen!
    // => sollte schon drin sein, in get tours mit overlaps.

    //get tours of this vehicle -> we want to redistibute those
    let tours_or_not = data.get_tours(vehicle_id, start, end).await;
    let tours_to_redistribute = match tours_or_not {
        Ok(tours_or_not) => tours_or_not,
        Err(e) => {
            return Some(e);
        }
    };
    // one day interval
    let start_all = start.checked_sub_days(Days::new(1)).unwrap();
    let end_all = end.checked_add_days(Days::new(1)).unwrap();
    println!(
        "New Interval: starttime all: {}, endtime all: {} ",
        start_all, end_all
    );
    // get self blocking tours in a one day range
    /*let all_tours_or_not = data.get_tours(vehicle_id, start_all, end_all).await;
    let all_other_tours = match all_tours_or_not {
        Ok(all_tours_or_not) => all_tours_or_not,
        Err(e) => {
            return Some(e);
        }
    };
    println!("LEN all other tours: {:?}", all_other_tours.len());
    let mut filtered_blocking_tours: Vec<Box<&dyn PrimaTour>> = Vec::new();
    for (i, tour) in all_other_tours.into_iter().enumerate() {
        let red_tour = match tours_to_redistribute.get(i) {
            Some(event) => event,
            None => {
                println!("in none -> continue");
                continue;
            }
        };
        if tour.get_id().await != red_tour.get_id().await {
            println!("in if selfblocking write...");
            filtered_blocking_tours.push(tour);
        }
        println!("i: {}", i);
    }
    println!(
        "LEN blocking tours: {:?}, len tours to red {:?}",
        filtered_blocking_tours.len(),
        tours_to_redistribute.len(),
    );*/
    // get vehicle and company infos
    let vehicle_or_not = Data::get_vehicle(data, vehicle_id).await;
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
    };
    // create timetable for redistribution
    let mut company_timetable: Vec<Vec<Intervals>> = Vec::new();
    //if all_vehicles.len() > 1 {
    println!("in if all vehicles > 1 len: {:?}", all_vehicles.len());
    for v in all_vehicles.iter() {
        let mut vehicle_timetable: Vec<Intervals> = Vec::new();
        let v_id = *(*v).get_id().await;
        //if v_id == vehicle_id {
        //    continue;
        //}
        let this_vehicle_tours_or_not = data.get_tours(v_id, start_all, end_all).await;
        let this_vehicle_tours = match this_vehicle_tours_or_not {
            Ok(this_vehicle_tours_or_not) => this_vehicle_tours_or_not,
            Err(e) => {
                return Some(e);
            }
        };
        for tour in this_vehicle_tours.iter() {
            let arr = tour.get_arr().await;
            let dep = tour.get_dep().await;
            let dur = arr - dep;
            let interval = Intervals {
                start_time: dep,
                duration: dur,
                vehicle_idx: v_id,
            };
            vehicle_timetable.push(interval);
        }
        //filtered_blocking_tours.append(&mut this_vehicle_tours);
        company_timetable.push(vehicle_timetable);
    }
    //}

    // -------- Events ----------------------------------------------------------------------------------------------------- !!
    //println!("LÄNGE! len{:?}", red_data.tours_to_redistribute.len());
    /*let mut first_start: Vec<NaiveDateTime> = Vec::new();
        let mut last_end: Vec<NaiveDateTime> = Vec::new();
        for t in red_data.tours_to_redistribute.iter() {
            let mut eves = (*t).get_events().await;
            first_start.push(eves.first().unwrap().get_scheduled_time().await); // erstes event der tour startzeit
            last_end.push(eves.last().unwrap().get_scheduled_time().await); // letztes event der tour endzeit
                                                                            //println!("  eves länge in for: {:?}", eves.len());
            red_data.events_to_redistribute.append(&mut eves);
        }
        // 1105
        /*println!(
            "  first start: len {:?}; elem 0 {:?}",
            first_start.len(),
            first_start.get(0)
        );
        // 1145
        println!(
            "  last end: len {:?}; elem 0 {:?}",
            last_end.len(),
            last_end.get(0)
        );*/
        // blocking events_for_vehicle are all events the vehicle has, in a 1 Day range
        let events_or_not = Data::get_events_for_vehicle(data, vehicle_id, start_all, end_all).await;
        let blocking_events_for_vehicle = match events_or_not {
            Ok(events_or_not) => events_or_not,
            Err(e) => {
                return Some(e);
            }
        };
        /*println!(
            "HIER! len blocking evenets: {:?}",
            blocking_events_for_vehicle.len()
        );
        println!(
            "HIER! len events to red: {:?}",
            red_data.events_to_redistribute.len()
        );*/
        // filter out all events we want to redestibute, to have just the blocking events for this vehicle
        let mut filtered_blocking_events: Vec<Box<&dyn PrimaEvent>> = Vec::new();
        for (i, eve) in blocking_events_for_vehicle.into_iter().enumerate() {
            let adam = match red_data.events_to_redistribute.get(i) {
                Some(event) => event,
                None => {
                    //println!("in none -> continue");
                    continue;
                }
            };
            if eve.get_id().await != adam.get_id().await {
                //println!("in if selfblocking write...");
                filtered_blocking_events.push(eve);
            }
            //println!("i: {}", i);
        }

        red_data.self_blocking_events = filtered_blocking_events.clone();
        /*println!(
            "LÄNGE filtered_blocking_events: {:?}",
            filtered_blocking_events.len()
        );
        println!(
            "LÄNGE self_blocking_events: {:?}",
            red_data.self_blocking_events.len()
        );*/

        // get a vector of all blocking events of all vehicles of this company
        if all_vehicles.len() > 1 {
            //println!("in if all vehicles > 1 len: {:?}", all_vehicles.len());
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
    */
    /*println!(
        "LÄNGE blocking_events: {:?}",
        red_data.blocking_events.len()
    );*/
    // ----------------------------------- "self" redistibution -------------------------------------------------------------
    println!("<<--self red tours-->>");
    // Tour 0: dep: 1030, arr: 1050, sched_start: 1035, comm_start: 1032, sched_end: 1045. comm_end: 1048; VID: 1
    // Tour 1: dep: 1100, arr: 1150, sched_start: 1105, comm_start: 1110, sched_end: 1145. comm_end: 1148; VID: 1
    // Tour 2: dep: 1030, arr: 1050, sched_start: 1035, comm_start: 1032, sched_end: 1045. comm_end: 1048; VID: 2
    // Alle selbe Company

    // Erstbeste Option:  anderes Fahrzeug, zur selben Zeit
    // Zweitbeste Option: selbes Fahrzeug (oder anderes Fahrzeug, selbe Company) andere Uhrzeit
    // Drittbeste Option: andere Company, selbe Zeit
    // Letzte Option:     andere Company, andere Zeit

    let mut red_depatures: Vec<NaiveDateTime> = Vec::new();
    let mut red_arrivals: Vec<NaiveDateTime> = Vec::new();
    let mut red_tour_durations: Vec<Duration> = Vec::new();
    for t in tours_to_redistribute.iter() {
        let dep = t.get_dep().await;
        red_depatures.push(dep);
        let arr = t.get_arr().await;
        red_arrivals.push(arr);
        let timewindow = arr - dep;
        red_tour_durations.push(timewindow);
    }
    // 1100 - 1150 => 50min = 3000 sec
    println!(
        "LÄNGE tour_durations: {:?} dur: {:?}",
        red_tour_durations.len(),
        red_tour_durations.get(0)
    );

    // Hier die for schleife machen, die auf Zettel ist mit i, i+1 (next)
    for v_tt in company_timetable.iter() {
        let mut v_tt_iter = v_tt.iter().peekable();
        // erstes elem im ersten durchlauf
        while v_tt_iter.peek().is_some() {
            // ebenfalls erstes elem, mit next aber iterator eins weiter
            let v_tours = v_tt_iter.next().unwrap();
            //let v_tours = match v_tt_iter.next() {
            //    Some() =>
            //    None => ,
            //}
            if vehicle_id != v_tours.vehicle_idx {
                if start == v_tours.start_time {
                    continue;
                }
                let current_interval =
                    Interval::new(v_tours.start_time, v_tours.start_time + v_tours.duration);
                if v_tt_iter.peek().is_some() {
                    let v_tours_next = *v_tt_iter.peek().unwrap();
                    if !(current_interval.contains_point(&start)) && end > v_tours_next.start_time {
                        //leeres Feld, passt rein
                    }
                } else {
                    // ToDo: wenn das aktuelle elem das letzte elem ist
                    // hinten dran hängen mit availability-check?
                }
            }
        }
    }
    // TODO
    // Wichitg: Tests mit mehr touren füllen, sonst habe ich nichts zum vergleichen
    // nochmal schauen, dass die tests auch mit wenig touren laufen!

    /* Algo:
     *  check if other vehicle of same company at same time is available (and has same dependencies) -> yes: finished
     *  no -> loop through all vehicles of same company and see if there is a timeslot available (with same dependencies) -> yes: finished
     *  no -> loop through all vehicles of all other comapny at same time see if available (and has same dependencies) -> yes: finished
     *  no -> loop through again, and find free timeslot (with same dependencies)
     *  Rückgabe ist suggestion new tour-zuordnung
     */

    /*let mut tt: Vec<Timetable> = Vec::new();
    let mut pu_e = *(*red_data.self_blocking_events.first().unwrap());
    let mut do_e = *(*red_data.self_blocking_events.first().unwrap());
    let mut pu_t = NaiveDateTime::new(zero_date.unwrap(), zero_time.unwrap());
    let mut do_t = NaiveDateTime::new(zero_date.unwrap(), zero_time.unwrap());
    let mut tour_id = TourIdT::new(0);
    for (i, eve) in red_data.self_blocking_events.iter().enumerate() {
        //println!("in self blocking for-Schleife i: {:?}", i);
        tour_id = (*eve).get_tour_id().await;
        if i % 2 == 0 {
            if (*eve).get_is_pickup().await {
                pu_e = *(*eve);
                pu_t = eve.get_scheduled_time().await;
            } else {
                do_e = *(*eve);
                do_t = eve.get_scheduled_time().await;
            }
        } else {
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
    //println!("LÄNGE tt: {:?}", tt.len(),);
    */

    // -- redistribution --
    // TODO: rückgabe ist redistribution Vorschlag!
    // TODO: get all vehicles of all COMPANIES, if we have to redistribute to another company
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
        // dep: 1030 arr: 1050
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
