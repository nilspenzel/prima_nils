use crate::{
    backend::{
        data::ActiveValue,
        data::Data,
        helpers::is_user_role_valid,
        id_types::UserId,
        id_types::{CompanyId, Id},
        lib::UserCrud,
        user::UserData,
    },
    entities::{prelude::User, user},
    error, StatusCode,
};
use async_trait::async_trait;
use sea_orm::EntityTrait;

#[async_trait]
impl UserCrud for Data {
    async fn create_user(
        &mut self,
        name: &str,
        is_driver: bool,
        is_disponent: bool,
        company: Option<CompanyId>,
        is_admin: bool,
        email: &str,
        password: Option<String>,
        salt: &str,
        o_auth_id: Option<String>,
        o_auth_provider: Option<String>,
    ) -> StatusCode {
        if self.users.values().any(|user| user.email == *email) {
            return StatusCode::CONFLICT;
        }
        if !is_user_role_valid(is_driver, is_disponent, is_admin, company) {
            return StatusCode::BAD_REQUEST;
        }
        match User::insert(user::ActiveModel {
            id: ActiveValue::NotSet,
            display_name: ActiveValue::Set(name.to_string()),
            is_driver: ActiveValue::Set(is_driver),
            is_admin: ActiveValue::Set(is_admin),
            email: ActiveValue::Set(email.to_string()),
            password: ActiveValue::Set(password.clone()),
            salt: ActiveValue::Set(salt.to_string()),
            o_auth_id: ActiveValue::Set(o_auth_id.clone()),
            o_auth_provider: ActiveValue::Set(o_auth_provider.clone()),
            company: ActiveValue::Set(company.map(|company_id| company_id.id())),
            is_active: ActiveValue::Set(true),
            is_disponent: ActiveValue::Set(is_disponent),
        })
        .exec(&self.db_connection)
        .await
        {
            Ok(result) => {
                let id = UserId::new(result.last_insert_id);
                self.users.insert(
                    id,
                    UserData::new(
                        id,
                        name,
                        is_driver,
                        is_disponent,
                        company,
                        is_admin,
                        email,
                        password,
                        salt,
                        o_auth_id,
                        o_auth_provider,
                    ),
                );
                StatusCode::CREATED
            }
            Err(e) => {
                error!("{e:}");
                StatusCode::INTERNAL_SERVER_ERROR
            }
        }
    }
}
