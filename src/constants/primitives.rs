// All prices are listed in cent.
pub const BEELINE_KMH: f64 = 100.0;
#[allow(dead_code)]
pub const KM_PRICE_TO_2_TARIFF_1: i32 = 350;
#[allow(dead_code)]
pub const KM_PRICE_TO_11_TARIFF_1: i32 = 210;
#[allow(dead_code)]
pub const KM_PRICE_FROM_11_TARIFF_1: i32 = 210;
#[allow(dead_code)]
pub const KM_PRICE_TO_2_TARIFF_2: i32 = 360;
#[allow(dead_code)]
pub const KM_PRICE_TO_11_TARIFF_2: i32 = 220;
#[allow(dead_code)]
pub const KM_PRICE_FROM_11_TARIFF_2: i32 = 220;

#[allow(dead_code)]
pub const WAITING_PRICE: i32 = 20; // per 28.8 seconds after the first 2 minutes

#[allow(dead_code)]
pub const BASE_PRICE_TARIFF_1: i64 = 450;
#[allow(dead_code)]
pub const BASE_PRICE_TARIFF_2: i64 = 550;

#[allow(dead_code)]
pub const APPROACH_PRICE_TO_10_KM: i32 = 1000;
#[allow(dead_code)]
pub const APPROACH_PRICE_FROM_10_KM: i32 = 1000;

#[allow(dead_code)]
pub const SURCHARGE_OVER_5_PASSENGERS: i32 = 900;

pub const PASSENGER_CHANGE_MINUTES: i64 = 2;

#[allow(dead_code)]
pub const FLAT_BUFFER_TIME: i32 = 5;

#[allow(dead_code)]
pub const BUFFER_TIME_PER_DIST: i32 = 1;

pub const MIN_PREP_MINUTES: i64 = 60;

#[allow(dead_code)]
pub static KM_PRICE: &[&[i32]] = &[
    &[
        KM_PRICE_TO_2_TARIFF_1,
        KM_PRICE_TO_11_TARIFF_1,
        KM_PRICE_FROM_11_TARIFF_1,
    ],
    &[
        KM_PRICE_TO_2_TARIFF_2,
        KM_PRICE_TO_11_TARIFF_2,
        KM_PRICE_FROM_11_TARIFF_2,
    ],
];

#[allow(dead_code)]
pub static RELATIVE_DISTANCE_BREAKPOINTS: &[i32] = &[2, 9, std::i32::MAX];
