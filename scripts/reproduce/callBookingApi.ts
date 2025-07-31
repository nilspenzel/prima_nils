#!/usr/bin/env ts-node

import 'dotenv/config';
import { bookingApi } from '../../src/lib/server/booking/bookingApi';

const parameters = {
	capacities: {
		passengers: 2,
		bikes: 0,
		luggage: 0,
		wheelchairs: 0
	},
	connection1: {
		start: {
			lat: 51.53512200000001,
			lng: 14.529001,
			address: 'Schleife Busbahnhof'
		},
		target: {
			lat: 51.4008118,
			lng: 14.5844962,
			address: 'Friedensstraße 23'
		},
		startTime: 1754554860000,
		targetTime: 1754557200000,
		signature: 'aecb2c759dd8a78b99f9c180e746e3404cc2a6cadbd8680b4bc7d5944b8a886c',
		startFixed: true,
		requestedTime: 1754555460000
	},
	connection2: null
};

const kidsThreeToFour = 0;
const kidsZeroToTwo = 0;
const kidsFiveToSix = 0;
const finalFlag = false;
async function main() {
	const response = await bookingApi(
		parameters,
		1,
		true,
		kidsThreeToFour,
		kidsFiveToSix,
		kidsZeroToTwo,
		finalFlag
	);

	if (response.status === 200) {
		console.log('Booking succeeded');
	}
}

main().catch((err) => {
	console.error('Error during booking:', err);
	process.exit(1);
});
