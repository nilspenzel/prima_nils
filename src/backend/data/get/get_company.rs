use crate::{
    backend::{
        data::Data,
        id_types::CompanyId,
        lib::{GetCompany, PrimaCompany},
    },
    StatusCode,
};
use async_trait::async_trait;

#[async_trait]
impl GetCompany for Data {
    async fn get_company(
        &self,
        company_id: CompanyId,
    ) -> Result<Box<&dyn PrimaCompany>, StatusCode> {
        Ok(Box::new(
            self.companies
                .iter()
                .find(|company| company.id == company_id)
                .unwrap() as &dyn PrimaCompany,
        ))
    }
}
