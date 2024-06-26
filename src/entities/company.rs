//! `SeaORM` Entity. Generated by sea-orm-codegen 0.12.14

use sea_orm::entity::prelude::*;

#[derive(Clone, Debug, PartialEq, DeriveEntityModel)]
#[sea_orm(table_name = "company")]
pub struct Model {
    #[sea_orm(primary_key)]
    pub id: i32,
    #[sea_orm(column_type = "Float")]
    pub latitude: f32,
    #[sea_orm(column_type = "Float")]
    pub longitude: f32,
    pub display_name: String,
    #[sea_orm(unique)]
    pub email: String,
    pub zone: i32,
    pub community_area: i32,
}

#[derive(Copy, Clone, Debug, EnumIter, DeriveRelation)]
pub enum Relation {
    #[sea_orm(has_many = "super::user::Entity")]
    User,
    #[sea_orm(has_many = "super::vehicle::Entity")]
    Vehicle,
    #[sea_orm(
        belongs_to = "super::zone::Entity",
        from = "Column::Zone",
        to = "super::zone::Column::Id",
        on_update = "NoAction",
        on_delete = "NoAction"
    )]
    Zone2,
    #[sea_orm(
        belongs_to = "super::zone::Entity",
        from = "Column::CommunityArea",
        to = "super::zone::Column::Id",
        on_update = "NoAction",
        on_delete = "NoAction"
    )]
    Zone1,
}

impl Related<super::user::Entity> for Entity {
    fn to() -> RelationDef {
        Relation::User.def()
    }
}

impl Related<super::vehicle::Entity> for Entity {
    fn to() -> RelationDef {
        Relation::Vehicle.def()
    }
}

impl ActiveModelBehavior for ActiveModel {}
