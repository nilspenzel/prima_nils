#!/usr/bin/env ts-node

import 'dotenv/config';
import { bookingApi } from '../src/lib/server/booking/bookingApi';

const parameters = {
	connection1: {
		start: {
			lng: 14.5316092,
			lat: 51.5393992,
			address: 'Strugaaue 2'
		},
		target: {
			lng: 14.6226502,
			lat: 51.5241162,
			address: 'Weißwasser/O.L.'
		},
		startTime: 1751353769004,
		targetTime: 1751354673335,
		signature: '',
		startFixed: false
	},
	connection2: null,
	capacities: {
		passengers: 1,
		bikes: 0,
		luggage: 0,
		wheelchairs: 0
	}
};

const kidsThreeToFour = 0;
const kidsZeroToTwo = 0;
const kidsFiveToSix = 0;
const finalFlag = true;
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
