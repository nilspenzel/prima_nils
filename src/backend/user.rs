use crate::backend::{
    id_types::{CompanyId, UserId},
    lib::PrimaUser,
};
use async_trait::async_trait;

#[derive(PartialEq, Clone)]
#[readonly::make]
pub struct UserData {
    pub id: UserId,
    pub name: String,
    pub is_driver: bool,
    pub is_disponent: bool,
    pub company_id: Option<CompanyId>,
    pub is_admin: bool,
    pub email: String,
    pub password: Option<String>,
    pub salt: String,
    pub o_auth_id: Option<String>,
    pub o_auth_provider: Option<String>,
}

impl UserData {
    #[allow(clippy::too_many_arguments)]
    pub fn new(
        id: UserId,
        name: &str,
        is_driver: bool,
        is_disponent: bool,
        company_id: Option<CompanyId>,
        is_admin: bool,
        email: &str,
        password: Option<String>,
        salt: &str,
        o_auth_id: Option<String>,
        o_auth_provider: Option<String>,
    ) -> Self {
        Self {
            id,
            name: name.to_string(),
            is_driver,
            is_disponent,
            company_id,
            is_admin,
            email: email.to_string(),
            password,
            salt: salt.to_string(),
            o_auth_id,
            o_auth_provider,
        }
    }
}

#[async_trait]
impl PrimaUser for UserData {
    async fn get_id(&self) -> UserId {
        self.id
    }

    async fn get_name(&self) -> &str {
        &self.name
    }

    async fn is_driver(&self) -> bool {
        self.is_driver
    }

    async fn is_disponent(&self) -> bool {
        self.is_disponent
    }

    async fn is_admin(&self) -> bool {
        self.is_admin
    }

    async fn get_company_id(&self) -> &Option<CompanyId> {
        &self.company_id
    }

    async fn get_email(&self) -> &str {
        &self.email
    }
}
