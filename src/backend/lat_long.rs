use core::cmp::Ordering;

#[macro_export]
macro_rules! define_lat_long {
    ($t:ident) => {
        #[derive(Default, PartialEq, Clone, Copy)]
        pub struct $t {
            value: f32,
        }

        impl std::fmt::Display for $t {
            fn fmt(
                &self,
                f: &mut std::fmt::Formatter<'_>,
            ) -> std::fmt::Result {
                write!(f, "{}", self.value)
            }
        }

        impl $t {
            pub fn new(v: f32) -> Self {
                Self { value: v }
            }

            pub fn from(v: f64) -> Self {
                Self { value: v as f32 }
            }

            pub fn v(&self) -> f32 {
                self.value
            }

            pub fn v64(&self) -> f64 {
                self.value as f64
            }
        }
    };
}
define_lat_long!(Latitude);
define_lat_long!(Longitude);

impl std::cmp::PartialEq<Longitude> for Latitude {
    fn eq(
        &self,
        other: &Longitude,
    ) -> bool {
        self.value == other.value
    }
}

impl std::cmp::PartialOrd<Longitude> for Latitude {
    fn partial_cmp(
        &self,
        other: &Longitude,
    ) -> Option<Ordering> {
        self.value.partial_cmp(&other.value)
    }
}

impl std::cmp::PartialEq<Latitude> for Longitude {
    fn eq(
        &self,
        other: &Latitude,
    ) -> bool {
        self.value == other.value
    }
}

impl std::cmp::PartialOrd<Latitude> for Longitude {
    fn partial_cmp(
        &self,
        other: &Latitude,
    ) -> Option<Ordering> {
        self.value.partial_cmp(&other.value)
    }
}

mod test {
    #[allow(unused_imports)]
    use crate::backend::lat_long::{Latitude, Longitude};

    #[test]
    fn test_lat_lng_cmp() {
        let lat = Latitude::new(1.0);
        let lng_eq = Longitude::new(1.0);
        let lng = Longitude::new(2.0);
        assert!(lat == lng_eq);
        assert!(lat != lng);

        assert!(lat <= lng_eq);
        assert!(lat >= lng_eq);
        assert!(!(lat < lng_eq));
        assert!(!(lat > lng_eq));

        assert!(lat < lng);
        assert!(lat <= lng);
        assert!(!(lng < lat));
        assert!(!(lng <= lat));
    }
}
