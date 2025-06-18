export async function up(db) {
    await db.schema
		.createTable('booking_api_parameters')
		.addColumn('id', 'serial', (col) => col.primaryKey())
		.addColumn('start_lat1', 'real')
		.addColumn('start_lng1', 'real')
		.addColumn('target_lat1', 'real')
		.addColumn('target_lng1', 'real')
		.addColumn('start_time1', 'bigint')
		.addColumn('target_time1', 'bigint')
		.addColumn('start_address1', 'varchar')
		.addColumn('target_address1', 'varchar')
		.addColumn('start_fixed1', 'boolean')
		.addColumn('start_lat2', 'real')
		.addColumn('start_lng2', 'real')
		.addColumn('target_lat2', 'real')
		.addColumn('target_lng2', 'real')
		.addColumn('start_time2', 'bigint')
		.addColumn('target_time2', 'bigint')
		.addColumn('start_address2', 'varchar')
		.addColumn('target_address2', 'varchar')
		.addColumn('start_fixed2', 'boolean')
        .addColumn('kids_zero_to_two', 'integer')
        .addColumn('kids_three_to_four', 'integer')
        .addColumn('kids_five_to_six', 'integer')
        .addColumn('passengers', 'integer')
        .addColumn('wheelchairs', 'integer')
        .addColumn('bikes', 'integer')
        .addColumn('luggage', 'integer')
		.execute();
}

export async function down() {}