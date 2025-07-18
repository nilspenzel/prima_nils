#!/usr/bin/env ts-node

import 'dotenv/config';
import { bookingApi } from '../../src/lib/server/booking/bookingApi';

const parameters = {
  "capacities": {
    "passengers": 1,
    "bikes": 0,
    "luggage": 0,
    "wheelchairs": 0
  },
  "connection1": {
    "start": {
      "lat": 51.5302251,
      "lng": 14.5252029,
      "address": "START"
    },
    "target": {
      "lat": 51.5300072,
      "lng": 14.4892926,
      "address": "END"
    },
    "startTime": 1753077600000,
    "targetTime": 1753078680000,
    "signature": "62085305f0ac3bf274d43dc0e09c58fe21f3ea34f2126dfb420351709883a25e",
    "startFixed": true
  },
  "connection2": null
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
