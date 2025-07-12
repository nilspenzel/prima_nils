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

const inNiesky = { lat: 51.29468377345111, lng: 14.833542206420248 };
const inBautzen = { lng: 14.434463472307556, lat: 51.18137889958882 };

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
		await addRideShareTour(inXMinutes(65), true, 1, 0, mockUserId, inNiesky, inBautzen);
		const busStops = new Array<BusStop>();
		const body = JSON.stringify({
			start: inNiesky,
			target: inBautzen,
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
