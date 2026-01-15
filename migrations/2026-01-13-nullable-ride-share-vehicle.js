export async function up(db) {
    await db.schema.alterTable('ride_share_tour')
        .alterColumn('vehicle', (col) => col.dropNotNull())
        .execute()
        
    await db.schema.alterTable('journey')
       .alterColumn('user', (col) => col.dropNotNull())
       .execute()
}

export async function down() { }
