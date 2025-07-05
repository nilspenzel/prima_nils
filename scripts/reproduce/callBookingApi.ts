#!/usr/bin/env ts-node

import 'dotenv/config';
import { bookingApi } from '../../src/lib/server/booking/bookingApi';

const parameters = {
  "connection1": {
    "start": {
      "lng": 14.6336982,
      "lat": 51.4039564,
      "address": "WSG 4km"
    },
    "target": {
      "lng": 14.5295784,
      "lat": 51.5344271,
      "address": "Mühlroser Straße 3"
    },
    "startTime": 1751940000000,
    "targetTime": 1751957223009,
    "signature": "",
    "startFixed": false
  },
  "connection2": null,
  "capacities": {
    "passengers": 1,
    "bikes": 0,
    "luggage": 0,
    "wheelchairs": 0
  }
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
