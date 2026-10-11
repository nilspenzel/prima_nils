#!/usr/bin/env ts-node

import 'dotenv/config';
import { moveTour } from '../../src/lib/server/moveTour';

const parameters = {
	tourId: 42,
	vehicleId: 28,
	companyId: 14
};

async function main() {
	await moveTour(parameters.tourId, parameters.vehicleId, parameters.companyId);
}

main().catch((err) => {
	console.error('Error during tour cancellation:', err);
	process.exit(1);
});
