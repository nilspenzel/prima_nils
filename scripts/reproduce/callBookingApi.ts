#!/usr/bin/env ts-node

import 'dotenv/config';
import { bookingApi } from '../../src/lib/server/booking/taxi/bookingApi';

const parameters = {
  "capacities": {
    "passengers": 2,
    "bikes": 0,
    "luggage": 0,
    "wheelchairs": 0
  },
  "connection1": {
    "start": {
      "lat": 51.505444,
      "lng": 14.638026999999997,
      "address": "Weißwasser Bahnhof"
    },
    "target": {
      "lat": 51.4651482,
      "lng": 14.769476,
      "address": "Friedhof Brand"
    },
    "startTime": 1792499294000,
    "targetTime": 1792500606800,
    "signature": "508d27fc579571fbf7c710a65975d3fc89d205d6963539c2c9e9623e8461f912",
    "startFixed": true,
    "requestedTime": 1792498800000,
    "mode": 1
  },
  "connection2": null
};

const kidsThreeToFour = 1;
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