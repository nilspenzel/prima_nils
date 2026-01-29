import pg from 'pg';
import 'dotenv/config';

const { Client } = pg;

const day = 24 * 60 * 60 * 1000;
const week = 7 * day;
const args = process.argv.slice(2);
const typeArg = args.find((a) => a.startsWith('--type='));
const anonymizeAll = args.find((a) => a === '--all') !== undefined;

if (!typeArg) {
	console.error('Missing --type flag (rs | taxi)');
	process.exit(1);
}

const type = typeArg.split('=')[1];

const procedureMap = {
	rs: 'anonymize_rs',
	taxi: 'anonymize_taxi'
};

const procedure = procedureMap[type];

if (!procedure) {
	console.error(`Invalid --type value: ${type}`);
	process.exit(1);
}

function getTimestamp(monthOffset) {
	const yesterday = new Date();
	const year = yesterday.getFullYear();
	const month = yesterday.getMonth() + monthOffset;
	const date = new Date(year, month, 1, 0, 0, 0);
	return date.getTime();
}

const now = new Date(Date.now());
const midnight = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime();

const t1 = anonymizeAll ? 0 : type === 'rs' ? midnight - week * 3 : getTimestamp(-3);
const t2 = type === 'rs' ? t1 + 2 * week : getTimestamp(-1);

console.log({ t1: new Date(t1) }, { t2: new Date(t2) }, { midnight: new Date(midnight) });
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
		await client.query(`CALL ${procedure}($1, $2)`, [t1, t2]);

		console.log(
			`Anonymization (${type}) successful between ${new Date(t1).toISOString()} and ${new Date(t2).toISOString()}`
		);
	} catch (err) {
		console.error(`Failed anonymization (${type}):`, err);
		process.exit(1);
	} finally {
		await client.end();
	}
}

main();
