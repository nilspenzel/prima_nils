#!/usr/bin/env ts-node

import 'dotenv/config';
import { bookingApi } from '../../src/lib/server/booking/taxi/bookingApi';

const parameters = {
	capacities: {
		passengers: 2,
		bikes: 0,
		luggage: 0,
		wheelchairs: 0
	},
	connection1: {
		start: {
			lat: 51.5446031,
			lng: 14.5355952,
			address: 'Schleife - Slepo'
		},
		target: {
			lat: 51.5162944,
			lng: 14.7396133,
			address: 'Skerbersdorfer Straße 14'
		},
		startTime: 1792905300000,
		targetTime: 1792906577501,
		signature: '2b9bbdb4af1f2800f5b3787c4688a7ec94e85e8dd52d18c17b96e1b66dbfaf6b',
		startFixed: true,
		requestedTime: 1792905300000,
		mode: 1
	},
	connection2: null
};

const kidsThreeToFour = 0;
const kidsZeroToTwo = 0;
const kidsFiveToSix = 0;
const kidsSevenToFourteen = 0;
const finalFlag = false;
async function main() {
	const response = await bookingApi(
		parameters,
		13,
		false,
		true,
		kidsThreeToFour,
		kidsFiveToSix,
		kidsZeroToTwo,
		kidsSevenToFourteen,
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
