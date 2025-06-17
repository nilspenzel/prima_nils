#!/usr/bin/env ts-node

import 'dotenv/config';
import { cancelTour } from '../src/lib/server/cancelTour';

const parameters = {
	tourId: 196,
	company: 1
};

async function main() {
	await cancelTour(parameters.tourId, 'message', parameters.company);
}

main().catch((err) => {
	console.error('Error during tour cancellation:', err);
	process.exit(1);
});
