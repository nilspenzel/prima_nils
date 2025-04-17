
export async function up(db) {
    await db.schema.alterTable('vehicle')
    .addColumn('light_luggage', 'integer', (col) => col.notNull().defaultTo(0))
    .execute()

    await db.schema.alterTable('request')
    .addColumn('light_luggage', 'integer', (col) => col.notNull().defaultTo(0))
    .execute()
}