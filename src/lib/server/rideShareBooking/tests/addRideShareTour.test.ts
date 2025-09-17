import {
	addTestUser,
	clearDatabase
} from '$lib/testHelpers';
import { describe, it, expect, beforeAll, beforeEach } from 'vitest';
import { createSession } from '$lib/server/auth/session';
import { inXMinutes } from '$lib/server/booking/tests/util';
import { addRideShareTour } from '../addRideShareTour';
import { getRideShareTours } from '../getRideShareTours';
import { Interval } from '$lib/util/interval';

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

describe('Create new ride share tour', () => {
	it('simple success case', async () => {
		await addRideShareTour(inXMinutes(100), true, 3, 0, mockUserId, inNiesky1, inNiesky2);
		const rsTours = await getRideShareTours(capacities, new Interval(inXMinutes(0), inXMinutes(600)));
		expect(rsTours).toHaveLength(1);
	}, 30000);
});
