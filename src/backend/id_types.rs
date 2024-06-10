use core::hash::Hash;
use std::slice::Iter;

pub trait Id: Send + PartialEq + Eq + Hash {
    fn id(&self) -> i32;
    fn as_idx(&self) -> usize;
}

#[macro_export]
macro_rules! define_id {
    ($t:ident) => {
        #[derive(Debug, PartialEq, Eq, Clone, PartialOrd, Ord, Hash, Copy, Default)]
        pub struct $t {
            id: i32,
        }

        impl Id for $t {
            fn id(&self) -> i32 {
                self.id
            }

            fn as_idx(&self) -> usize {
                assert!(self.id > 0);
                (self.id() - 1) as usize
            }
        }

        impl $t {
            #[allow(dead_code)]
            pub fn new(id: i32) -> Self {
                Self { id }
            }
        }

        impl std::fmt::Display for $t {
            fn fmt(
                &self,
                f: &mut std::fmt::Formatter<'_>,
            ) -> std::fmt::Result {
                write!(f, "{}", self.id)
            }
        }

        impl PartialEq<i32> for $t {
            fn eq(
                &self,
                other: &i32,
            ) -> bool {
                self.id == *other
            }
        }
    };
}
define_id!(VehicleId);
define_id!(CompanyId);
define_id!(ZoneId);
define_id!(AddressId);
define_id!(UserId);
define_id!(TourId);
define_id!(EventId);
define_id!(AvailabilityId);

#[allow(dead_code)]
#[derive(Clone, PartialEq, Default)]
pub struct VecMap<K: Id, V> {
    vec: Vec<V>,
    id: K,
}

impl<K: Id + Default, V: Clone> VecMap<K, V> {
    pub fn new() -> Self {
        Self {
            vec: Vec::<V>::new(),
            id: K::default(),
        }
    }

    #[allow(dead_code)]
    pub fn get(
        &self,
        key: K,
    ) -> &V {
        &self.vec[key.as_idx()]
    }

    #[allow(dead_code)]
    pub fn get_mut(
        &mut self,
        key: K,
    ) -> &mut V {
        &mut self.vec[key.as_idx()]
    }

    pub fn set(
        &mut self,
        key: K,
        value: V,
    ) {
        self.vec[key.as_idx()] = value
    }

    pub fn iter(&self) -> Iter<V> {
        self.vec.iter()
    }

    pub fn push(
        &mut self,
        v: V,
    ) {
        self.vec.push(v);
    }

    pub fn resize(
        &mut self,
        new_size: usize,
        default_val: V,
    ) {
        self.vec.resize(new_size, default_val);
    }

    pub fn len(&self) -> usize {
        self.vec.len()
    }
}
