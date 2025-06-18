#!/usr/bin/env ts-node

import 'dotenv/config';
import { bookingApi } from '../src/lib/server/booking/bookingApi';

const parameters = {
	connection1: {
		start: {
			lng: 14.5364242,
			lat: 51.5338373,
			address: 'Schleifer Straße 5'
		},
		target: {
			lng: 14.4794545,
			lat: 51.3408297,
			address: 'Körnerplatz'
		},
		startTime: 1750494003957,
		targetTime: 1750495769548,
		signature: '',
		startFixed: true
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
