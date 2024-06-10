use crate::{
    backend::{id_types::CompanyId, interval::Interval, point::Point},
    constants::primitives::{BEELINE_KMH, WAITING_PRICE},
};
use chrono::{Duration, NaiveDate, Utc};

pub fn is_user_role_valid(
    is_driver: bool,
    is_disponent: bool,
    is_admin: bool,
    company_id: Option<CompanyId>,
) -> bool {
    // The user should have a company if and only if he is a disponent and/or driver.
    // Admins may not be drivers/disponents.
    // Customers are users which are none of driver, disponent, admin.
    match company_id {
        None => {
            if is_driver || is_disponent {
                return false;
            }
        }
        Some(_) => {
            if !is_driver && !is_disponent {
                return false;
            }
        }
    }
    if is_admin && (is_driver || is_disponent) {
        return false;
    }
    true
}

// Waiting price computation may differ for regions other than Bautzen.
#[allow(dead_code)]
pub fn minutes_to_waiting_price(minutes: i32) -> i32 {
    WAITING_PRICE * (((minutes * 60) as f32 / 28.8) as i32)
}

pub fn seconds_to_minutes(seconds: i32) -> i32 {
    assert!(seconds >= 0);
    seconds / 60
}

pub fn seconds_to_minutes_duration(seconds: f64) -> Duration {
    assert!(seconds >= 0.0);
    Duration::minutes(seconds_to_minutes(seconds as i32) as i64)
}

pub fn beeline_duration(
    p1: &Point,
    p2: &Point,
) -> Duration {
    Duration::minutes(hrs_to_minutes(
        meter_to_km_f(p1.geodesic_distance(p2)) / BEELINE_KMH,
    ))
}

pub fn meter_to_km_f(m: f64) -> f64 {
    assert!(m >= 0.0);
    m / 1000.0
}

fn hrs_to_minutes(h: f64) -> i64 {
    assert!(h >= 0.0);
    (h * 60.0) as i64
}

pub fn is_valid(interval: &Interval) -> bool {
    interval.start_time >= Utc::now().naive_utc() - Duration::minutes(15)
        && interval.end_time
            <= NaiveDate::from_ymd_opt(10000, 1, 1)
                .unwrap()
                .and_hms_opt(0, 0, 0)
                .unwrap()
}

#[cfg(test)]
mod test {
    use crate::{
        backend::{
            coord::Coord,
            helpers::{
                beeline_duration, hrs_to_minutes, meter_to_km_f, seconds_to_minutes,
                seconds_to_minutes_duration, Point,
            },
        },
        constants::geojson_strings::geo_points::TestPoints,
        osrm::{Dir::Forward, OSRM},
    };
    use chrono::Duration;
    use itertools::Itertools;

    async fn check_times_in_zone(
        v: &[Point],
        osrm: &OSRM,
    ) {
        for p in v.iter() {
            let osrm_result = osrm
                .one_to_many(
                    &Coord::from(*p),
                    &v.iter().map(|point| Coord::from(*point)).collect_vec(),
                    Forward,
                )
                .await;
            assert!(osrm_result.is_ok());
            for r in osrm_result.unwrap().iter() {
                assert!(seconds_to_minutes_duration(r.time) < Duration::hours(1));
            }
        }
    }

    #[test]
    fn test_helpers_hrs_to_minutes() {
        assert_eq!(hrs_to_minutes(100.0), 6000);
        assert_eq!(hrs_to_minutes(0.0), 0);
    }

    #[test]
    fn test_helpers_meter_to_km_f() {
        assert_eq!(meter_to_km_f(0.0), 0.0);
        assert_eq!(meter_to_km_f(1000.0), 1.0);
    }

    #[test]
    fn test_helpers_seconds_to_minutes_duration() {
        assert_eq!(seconds_to_minutes_duration(120.0), Duration::minutes(2));
        assert_eq!(seconds_to_minutes_duration(120.1), Duration::minutes(2));
        assert_eq!(seconds_to_minutes_duration(0.0), Duration::minutes(0));
    }

    #[test]
    fn test_helpers_seconds_to_minutes() {
        assert_eq!(seconds_to_minutes(60), 1);
        assert_eq!(seconds_to_minutes(119), 1);
        assert_eq!(seconds_to_minutes(0), 0);
    }

    #[tokio::test]
    async fn test_beeline_duration() {
        let mut test_points = TestPoints::new();
        let mut all_test_points = Vec::<Point>::new();
        all_test_points.append(&mut test_points.bautzen_ost);
        all_test_points.append(&mut test_points.bautzen_west);
        all_test_points.append(&mut test_points.gorlitz);
        //Check that all points in bautzen/görlitz areas are at most 1 hour apart according to the beeline distance function.
        for (p1, p2) in all_test_points
            .iter()
            .cartesian_product(all_test_points.iter())
        {
            assert!(beeline_duration(p1, p2) < Duration::hours(1));
        }
        //Check that beeline distances (as durations) to different points further away from the general bautzen/görtlitz area are reasonable.
        for p in all_test_points.iter() {
            // point in lisbon
            assert!(beeline_duration(p, &test_points.outside[0]) > Duration::hours(15));
            assert!(beeline_duration(p, &test_points.outside[0]) < Duration::days(3));
            // point in USA
            assert!(beeline_duration(p, &test_points.outside[1]) > Duration::days(3));
            assert!(beeline_duration(p, &test_points.outside[1]) < Duration::days(7));
            // point in Frankfurt
            assert!(beeline_duration(p, &test_points.outside[2]) > Duration::hours(3));
            assert!(beeline_duration(p, &test_points.outside[2]) < Duration::hours(10));
            // point in Görlitz (negative area of multipolygon)
            assert!(beeline_duration(p, &test_points.outside[3]) < Duration::hours(1));
        }
    }

    #[tokio::test]
    async fn osrm_reasonable_times_test() {
        let osrm = OSRM::new();
        let test_points = TestPoints::new();
        check_times_in_zone(&test_points.bautzen_ost, &osrm).await;
        check_times_in_zone(&test_points.bautzen_west, &osrm).await;
        check_times_in_zone(&test_points.gorlitz, &osrm).await;
    }
}
