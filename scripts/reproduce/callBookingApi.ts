#!/usr/bin/env ts-node

import 'dotenv/config';
import { bookingApi } from '../../src/lib/server/booking/taxi/bookingApi';

const parameters = {
  "capacities": {
    "passengers": 3,
    "bikes": 0,
    "luggage": 1,
    "wheelchairs": 0
  },
  "connection1": {
    "start": {
      "lat": 51.5388861,
      "lng": 14.5189616,
      "address": "Zum Sportplatz 5"
    },
    "target": {
      "lat": 51.5154998,
      "lng": 14.7165111,
      "address": "Geschwister-Scholl-Straße 7"
    },
    "startTime": 1786160100000,
    "targetTime": 1786161900000,
    "signature": "f1df381020834ef4779285f94ac4e868dd5308b6280f1012fb93623536d7aee2",
    "startFixed": false,
    "requestedTime": 1786161900000,
    "mode": 1
  },
  "connection2": null
};

 //13 true 2 0 1 0 false

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
