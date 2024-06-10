use super::id_types::AddressId;

#[derive(Debug, PartialEq, Clone, Default)]
pub struct AddressData {
    pub id: AddressId,
    pub address: String,
}

impl AddressData {
    #[allow(dead_code)]
    pub fn print(
        &self,
        indent: &str,
    ) {
        println!("{}id: {}, address: {}", indent, self.id, self.address);
    }
}
