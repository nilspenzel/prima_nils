import { lucia } from '$lib/auth';
import type { ExpectedConnection } from '$lib/bookingApiParameters';
import { Coordinates, Location } from '$lib/location';
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
import { describe, it, expect, beforeAll, beforeEach } from 'vitest';
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

beforeEach(async () => {
	await clearTours();
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
		//company = await addCompany(Zone.NIESKY, inNiesky3);
		//taxi = await addTaxi(company, { passengers: 3, bikes: 0, wheelchairs: 0, luggage: 0 });
		await setAvailability(taxi, dateInXMinutes(0), dateInXMinutes(600));
		const tsts = [];
		for(let i=0;i!=1;i++){
			tsts.push({
				coordinates: inNiesky3,
				times: [dateInXMinutes(580)]
			});
		}
		const body = JSON.stringify({
			start: inNiesky1,
			target: inNiesky2,
			startBusStops: [],
			targetBusStops: tsts,
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
		expect(new Date(pickup.scheduled_time).toISOString()).toBe(dateInXMinutes(550).toISOString());

		expect(new Date(dropoff.communicated_time).toISOString()).toBe(
			new Date(whiteResponse.direct[0].dropoffTime).toISOString()
		);
		expect(dropoff.address).toBe('target address');
		expect(
			Math.abs(inNiesky2.lat - dropoff.latitude) + Math.abs(inNiesky2.lng - dropoff.longitude)
		).toBeLessThan(COORDINATE_ROUNDING_ERROR_THRESHOLD);
		expect(dropoff.customer).toBe(mockUserId);
	}, 30000);

	it('too many passengers', async () => {
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

	it('early overlap with availability only sufficient for blacklist', async () => {
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

	it('early overlap with availability too small', async () => {
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
		const body = JSON.stringify({
			start: inNiesky1,
			target: inNiesky2,
			startBusStops: [],
			targetBusStops: [],
			times: [dateInXMinutes(-4)],
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
		const body = JSON.stringify({
			start: inNiesky1,
			target: inNiesky2,
			startBusStops: [],
			targetBusStops: [],
			times: [dateInXMinutes(-3)],
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

	it('successful append', async () => {
		//company = await addCompany(Zone.NIESKY, inNiesky3);
		//taxi = await addTaxi(company, { passengers: 3, bikes: 0, wheelchairs: 0, luggage: 0 });
		//await setAvailability(taxi, dateInXMinutes(0), dateInXMinutes(600));
		const body = JSON.stringify({
			start: inNiesky1,
			target: inNiesky2,
			startBusStops: [],
			targetBusStops: [],
			times: [dateInXMinutes(550)],
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
		expect(new Date(pickup.scheduled_time).toISOString()).toBe(dateInXMinutes(550).toISOString());

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

		// Add an other request, which should be appended to the existing tour.
		// The new requests start will be the last requests destination and as such some of the events will share the same eventgroup
		const body2 = JSON.stringify({
			start: inNiesky2,
			target: inNiesky1,
			startBusStops: [],
			targetBusStops: [],
			times: [dateInXMinutes(570)],
			startFixed: true,
			capacities
		});
		const blackResponse2 = await black(body2).then((r) => r.json());
		expect(blackResponse2.start.length).toBe(0);
		expect(blackResponse2.target.length).toBe(0);
		expect(blackResponse2.direct.length).toBe(1);
		expect(blackResponse2.direct[0]).toBe(true);

		const whiteResponse2 = await white(body2).then((r) => r.json());
		expect(whiteResponse2.start.length).toBe(0);
		expect(whiteResponse2.target.length).toBe(0);
		expect(whiteResponse2.direct.length).toBe(1);
		expect(whiteResponse2.direct[0]).not.toBe(null);

		const appendConnection: ExpectedConnection = {
			start: new Location(inNiesky2, 'start address'),
			target: new Location(inNiesky1, 'target address'),
			startTime: whiteResponse2.direct[0].pickupTime,
			targetTime: whiteResponse2.direct[0].dropoffTime
		};
		const bookingBodyAppend = JSON.stringify({
			connection1: appendConnection,
			connection2: null,
			capacities
		});

		await booking(bookingBodyAppend);
		const tours2 = await getTours();
		expect(tours2.length).toBe(1);
		expect(new Date(tours2[0].departure).getTime()).toBe(new Date(tours[0].departure).getTime());
		expect(new Date(tours2[0].arrival).getTime()).not.toBe(new Date(tours[0].arrival).getTime());
		const requests = tours2[0].requests;
		expect(requests.length).toBe(2);
		const events = requests[0].events;
		expect(events.length).toBe(2);
		const events2 = requests[1].events;
		expect(events.length).toBe(2);
		const eventGroups = new Set<string>();
		events.forEach((e)=> eventGroups.add(e.event_group));
		events2.forEach((e)=> eventGroups.add(e.event_group));
		expect(eventGroups.size).toBe(3);
	});

	it('successful connect', async () => {
		//company = await addCompany(Zone.NIESKY, inNiesky3);
		//taxi = await addTaxi(company, { passengers: 3, bikes: 0, wheelchairs: 0, luggage: 0 });
		//await setAvailability(taxi, dateInXMinutes(0), dateInXMinutes(600));
		const distance = 22;
		const bodyObj = {
			start: inNiesky1,
			target: inNiesky2,
			startBusStops: [],
			targetBusStops: [],
			times: [dateInXMinutes(10)],
			startFixed: true,
			capacities
		};
		const body = JSON.stringify(bodyObj);
		const whiteResponse = await white(body).then((r) => r.json());

		const connection1: ExpectedConnection = {
			start: new Location(inNiesky1, 'start address'),
			target: new Location(inNiesky2, 'target address'),
			startTime: whiteResponse.direct[0].pickupTime,
			targetTime: whiteResponse.direct[0].dropoffTime
		};
		const bookingBody = JSON.stringify({
			connection1: null,
			connection2: connection1,
			capacities
		});
		await booking(bookingBody);
		const tours = await getTours();
		expect(tours.length).toBe(1);

		// Add an other request, which should be accepted by creating a new tour.
		bodyObj.times = [dateInXMinutes(10+30)];
		const body2 = JSON.stringify(bodyObj);

		const whiteResponse2 = await white(body2).then((r) => r.json());
		expect(whiteResponse2.direct.length).toBe(1);
		expect(whiteResponse2.direct[0]).not.toBe(null);

		const connection2: ExpectedConnection = {
			start: new Location(inNiesky1, 'start address'),
			target: new Location(inNiesky2, 'target address'),
			startTime: whiteResponse2.direct[0].pickupTime,
			targetTime: whiteResponse2.direct[0].dropoffTime
		};
		const bookingBody2 = JSON.stringify({
			connection1: null,
			connection2: connection2,
			capacities
		});

		await booking(bookingBody2);
		const tours2 = await getTours();
		expect(tours2.length).toBe(2);

		// Add a third request, which should connect the two existing tours.
		const body3 = JSON.stringify({
			start: inNiesky2,
			target: inNiesky1,
			startBusStops: [],
			targetBusStops: [],
			times: [dateInXMinutes(10+10)],
			startFixed: true,
			capacities
		});
		
		const whiteResponse3 = await white(body3).then((r) => r.json());
		expect(whiteResponse3.direct.length).toBe(1);
		expect(whiteResponse3.direct[0]).not.toBe(null);

		const connection3: ExpectedConnection = {
			start: new Location(inNiesky2, 'start address'),
			target: new Location(inNiesky1, 'target address'),
			startTime: whiteResponse3.direct[0].pickupTime,
			targetTime: whiteResponse3.direct[0].dropoffTime
		};
		const bookingBody3 = JSON.stringify({
			connection1: null,
			connection2: connection3,
			capacities
		});

		await booking(bookingBody3);
		const tours3 = await getTours();
		expect(tours3.length).toBe(1);

		const eventGroups = new Set<string>();
		tours3.flatMap((t) => t.requests.flatMap((r) => r.events)).forEach((e)=> eventGroups.add(e.event_group));
		expect(eventGroups.size).toBe(4);
	});

	it('startFixed = false, simple success case', async () => {
		await setAvailability(taxi, dateInXMinutes(0), dateInXMinutes(600));
		const tsts = [];
		for(let i=0;i!=1;i++){
			tsts.push({
				coordinates: inNiesky3,
				times: [dateInXMinutes(580)]
			});
		}
		const body = JSON.stringify({
			start: inNiesky1,
			target: inNiesky2,
			startBusStops: [],
			targetBusStops: tsts,
			times: [dateInXMinutes(550)],
			startFixed: false,
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
		expect(new Date(dropoff.scheduled_time).toISOString()).toBe(dateInXMinutes(550).toISOString());
	}, 30000);

	it('successful prepend', async () => {
		//company = await addCompany(Zone.NIESKY, inNiesky3);
		//taxi = await addTaxi(company, { passengers: 3, bikes: 0, wheelchairs: 0, luggage: 0 });
		//await setAvailability(taxi, dateInXMinutes(0), dateInXMinutes(600));
		const body = JSON.stringify({
			start: inNiesky1,
			target: inNiesky2,
			startBusStops: [],
			targetBusStops: [],
			times: [dateInXMinutes(550)],
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
		expect(new Date(pickup.scheduled_time).toISOString()).toBe(dateInXMinutes(550).toISOString());

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

		// Add an other request, which should be appended to the existing tour.
		// The new requests start will be the last requests destination and as such some of the events will share the same eventgroup
		const body2 = JSON.stringify({
			start: inNiesky2,
			target: inNiesky1,
			startBusStops: [],
			targetBusStops: [],
			times: [dateInXMinutes(530)],
			startFixed: true,
			capacities
		});
		const blackResponse2 = await black(body2).then((r) => r.json());
		expect(blackResponse2.start.length).toBe(0);
		expect(blackResponse2.target.length).toBe(0);
		expect(blackResponse2.direct.length).toBe(1);
		expect(blackResponse2.direct[0]).toBe(true);

		const whiteResponse2 = await white(body2).then((r) => r.json());
		expect(whiteResponse2.start.length).toBe(0);
		expect(whiteResponse2.target.length).toBe(0);
		expect(whiteResponse2.direct.length).toBe(1);
		expect(whiteResponse2.direct[0]).not.toBe(null);

		const appendConnection: ExpectedConnection = {
			start: new Location(inNiesky2, 'start address'),
			target: new Location(inNiesky1, 'target address'),
			startTime: whiteResponse2.direct[0].pickupTime,
			targetTime: whiteResponse2.direct[0].dropoffTime
		};
		const bookingBodyAppend = JSON.stringify({
			connection1: appendConnection,
			connection2: null,
			capacities
		});

		await booking(bookingBodyAppend);
		const tours2 = await getTours();
		expect(tours2.length).toBe(1);
		expect(new Date(tours2[0].departure).getTime()).not.toBe(new Date(tours[0].departure).getTime());
		expect(new Date(tours2[0].arrival).getTime()).toBe(new Date(tours[0].arrival).getTime());
		const requests = tours2[0].requests;
		expect(requests.length).toBe(2);
		const events = requests[0].events;
		expect(events.length).toBe(2);
		const events2 = requests[1].events;
		expect(events.length).toBe(2);
		const eventGroups = new Set<string>();
		events.forEach((e)=> eventGroups.add(e.event_group));
		events2.forEach((e)=> eventGroups.add(e.event_group));
		expect(eventGroups.size).toBe(3);
	});
});
