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
			lat: 51.496103,
			lng: 14.7953534,
			address: 'START'
		},
		target: {
			lat: 51.5342031,
			lng: 14.5217853,
			address: 'END'
		},
		startTime: 1753937280000,
		targetTime: 1753939860000,
		signature: '530f72a2ff9bc4a0fe777e742f8b4502ea9da9ceedf699277b5ec3007ad386d4',
		startFixed: false
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
