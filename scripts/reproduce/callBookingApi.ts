#!/usr/bin/env ts-node

import 'dotenv/config';
import { bookingApi } from '../../src/lib/server/booking/bookingApi';

const parameters = {
  "connection1": {
    "start": {
      "lng": 14.520827,
      "lat": 51.5405733,
      "address": "Thälmann-Siedlung 25"
    },
    "target": {
      "lng": 14.5298561,
      "lat": 51.5290227,
      "address": "Rohner Weg 13b"
    },
    "startTime": 1751977585523,
    "targetTime": 1751979107523,
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
