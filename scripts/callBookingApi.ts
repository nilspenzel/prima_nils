#!/usr/bin/env ts-node

import 'dotenv/config';
import { bookingApi } from '../src/lib/server/booking/bookingApi';

const parameters = {
  "connection1": {
    "start": {
      "lng": 14.5366817,
      "lat": 51.5286634,
      "address": "Rohner Weg 6"
    },
    "target": {
      "lng": 14.5270988,
      "lat": 51.4265192,
      "address": "WSG 4km"
    },
    "startTime": 1751250787858,
    "targetTime": 1751253057338,
    "signature": "",
    "startFixed": true
  },
  "connection2": null,
  "capacities": {
    "passengers": 2,
    "bikes": 0,
    "luggage": 0,
    "wheelchairs": 0
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
