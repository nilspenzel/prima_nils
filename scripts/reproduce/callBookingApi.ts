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
			lat: 51.5279047,
			lng: 14.5229428,
			address: 'Trebendorfer Weg 81'
		},
		target: {
			lat: 51.4486748,
			lng: 14.7390955,
			address: 'WSG 4km'
		},
		startTime: 1753754100000,
		targetTime: 1753757100000,
		signature: '7b710a95edb9ae791d82aca8971c5471f9c7ee23f3b29ff288a51752918cc578',
		startFixed: true,
		requestedTime: 0
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
