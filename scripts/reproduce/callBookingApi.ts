#!/usr/bin/env ts-node

import 'dotenv/config';
import { bookingApi } from '../../src/lib/server/booking/bookingApi';

const parameters = {
	capacities: {
		passengers: 1,
		bikes: 0,
		luggage: 0,
		wheelchairs: 0
	},
	connection1: {
		start: {
			lat: 51.50595500000001,
			lng: 14.479306000000001,
			address: 'Mulkwitz Außenkippe'
		},
		target: {
			lat: 51.3280041,
			lng: 14.5841901,
			address: 'WSG 4km'
		},
		startTime: 1753929900000,
		targetTime: 1753932600000,
		signature: '8b81d5a6d4bed7e618f9260d296d65ce75cdeb4bec2ac8ae253aa37b42b92aee',
		startFixed: true,
		requestedTime: new Date('2025-07-31T02:49:00Z').getTime()
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
