import pg from 'pg';
import 'dotenv/config';

const { Client } = pg;

const isDocker = process.env.DOCKER_ENV === 'true';

const client = new Client({
	host: isDocker ? 'pg' : 'localhost',
	port: isDocker ? 5432 : 6500,
	user: 'postgres',
	password: 'pw',
	database: 'prima'
});

async function main() {
	try {
		await client.connect();
		await client.query(`CALL delete_unused_events()`);
	} catch (err) {
		console.error(err);
		process.exit(1);
	} finally {
		await client.end();
	}
}

main();
