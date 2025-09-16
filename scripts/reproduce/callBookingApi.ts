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
      "lat": 51.533173,
      "lng": 14.529221,
      "address": "Mühlroser Straße 8a"
    },
    "target": {
      "lat": 51.423436,
      "lng": 14.6559265,
      "address": "Körnerplatz"
    },
    "startTime": 1758196500000,
    "targetTime": 1758198900000,
    "signature": "2170241e4865741e06d747aec1ee1ad618bd27dbbe0d4f15937ca4346cbc5b57",
    "startFixed": true,
    "requestedTime": 1758196500000
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
