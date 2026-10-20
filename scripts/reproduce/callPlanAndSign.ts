import { PlanData } from '../../src/lib/openapi';
import { planAndSign } from '../../src/lib/planAndSign';
const originalDateNow = Date.now;

Date.now = () => new Date('2026-10-16T00:05:00Z').getTime();

const query = {
	query: {
  "time": "2026-10-18T23:27:08.753Z",
  "arriveBy": false,
  "fromPlace": "51.5003717,14.8341397",
  "toPlace": "51.535357,14.5350536",
  "preTransitModes": [
    "WALK",
    "ODM"
  ],
  "postTransitModes": [
    "WALK",
    "ODM"
  ],
  "directModes": [
    "WALK",
    "ODM"
  ],
  "luggage": 1,
  "fastestDirectFactor": 1.6,
  "maxMatchingDistance": 250,
  "maxTravelTime": 1440,
  "passengers": 1
}
} as PlanData;
const baseUrl = 'http://localhost:5173';

async function main() {
	await planAndSign(query.query, baseUrl);
}

main().catch((err) => {
	console.error('Error during booking:', err);
	process.exit(1);
});
