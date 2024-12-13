import { lucia } from '$lib/auth';
import type { ExpectedConnection } from '$lib/bookingApiParameters';
import { Coordinates, Location } from '$lib/location';
import { oneToMany } from '$lib/api';
import {
	addCompany,
	addTaxi,
	addTestUser,
	clearDatabase,
	clearTours,
	getTours,
	setAvailability,
	Zone
} from '$lib/testHelpers';
import { minutesToMs, msToMinutes } from '$lib/time_utils';
import { Cookie } from 'lucia';
import { describe, it, expect, beforeAll } from 'vitest';
import { COORDINATE_ROUNDING_ERROR_THRESHOLD, MAX_PASSENGER_WAITING_TIME_PICKUP } from '$lib/constants';

let taxi: number;
let company: number;

const black = async (body: string) => {
	return await fetch('http://localhost:5173/api/blacklist', {
		method: 'POST',
		headers: {
			'Content-Type': 'application/json'
		},
		body
	});
};

const white = async (body: string) => {
	return await fetch('http://localhost:5173/api/whitelist', {
		method: 'POST',
		headers: {
			'Content-Type': 'application/json'
		},
		body
	});
};

const booking = async (body: string) => {
	return await fetch('http://localhost:5173/api/booking', {
		method: 'POST',
		headers: {
			'Content-Type': 'application/json',
			Cookie: `${lucia.sessionCookieName} = ${sessionCookie.value}`
		},
		body
	});
};

const capacities = {
	passengers: 1,
	wheelchairs: 0,
	bikes: 0,
	luggage: 0
};

const inNiesky1 = new Coordinates(51.29468377345111, 14.833542206420248);
const inNiesky2 = new Coordinates(51.29544187321241, 14.820560314788537);
const inNiesky3 = new Coordinates(51.294046423258095, 14.820774891510126);

const BASE_DATE_MS = new Date('2050-09-23T17:00').getTime();
const dateInXMinutes = (x: number): Date => {
	return new Date(BASE_DATE_MS + minutesToMs(x));
};
const mockUserId = '58zzc8y1dorgva0';
let sessionCookie: Cookie;
beforeAll(async () => {
	await clearDatabase();
	await addTestUser();

	const session = await lucia.createSession(mockUserId, {});
	sessionCookie = lucia.createSessionCookie(session.id);
});

describe('Whitelist and Booking API Tests', () => {
	it('no company', async () => {
		const body = JSON.stringify({
			start: inNiesky1,
			target: inNiesky2,
			startBusStops: [],
			targetBusStops: [
				{
					coordinates: inNiesky3,
					times: [dateInXMinutes(580)]
				}
			],
			times: [dateInXMinutes(550)],
			startFixed: true,
			capacities
		});
		const blackResponse = await black(body).then((r) => r.json());
		expect(blackResponse.start.length).toBe(0);
		expect(blackResponse.target.length).toBe(1);
		expect(blackResponse.direct.length).toBe(1);
		expect(blackResponse.target[0][0]).toBe(false);
		expect(blackResponse.direct[0]).toBe(false);

		const whiteResponse = await white(body).then((r) => r.json());
		expect(whiteResponse.start.length).toBe(0);
		expect(whiteResponse.target.length).toBe(1);
		for (let i = 0; i != whiteResponse.target.length; ++i) {
			expect(whiteResponse.target[i].length).toBe(1);
			expect(whiteResponse.target[i][0]).toBe(null);
		}
		expect(whiteResponse.direct.length).toBe(1);
		expect(whiteResponse.direct[0]).toBe(null);
	});

	it('company in wrong zone', async () => {
		company = await addCompany(Zone.ALTKREIS_BAUTZEN, inNiesky3);
		taxi = await addTaxi(company, { passengers: 3, bikes: 0, wheelchairs: 0, luggage: 0 });
		await setAvailability(taxi, dateInXMinutes(0), dateInXMinutes(999999));
		const body = JSON.stringify({
			start: inNiesky1,
			target: inNiesky2,
			startBusStops: [],
			targetBusStops: [
				{
					coordinates: inNiesky3,
					times: [dateInXMinutes(580)]
				}
			],
			times: [dateInXMinutes(550)],
			startFixed: true,
			capacities
		});
		const blackResponse = await black(body).then((r) => r.json());
		expect(blackResponse.start.length).toBe(0);
		expect(blackResponse.target.length).toBe(1);
		expect(blackResponse.direct.length).toBe(1);
		expect(blackResponse.target[0][0]).toBe(false);
		expect(blackResponse.direct[0]).toBe(false);

		const whiteResponse = await white(body).then((r) => r.json());
		expect(whiteResponse.start.length).toBe(0);
		expect(whiteResponse.target.length).toBe(1);
		for (let i = 0; i != whiteResponse.target.length; ++i) {
			expect(whiteResponse.target[i].length).toBe(1);
			expect(whiteResponse.target[i][0]).toBe(null);
		}
		expect(whiteResponse.direct.length).toBe(1);
		expect(whiteResponse.direct[0]).toBe(null);
	});

	it('no vehicle', async () => {
		company = await addCompany(Zone.NIESKY, inNiesky3);
		const body = JSON.stringify({
			start: inNiesky1,
			target: inNiesky2,
			startBusStops: [],
			targetBusStops: [
				{
					coordinates: inNiesky3,
					times: [dateInXMinutes(580)]
				}
			],
			times: [dateInXMinutes(550)],
			startFixed: true,
			capacities
		});
		const blackResponse = await black(body).then((r) => r.json());
		expect(blackResponse.start.length).toBe(0);
		expect(blackResponse.target.length).toBe(1);
		expect(blackResponse.direct.length).toBe(1);
		expect(blackResponse.target[0][0]).toBe(false);
		expect(blackResponse.direct[0]).toBe(false);

		const whiteResponse = await white(body).then((r) => r.json());
		expect(whiteResponse.start.length).toBe(0);
		expect(whiteResponse.target.length).toBe(1);
		for (let i = 0; i != whiteResponse.target.length; ++i) {
			expect(whiteResponse.target[i].length).toBe(1);
			expect(whiteResponse.target[i][0]).toBe(null);
		}
		expect(whiteResponse.direct.length).toBe(1);
		expect(whiteResponse.direct[0]).toBe(null);
	});

	it('no availability', async () => {
		taxi = await addTaxi(company, { passengers: 3, bikes: 0, wheelchairs: 0, luggage: 0 });
		const body = JSON.stringify({
			start: inNiesky1,
			target: inNiesky2,
			startBusStops: [],
			targetBusStops: [
				{
					coordinates: inNiesky3,
					times: [dateInXMinutes(580)]
				}
			],
			times: [dateInXMinutes(550)],
			startFixed: true,
			capacities
		});
		const blackResponse = await black(body).then((r) => r.json());
		expect(blackResponse.start.length).toBe(0);
		expect(blackResponse.target.length).toBe(1);
		expect(blackResponse.direct.length).toBe(1);
		expect(blackResponse.target[0][0]).toBe(false);
		expect(blackResponse.direct[0]).toBe(false);

		const whiteResponse = await white(body).then((r) => r.json());
		expect(whiteResponse.start.length).toBe(0);
		expect(whiteResponse.target.length).toBe(1);
		for (let i = 0; i != whiteResponse.target.length; ++i) {
			expect(whiteResponse.target[i].length).toBe(1);
			expect(whiteResponse.target[i][0]).toBe(null);
		}
		expect(whiteResponse.direct.length).toBe(1);
		expect(whiteResponse.direct[0]).toBe(null);
	});

	it('simple success case', async () => {
		await setAvailability(taxi, dateInXMinutes(0), dateInXMinutes(600));
		const body = JSON.stringify({
			start: inNiesky1,
			target: inNiesky2,
			startBusStops: [],
			targetBusStops: [
				{
					coordinates: inNiesky3,
					times: [dateInXMinutes(580)]
				}
			],
			times: [dateInXMinutes(550)],
			startFixed: true,
			capacities
		});

		const blackResponse = await black(body).then((r) => r.json());
		expect(blackResponse.start.length).toBe(0);
		expect(blackResponse.target.length).toBe(1);
		expect(blackResponse.direct.length).toBe(1);
		expect(blackResponse.target[0][0]).toBe(true);
		expect(blackResponse.direct[0]).toBe(true);

		const whiteResponse = await white(body).then((r) => r.json());
		expect(whiteResponse.start.length).toBe(0);
		expect(whiteResponse.target.length).toBe(1);
		for (let i = 0; i != whiteResponse.target.length; ++i) {
			expect(whiteResponse.target[i].length).toBe(1);
			expect(whiteResponse.target[i][0]).not.toBe(null);
		}
		expect(whiteResponse.direct.length).toBe(1);
		expect(whiteResponse.direct[0]).not.toBe(null);

		const connection1: ExpectedConnection = {
			start: new Location(inNiesky1, 'start address'),
			target: new Location(inNiesky2, 'target address'),
			startTime: whiteResponse.direct[0].pickupTime,
			targetTime: whiteResponse.direct[0].dropoffTime
		};
		const bookingBody = JSON.stringify({
			connection1,
			connection2: null,
			capacities
		});

		await booking(bookingBody);
		await new Promise((resolve) => setTimeout(resolve, 200));
		const tours = await getTours();
		expect(tours.length).toBe(1);
		expect(tours[0].requests.length).toBe(1);
		expect(tours[0].requests[0].events.length).toBe(2);
		const event1 = tours[0].requests[0].events[0];
		const event2 = tours[0].requests[0].events[1];
		expect(event1.is_pickup).not.toBe(event2.is_pickup);
		const pickup = event1.is_pickup ? event1 : event2;
		const dropoff = !event1.is_pickup ? event1 : event2;
		expect(pickup.event_group).not.toBe(dropoff.event_group);

		expect(new Date(pickup.communicated_time).toISOString()).toBe(
			new Date(whiteResponse.direct[0].pickupTime).toISOString()
		);
		expect(pickup.address).toBe('start address');
		expect(
			Math.abs(inNiesky1.lat - pickup.latitude) + Math.abs(inNiesky1.lng - pickup.longitude)
		).toBeLessThan(COORDINATE_ROUNDING_ERROR_THRESHOLD);
		expect(pickup.customer).toBe(mockUserId);

		expect(new Date(dropoff.communicated_time).toISOString()).toBe(
			new Date(whiteResponse.direct[0].dropoffTime).toISOString()
		);
		expect(dropoff.address).toBe('target address');
		expect(
			Math.abs(inNiesky2.lat - dropoff.latitude) + Math.abs(inNiesky2.lng - dropoff.longitude)
		).toBeLessThan(COORDINATE_ROUNDING_ERROR_THRESHOLD);
		expect(dropoff.customer).toBe(mockUserId);
	});

	it('too many passengers', async () => {
		await clearTours();
		const body = JSON.stringify({
			start: inNiesky1,
			target: inNiesky2,
			startBusStops: [],
			targetBusStops: [
				{
					coordinates: inNiesky3,
					times: [dateInXMinutes(580)]
				}
			],
			times: [dateInXMinutes(550)],
			startFixed: true,
			capacities: { passengers: 4, bikes: 0, wheelchairs: 0, luggage: 0 }
		});

		const blackResponse = await black(body).then((r) => r.json());
		expect(blackResponse.start.length).toBe(0);
		expect(blackResponse.target.length).toBe(1);
		expect(blackResponse.direct.length).toBe(1);
		expect(blackResponse.target[0][0]).toBe(false);
		expect(blackResponse.direct[0]).toBe(false);

		const whiteResponse = await white(body).then((r) => r.json());
		expect(whiteResponse.start.length).toBe(0);
		expect(whiteResponse.target.length).toBe(1);
		for (let i = 0; i != whiteResponse.target.length; ++i) {
			expect(whiteResponse.target[i].length).toBe(1);
			expect(whiteResponse.target[i][0]).toBe(null);
		}
		expect(whiteResponse.direct.length).toBe(1);
		expect(whiteResponse.direct[0]).toBe(null);
	});

	it('too many bikes', async () => {
		await clearTours();
		const body = JSON.stringify({
			start: inNiesky1,
			target: inNiesky2,
			startBusStops: [],
			targetBusStops: [
				{
					coordinates: inNiesky3,
					times: [dateInXMinutes(580)]
				}
			],
			times: [dateInXMinutes(550)],
			startFixed: true,
			capacities: { passengers: 1, bikes: 1, wheelchairs: 0, luggage: 0 }
		});

		const blackResponse = await black(body).then((r) => r.json());
		expect(blackResponse.start.length).toBe(0);
		expect(blackResponse.target.length).toBe(1);
		expect(blackResponse.direct.length).toBe(1);
		expect(blackResponse.target[0][0]).toBe(false);
		expect(blackResponse.direct[0]).toBe(false);

		const whiteResponse = await white(body).then((r) => r.json());
		expect(whiteResponse.start.length).toBe(0);
		expect(whiteResponse.target.length).toBe(1);
		for (let i = 0; i != whiteResponse.target.length; ++i) {
			expect(whiteResponse.target[i].length).toBe(1);
			expect(whiteResponse.target[i][0]).toBe(null);
		}
		expect(whiteResponse.direct.length).toBe(1);
		expect(whiteResponse.direct[0]).toBe(null);
	});

	it('too many wheelchairs', async () => {
		await clearTours();
		const body = JSON.stringify({
			start: inNiesky1,
			target: inNiesky2,
			startBusStops: [],
			targetBusStops: [
				{
					coordinates: inNiesky3,
					times: [dateInXMinutes(580)]
				}
			],
			times: [dateInXMinutes(550)],
			startFixed: true,
			capacities: { passengers: 1, bikes: 0, wheelchairs: 1, luggage: 0 }
		});

		const blackResponse = await black(body).then((r) => r.json());
		expect(blackResponse.start.length).toBe(0);
		expect(blackResponse.target.length).toBe(1);
		expect(blackResponse.direct.length).toBe(1);
		expect(blackResponse.target[0][0]).toBe(false);
		expect(blackResponse.direct[0]).toBe(false);

		const whiteResponse = await white(body).then((r) => r.json());
		expect(whiteResponse.start.length).toBe(0);
		expect(whiteResponse.target.length).toBe(1);
		for (let i = 0; i != whiteResponse.target.length; ++i) {
			expect(whiteResponse.target[i].length).toBe(1);
			expect(whiteResponse.target[i][0]).toBe(null);
		}
		expect(whiteResponse.direct.length).toBe(1);
		expect(whiteResponse.direct[0]).toBe(null);
	});

	it('too much luggage', async () => {
		await clearTours();
		const body = JSON.stringify({
			start: inNiesky1,
			target: inNiesky2,
			startBusStops: [],
			targetBusStops: [
				{
					coordinates: inNiesky3,
					times: [dateInXMinutes(580)]
				}
			],
			times: [dateInXMinutes(550)],
			startFixed: true,
			capacities: { passengers: 3, bikes: 0, wheelchairs: 0, luggage: 1 }
		});

		const blackResponse = await black(body).then((r) => r.json());
		expect(blackResponse.start.length).toBe(0);
		expect(blackResponse.target.length).toBe(1);
		expect(blackResponse.direct.length).toBe(1);
		expect(blackResponse.target[0][0]).toBe(false);
		expect(blackResponse.direct[0]).toBe(false);

		const whiteResponse = await white(body).then((r) => r.json());
		expect(whiteResponse.start.length).toBe(0);
		expect(whiteResponse.target.length).toBe(1);
		for (let i = 0; i != whiteResponse.target.length; ++i) {
			expect(whiteResponse.target[i].length).toBe(1);
			expect(whiteResponse.target[i][0]).toBe(null);
		}
		expect(whiteResponse.direct.length).toBe(1);
		expect(whiteResponse.direct[0]).toBe(null);
	});

	it('luggage on seats', async () => {
		await clearTours();
		const body = JSON.stringify({
			start: inNiesky1,
			target: inNiesky2,
			startBusStops: [],
			targetBusStops: [
				{
					coordinates: inNiesky3,
					times: [dateInXMinutes(580)]
				}
			],
			times: [dateInXMinutes(550)],
			startFixed: true,
			capacities: { passengers: 1, bikes: 0, wheelchairs: 0, luggage: 0 }
		});

		const blackResponse = await black(body).then((r) => r.json());
		expect(blackResponse.start.length).toBe(0);
		expect(blackResponse.target.length).toBe(1);
		expect(blackResponse.direct.length).toBe(1);
		expect(blackResponse.target[0][0]).toBe(true);
		expect(blackResponse.direct[0]).toBe(true);

		const whiteResponse = await white(body).then((r) => r.json());
		expect(whiteResponse.start.length).toBe(0);
		expect(whiteResponse.target.length).toBe(1);
		for (let i = 0; i != whiteResponse.target.length; ++i) {
			expect(whiteResponse.target[i].length).toBe(1);
			expect(whiteResponse.target[i][0]).not.toBe(null);
		}
		expect(whiteResponse.direct.length).toBe(1);
		expect(whiteResponse.direct[0]).not.toBe(null);

		const connection1: ExpectedConnection = {
			start: new Location(inNiesky1, 'start address'),
			target: new Location(inNiesky2, 'target address'),
			startTime: whiteResponse.direct[0].pickupTime,
			targetTime: whiteResponse.direct[0].dropoffTime
		};
		const bookingBody = JSON.stringify({
			connection1,
			connection2: null,
			capacities
		});

		await booking(bookingBody);
		await new Promise((resolve) => setTimeout(resolve, 200));
		const tours = await getTours();
		expect(tours.length).toBe(1);
		expect(tours[0].requests.length).toBe(1);
		expect(tours[0].requests[0].events.length).toBe(2);
		const event1 = tours[0].requests[0].events[0];
		const event2 = tours[0].requests[0].events[1];
		expect(event1.is_pickup).not.toBe(event2.is_pickup);
		const pickup = event1.is_pickup ? event1 : event2;
		const dropoff = !event1.is_pickup ? event1 : event2;
		expect(pickup.event_group).not.toBe(dropoff.event_group);

		expect(new Date(pickup.communicated_time).toISOString()).toBe(
			new Date(whiteResponse.direct[0].pickupTime).toISOString()
		);
		expect(pickup.address).toBe('start address');
		expect(
			Math.abs(inNiesky1.lat - pickup.latitude) + Math.abs(inNiesky1.lng - pickup.longitude)
		).toBeLessThan(COORDINATE_ROUNDING_ERROR_THRESHOLD);
		expect(pickup.customer).toBe(mockUserId);

		expect(new Date(dropoff.communicated_time).toISOString()).toBe(
			new Date(whiteResponse.direct[0].dropoffTime).toISOString()
		);
		expect(dropoff.address).toBe('target address');
		expect(
			Math.abs(inNiesky2.lat - dropoff.latitude) + Math.abs(inNiesky2.lng - dropoff.longitude)
		).toBeLessThan(COORDINATE_ROUNDING_ERROR_THRESHOLD);
		expect(dropoff.customer).toBe(mockUserId);
	});

	it('no overlap with availability', async () => {
		await clearTours();
		const body = JSON.stringify({
			start: inNiesky1,
			target: inNiesky2,
			startBusStops: [],
			targetBusStops: [
				{
					coordinates: inNiesky3,
					times: [dateInXMinutes(-100)]
				}
			],
			times: [dateInXMinutes(-120)],
			startFixed: true,
			capacities
		});

		const blackResponse = await black(body).then((r) => r.json());
		expect(blackResponse.start.length).toBe(0);
		expect(blackResponse.target.length).toBe(1);
		expect(blackResponse.direct.length).toBe(1);
		expect(blackResponse.target[0][0]).toBe(false);
		expect(blackResponse.direct[0]).toBe(false);

		const whiteResponse = await white(body).then((r) => r.json());
		expect(whiteResponse.start.length).toBe(0);
		expect(whiteResponse.target.length).toBe(1);
		for (let i = 0; i != whiteResponse.target.length; ++i) {
			expect(whiteResponse.target[i].length).toBe(1);
			expect(whiteResponse.target[i][0]).toBe(null);
		}
		expect(whiteResponse.direct.length).toBe(1);
		expect(whiteResponse.direct[0]).toBe(null);
	});

	it('early overlap with availability too small', async () => {
		await clearTours();
		const body = JSON.stringify({
			start: inNiesky1,
			target: inNiesky2,
			startBusStops: [],
			targetBusStops: [],
			times: [dateInXMinutes(-MAX_PASSENGER_WAITING_TIME_PICKUP)],
			startFixed: true,
			capacities
		});

		const blackResponse = await black(body).then((r) => r.json());
		expect(blackResponse.start.length).toBe(0);
		expect(blackResponse.target.length).toBe(0);
		expect(blackResponse.direct.length).toBe(1);
		expect(blackResponse.direct[0]).toBe(false);

		const whiteResponse = await white(body).then((r) => r.json());
		expect(whiteResponse.start.length).toBe(0);
		expect(whiteResponse.target.length).toBe(0);
		expect(whiteResponse.direct.length).toBe(1);
		expect(whiteResponse.direct[0]).toBe(null);
	});

	it('early overlap with availability too small', async () => {
		await clearTours();
		const body = JSON.stringify({
			start: inNiesky1,
			target: inNiesky2,
			startBusStops: [],
			targetBusStops: [],
			times: [dateInXMinutes(-msToMinutes(MAX_PASSENGER_WAITING_TIME_PICKUP)-1)],
			startFixed: true,
			capacities
		});

		const blackResponse = await black(body).then((r) => r.json());
		expect(blackResponse.start.length).toBe(0);
		expect(blackResponse.target.length).toBe(0);
		expect(blackResponse.direct.length).toBe(1);
		expect(blackResponse.direct[0]).toBe(false);

		const whiteResponse = await white(body).then((r) => r.json());
		expect(whiteResponse.start.length).toBe(0);
		expect(whiteResponse.target.length).toBe(0);
		expect(whiteResponse.direct.length).toBe(1);
		expect(whiteResponse.direct[0]).toBe(null);
	});

	it('1 point overlap early', async () => {
		await clearTours();
		const body = JSON.stringify({
			start: inNiesky1,
			target: inNiesky2,
			startBusStops: [],
			targetBusStops: [],
			times: [dateInXMinutes(-msToMinutes(MAX_PASSENGER_WAITING_TIME_PICKUP))],
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

	it('overlap barely to small for duration from company', async () => {
		await clearTours();
		const durationToStart = await oneToMany(inNiesky1, [inNiesky3],true);
		const body = JSON.stringify({
			start: inNiesky1,
			target: inNiesky2,
			startBusStops: [],
			targetBusStops: [],
			times: [dateInXMinutes(-6)],
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

	it('overlap barely sufficient for duration from company', async () => {
		await clearTours();
		const durationToStart = await oneToMany(inNiesky1, [inNiesky3],true);
		const body = JSON.stringify({
			start: inNiesky1,
			target: inNiesky2,
			startBusStops: [],
			targetBusStops: [],
			times: [dateInXMinutes(-5)],
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
		expect(whiteResponse.direct[0]).not.toBe(null);
	});
});
