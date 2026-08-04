export async function up(db) {
	await db.schema
		.createTable('notification_outbox')
		.addColumn('id', 'serial', (col) => col.primaryKey())
		.addColumn('kind', 'varchar', (col) => col.notNull())
		.addColumn('payload', 'jsonb', (col) => col.notNull())
		.addColumn('deduplication_key', 'varchar', (col) => col.unique())
		.addColumn('created_at', 'bigint', (col) => col.notNull())
		.addColumn('available_at', 'bigint', (col) => col.notNull())
		.addColumn('processed_at', 'bigint')
		.addColumn('attempts', 'integer', (col) => col.notNull().defaultTo(0))
		.addColumn('last_error', 'text')
		.execute();

	await db.schema
		.createIndex('notification_outbox_pending_idx')
		.on('notification_outbox')
		.columns(['processed_at', 'available_at'])
		.execute();
}

export async function down(db) {
	await db.schema.dropTable('notification_outbox').execute();
}
