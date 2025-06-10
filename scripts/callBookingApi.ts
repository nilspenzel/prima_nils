#!/usr/bin/env ts-node

import 'dotenv/config';
import { bookingApi } from '../src/lib/server/booking/bookingApi';

const parameters = {
	connection1: {
		start: {
			lng: 14.6591644,
			lat: 51.5458871,
			address: 'Körnerplatz'
		},
		target: {
			lng: 14.5308026,
			lat: 51.5426918,
			address: 'Hoyerswerdaer Straße 37'
		},
		startTime: 1750103327193,
		targetTime: 1750105046238,
		signature: '',
		startFixed: false
	},
	connection2: null,
	capacities: {
		passengers: 2,
		bikes: 0,
		luggage: 0,
		wheelchairs: 0
	}
};

const companyId = 1;
const isFlagged = true;
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
