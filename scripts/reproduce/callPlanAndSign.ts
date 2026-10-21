import { PlanData } from '../../src/lib/openapi';
import { planAndSign } from '../../src/lib/planAndSign';
const originalDateNow = Date.now;

Date.now = () => new Date('2026-10-16T00:05:00Z').getTime();

const query = {
	query: {
  "time": "2026-10-20T19:23:36.489Z",
  "arriveBy": true,
  "fromPlace": "51.5322939,14.5345323",
  "toPlace": "51.4651482,14.769476",
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
  "luggage": 0,
  "fastestDirectFactor": 1.6,
  "maxMatchingDistance": 250,
  "maxTravelTime": 1440,
  "passengers": 2
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
