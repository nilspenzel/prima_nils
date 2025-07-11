import { addTestUser, clearDatabase } from '$lib/testHelpers';
import { describe, it, expect, beforeAll, beforeEach } from 'vitest';
import { createSession } from '$lib/server/auth/session';
import { black, inXMinutes, white } from '../util';
import { type BusStop } from '$lib/server/booking/BusStop';
import { addRideShareTour } from '../../addRideShareTour';

let sessionToken: string;

const capacities = {
	passengers: 1,
	wheelchairs: 0,
	bikes: 0,
	luggage: 0
};

const inNiesky1 = { lat: 51.29468377345111, lng: 14.833542206420248 };
const inNiesky2 = { lat: 51.29544187321241, lng: 14.820560314788537 };

let mockUserId = -1;

beforeAll(async () => {
	await clearDatabase();
}, 60000);

beforeEach(async () => {
	await clearDatabase();
	mockUserId = (await addTestUser()).id;
	sessionToken = 'generateSessionToken()';
	console.log('Creating session for user ', mockUserId);
	await createSession(sessionToken, mockUserId);
});

describe('Whitelist and Booking API Tests for RideSharing', () => {
	it('simple rideShareInsert', async () => {
		await addRideShareTour(inXMinutes(65), true, 1, 0, mockUserId, inNiesky1, inNiesky2);
		const busStops = new Array<BusStop>();
		const body = JSON.stringify({
			start: inNiesky1,
			target: inNiesky2,
			startBusStops: [],
			targetBusStops: busStops,
			directTimes: [inXMinutes(70)],
			startFixed: true,
			capacities
		});

		const blackResponse = await black(body).then((r) => r.json());
		expect(blackResponse.start.length).toBe(0);
		expect(blackResponse.target.length).toBe(0);
		expect(blackResponse.direct.length).toBe(1);
		expect(blackResponse.direct[0]).toBe(true);

		const whiteResponse = await white(body).then((r) => r.json());
		expect(whiteResponse.start.length).toBe(0);
		expect(whiteResponse.target.length).toBe(0);
		expect(whiteResponse.direct.length).toBe(1);
		expect(whiteResponse.direct[0]).toBe(null);
	});
});
