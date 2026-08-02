import {
	addCompany,
	addTaxi,
	addTestUser,
	clearDatabase,
	getTours,
	setEvent,
	setRequest,
	setTour,
	Zone
} from '$lib/testHelpers';
import { beforeEach, describe, expect, it } from 'vitest';
import { createSession } from './server/auth/session';
import { oneToManyCarRouting } from './server/util/oneToManyCarRouting';
import { PASSENGER_CHANGE_DURATION } from './constants';
import { inXMinutes } from './server/booking/testUtils';
import type { Coordinates } from './util/Coordinates';

let sessionToken: string;

beforeEach(async () => {
	await clearDatabase();
}, 5000000);

const moveTour = async (tourId: number, vehicleId: number) => {
	return await fetch('http://localhost:5173/taxi/availability/api/tour', {
		method: 'POST',
		headers: {
			'Content-Type': 'application/json',
			Cookie: `session = ${sessionToken}`
		},
		body: JSON.stringify({ tourId, vehicleId })
	});
};

const createTour = async (
	vehicle: number,
	customer: number,
	departure: number,
	arrival: number,
	start: Coordinates,
	target: Coordinates
) => {
	const tour = await setTour(vehicle, departure, arrival);
	const request = await setRequest(tour!.id, customer, '', 1);
	await setEvent(request.id, departure, true, start.lat, start.lng);
	await setEvent(request.id, arrival, false, target.lat, target.lng);
	return tour!.id;
};

const expectedDirectDuration = async (from: Coordinates, to: Coordinates) => {
	const duration = (await oneToManyCarRouting(from, [to], false))[0];
	expect(duration).not.toBeUndefined();
	return duration! + PASSENGER_CHANGE_DURATION;
};

const oldPreviousEnd = { lat: 51.29468377345111, lng: 14.833542206420248 };
const oldNextStart = { lat: 51.29544187321241, lng: 14.820560314788537 };
const targetPreviousEnd = { lat: 51.30115190837412, lng: 14.89811075304624 };
const movedStart = { lat: 51.32191394274318, lng: 14.944479873593451 };
const movedEnd = { lat: 51.335866895211666, lng: 14.96375266477358 };
const targetNextStart = { lat: 51.294046423258095, lng: 14.820774891510126 };
const irrelevant = { lat: 51.3, lng: 14.85 };

describe('tests for moving tours', () => {
	it('updates direct durations on the old and new vehicle', async () => {
		const company = await addCompany(Zone.NIESKY);
		const companyOwner = (await addTestUser(company)).id;
		sessionToken = 'generateSessionToken()';
		await createSession(sessionToken, companyOwner);

		const capacities = { passengers: 3, bikes: 0, wheelchairs: 0, luggage: 0 };
		const oldVehicle = await addTaxi(company, capacities);
		const newVehicle = await addTaxi(company, capacities);

		await createTour(
			oldVehicle,
			companyOwner,
			inXMinutes(10),
			inXMinutes(20),
			irrelevant,
			oldPreviousEnd
		);
		const movedTour = await createTour(
			oldVehicle,
			companyOwner,
			inXMinutes(40),
			inXMinutes(50),
			movedStart,
			movedEnd
		);
		const oldNextTour = await createTour(
			oldVehicle,
			companyOwner,
			inXMinutes(70),
			inXMinutes(80),
			oldNextStart,
			irrelevant
		);

		await createTour(
			newVehicle,
			companyOwner,
			inXMinutes(10),
			inXMinutes(20),
			irrelevant,
			targetPreviousEnd
		);
		const targetNextTour = await createTour(
			newVehicle,
			companyOwner,
			inXMinutes(70),
			inXMinutes(80),
			targetNextStart,
			irrelevant
		);

		const response = await moveTour(movedTour, newVehicle);
		expect(response.status).toBe(200);

		const [expectedOldNext, expectedMoved, expectedTargetNext] = await Promise.all([
			expectedDirectDuration(oldPreviousEnd, oldNextStart),
			expectedDirectDuration(targetPreviousEnd, movedStart),
			expectedDirectDuration(movedEnd, targetNextStart)
		]);
		const tours = await getTours();

		expect(tours.find((tour) => tour.id === oldNextTour)?.directDuration).toBe(expectedOldNext);
		expect(tours.find((tour) => tour.id === movedTour)?.vehicle).toBe(newVehicle);
		expect(tours.find((tour) => tour.id === movedTour)?.directDuration).toBe(expectedMoved);
		expect(tours.find((tour) => tour.id === targetNextTour)?.directDuration).toBe(
			expectedTargetNext
		);
	}, 30000);
});
