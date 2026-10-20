#!/usr/bin/env ts-node

import 'dotenv/config';
import { bookingApi } from '../../src/lib/server/booking/taxi/bookingApi';

const parameters = {
  "capacities": {
    "passengers": 1,
    "bikes": 0,
    "luggage": 1,
    "wheelchairs": 0
  },
  "connection1": {
    "start": {
      "lat": 51.5003717,
      "lng": 14.8341397,
      "address": "Mosty (Wendisch Musta)"
    },
    "target": {
      "lat": 51.505444,
      "lng": 14.638026999999997,
      "address": "Weißwasser Bahnhof"
    },
    "startTime": 1792398819867,
    "targetTime": 1792401300000,
    "signature": "aae6064e87f6d63b8009aab546dfa7bdbecba0659ed7048ba79d0e4f746580dd",
    "startFixed": false,
    "requestedTime": 1792401300000,
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