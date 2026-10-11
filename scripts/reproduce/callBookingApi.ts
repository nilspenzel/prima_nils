#!/usr/bin/env ts-node

import 'dotenv/config';
import { bookingApi } from '../../src/lib/server/booking/taxi/bookingApi';

const parameters = {
  "capacities": {
    "passengers": 1,
    "bikes": 0,
    "luggage": 0,
    "wheelchairs": 0
  },
  "connection1": {
    "start": {
      "lat": 51.5405733,
      "lng": 14.520827,
      "address": "Thälmann-Siedlung 25"
    },
    "target": {
      "lat": 51.5342296,
      "lng": 14.6941141,
      "address": "Krauschwitz / Baierweiche"
    },
    "startTime": 1792381187000,
    "targetTime": 1792383034399,
    "signature": "36aa227802e5962ee7d07348e70b0563c06abcdac5d7f1a4a7ee630c95749ed7",
    "startFixed": false,
    "requestedTime": 1792383600000,
    "mode": 1
  },
  "connection2": null
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