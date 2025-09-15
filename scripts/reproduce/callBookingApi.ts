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
      "lat": 51.5342296,
      "lng": 14.6941141,
      "address": "Krauschwitz / Baierweiche"
    },
    "target": {
      "lat": 51.538412,
      "lng": 14.5250691,
      "address": "Jahnring 21"
    },
    "startTime": 1758643800000,
    "targetTime": 1758645540000,
    "signature": "0374c014a5968bedddb3abb3ddb8ac33f39c87ff1649c9bd821d7571de4f4e88",
    "startFixed": true,
    "requestedTime": 1758643800000
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
		false,
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
