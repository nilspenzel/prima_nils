use sea_orm_migration::prelude::*;

#[derive(DeriveMigrationName)]
pub struct Migration;

#[async_trait::async_trait]
impl MigrationTrait for Migration {
    async fn up(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        manager
        .alter_table(
            Table::alter()
                .table(Event::Table)
                .add_column(
                    ColumnDef::new(Event::Passengers)
                        .integer()
                        .not_null(),
                )
                .add_column(ColumnDef::new(Event::Wheelchair).boolean().not_null(),)
                .add_column(
                    ColumnDef::new(Event::Baggage)
                        .integer()
                        .not_null(),
                )
                .add_column(
                    ColumnDef::new(Event::ConnectsPublicTransport)
                        .integer()
                        .not_null(),
                )
                .to_owned(),
            )
        .await?;

        manager
            .create_table(
                Table::create()
                    .table(BlockedTimes::Table)
                    .if_not_exists()
                    .col(ColumnDef::new(BlockedTimes::Id)
                        .integer()
                        .not_null()
                        .auto_increment()
                        .primary_key(),
                    )
                    .col(ColumnDef::new(BlockedTimes::StartTime)
                        .date_time().not_null(),
                    )
                    .col(ColumnDef::new(BlockedTimes::EndTime)
                        .date_time().not_null(),
                    )
                    .col(ColumnDef::new(BlockedTimes::Vehicle)
                        .integer().not_null(),
                    )
                    .foreign_key(
                        ForeignKey::create()
                        .name("fk-blocked_times-vehicle_id")
                        .from(BlockedTimes::Table, BlockedTimes::Vehicle)
                        .to(Vehicle::Table, Vehicle::Id),
                    )
                    .to_owned()
            )
            .await?;

        manager
            .create_table(
                Table::create()
                    .table(Company::Table)
                    .if_not_exists()
                    .col(ColumnDef::new(Company::Id)
                        .integer()
                        .not_null()
                        .auto_increment()
                        .primary_key(),
                    )
                    .col(ColumnDef::new(Company::Name)
                        .string().not_null(),
                    )
                    .col(ColumnDef::new(Company::ZoneId)
                        .integer().not_null(),
                    )
                    .col(ColumnDef::new(Company::CentralLatitude)
                        .float().not_null(),
                    )
                    .col(ColumnDef::new(Company::CentralLongitude)
                        .float().not_null(),
                    )
                    .foreign_key(
                        ForeignKey::create()
                            .name("fk-company-zone_id")
                            .from(Company::Table, Company::ZoneId)
                            .to(Zone::Table, Zone::Id),
                    )
                    .to_owned(),
            )
            .await?;

        manager
            .alter_table(
                Table::alter()
                    .table(Vehicle::Table)
                    .add_column(
                        ColumnDef::new(Vehicle::StorageSpace)
                            .integer()
                            .not_null()
                    )
                    .add_column(
                        ColumnDef::new(Vehicle::CompanyId)
                        .integer()
                        .not_null()
                    )
                    .to_owned(),
            )
            .await?;

        let foreign_key_char = TableForeignKey::new()
            .name("fk_vehicle_company_id")
            .from_tbl(Vehicle::Table)
            .from_col(Vehicle::CompanyId)
            .to_tbl(Company::Table)
            .to_col(Company::Id)
            .to_owned();

        manager
            .alter_table(
                Table::alter()
                .table(Vehicle::Table)
                .add_foreign_key(&foreign_key_char)
                .to_owned(),
            )
            .await?;

        Ok(())
    }

    async fn down(&self, manager: &SchemaManager) -> Result<(), DbErr> {

        manager
            .drop_foreign_key(
                sea_query::ForeignKey::drop()
                .name("fk_vehicle_company_id")
                .table(Vehicle::Table)
                .to_owned(),
            )
            .await?;

        manager
            .alter_table(Table::alter()
                .drop_column(Event::Passengers)
                .drop_column(Event::Wheelchair)
                .drop_column(Event::Baggage)
                .drop_column(Event::ConnectsPublicTransport)
                .to_owned()
            )
            .await?;
        manager
            .drop_table(
                Table::drop().table(Company::Table).to_owned()
            )
            .await?;
        manager
            .alter_table(Table::alter()
                .drop_column(Vehicle::StorageSpace)
                .drop_column(Vehicle::CompanyId)
                .to_owned()
            )
            .await?;

        manager
            .drop_table(
                Table::drop().table(BlockedTimes::Table).to_owned()
            )
            .await?;
    
        Ok(())
    }
}

#[derive(DeriveIden)]
enum Event {
    Table,
    Passengers,
    Wheelchair,
    Baggage,
    ConnectsPublicTransport,
}

#[derive(DeriveIden)]
enum Company {
    Table,
    Id,
    ZoneId,
    Name,
    CentralLatitude,
    CentralLongitude,
}

#[derive(DeriveIden)]
enum Vehicle {
    Table,
    Id,
    StorageSpace,
    CompanyId,
}

#[derive(DeriveIden)]
enum Zone {
    Table,
    Id,
}

#[derive(DeriveIden)]
enum BlockedTimes {
    Table,
    Id,
    StartTime,
    EndTime,
    Vehicle,
}