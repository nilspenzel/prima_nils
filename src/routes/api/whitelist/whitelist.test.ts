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
import {
	COORDINATE_ROUNDING_ERROR_THRESHOLD,
	MAX_PASSENGER_WAITING_TIME_PICKUP
} from '$lib/constants';
import { oneToMany } from '$lib/api';
import type { BusStop } from '$lib/busStop';

let taxi: number;
let company: number;

let nieskyVehicle: number;
let horkaVehicle: number;
let biehainVehicle: number;

const n = 100;
const targetBusStops: BusStop[] = new Array<BusStop>(n);
const startBusStops: BusStop[] = new Array<BusStop>(n);

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

const nieskyPoints = [
	new Coordinates(51.23395283782045, 14.638699930592338),
	new Coordinates(51.237184908361996, 15.010479467079165)
];

// in Niesky zone:
const inNiesky1 = new Coordinates(51.29468377345111, 14.833542206420248);
const inNiesky2 = new Coordinates(51.29544187321241, 14.820560314788537);
const inNiesky3 = new Coordinates(51.294046423258095, 14.820774891510126);
const inHorka = new Coordinates(51.29763247871571, 14.895458042427606);
const inBiehain = new Coordinates(51.293447918734074, 14.934304192420939);
const inNowhere = new Coordinates(51.285611007511505, 14.98572242031949);
const inMoholz = new Coordinates(51.304408801780426, 14.777002072350683);
const inHorscha = new Coordinates(51.30376874271869, 14.72930337600468);
const betweenHorkaBiehain = new Coordinates(51.29484003237221, 14.910859106421867);
const betweenNieskyMoholz = new Coordinates(51.2932538563017, 14.787747625037866);

// in Görlitz zone:
const inLiebstein = new Coordinates(51.196870087212716, 14.904025913433145);

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

	let maxLat = -500;
	let minLat = 500;
	let maxLng = -500;
	let minLng = 500;
	for (let i = 0; i != nieskyPoints.length; ++i) {
		if (nieskyPoints[i].lat > maxLat) {
			maxLat = nieskyPoints[i].lat;
		}
		if (nieskyPoints[i].lng > maxLng) {
			maxLng = nieskyPoints[i].lng;
		}
		if (nieskyPoints[i].lat < minLat) {
			minLat = nieskyPoints[i].lat;
		}
		if (nieskyPoints[i].lng < minLng) {
			minLng = nieskyPoints[i].lng;
		}
	}
	for (let i = 0; i != n; ++i) {
		targetBusStops[i] = {
			coordinates: new Coordinates(
				Math.random() * (maxLat - minLat) + minLat,
				Math.random() * (maxLng - minLng) + minLng
			),
			times: [dateInXMinutes(100)]
		};
		startBusStops[i] = {
			coordinates: new Coordinates(
				Math.random() * (maxLat - minLat) + minLat,
				Math.random() * (maxLng - minLng) + minLng
			),
			times: [dateInXMinutes(100)]
		};
	}
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
		company = await addCompany(Zone.GÖRLITZ, inNiesky3);
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
		nieskyVehicle = taxi;
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
		const busStops = [];
		for (let i = 0; i != 1; i++) {
			busStops.push({
				coordinates: inNiesky3,
				times: [dateInXMinutes(580)]
			});
		}
		const body = JSON.stringify({
			start: inNiesky1,
			target: inNiesky2,
			startBusStops: [],
			targetBusStops: busStops,
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

	it('start and target in different zones', async () => {
		//company = await addCompany(Zone.NIESKY, inNiesky3);
		//taxi = await addTaxi(company, { passengers: 3, bikes: 0, wheelchairs: 0, luggage: 0 });
		//await setAvailability(taxi, dateInXMinutes(0), dateInXMinutes(600));

		company = await addCompany(Zone.GÖRLITZ, inLiebstein);
		taxi = await addTaxi(company, { passengers: 3, bikes: 0, wheelchairs: 0, luggage: 0 });
		await setAvailability(taxi, dateInXMinutes(0), dateInXMinutes(999999));

		// Start and target in different zones, target and targetBusStop in same zone
		const busStops = [];
		for (let i = 0; i != 1; i++) {
			busStops.push({
				coordinates: inNiesky2,
				times: [dateInXMinutes(580)]
			});
		}
		const body = JSON.stringify({
			start: inLiebstein,
			target: inNiesky1,
			startBusStops: [],
			targetBusStops: busStops,
			times: [dateInXMinutes(550)],
			startFixed: true,
			capacities
		});
		const blackResponse = await black(body).then((r) => r.json());
		expect(blackResponse.start.length).toBe(0);
		expect(blackResponse.target.length).toBe(1);
		expect(blackResponse.target[0][0]).toBe(true);
		expect(blackResponse.direct.length).toBe(1);
		expect(blackResponse.direct[0]).toBe(false);

		const whiteResponse = await white(body).then((r) => r.json());
		expect(whiteResponse.start.length).toBe(0);
		expect(whiteResponse.target.length).toBe(1);
		expect(whiteResponse.target[0][0]).not.toBe(null);
		expect(whiteResponse.direct.length).toBe(1);
		expect(whiteResponse.direct[0]).toBe(null);

		// Start and target in different zones, target and targetBusStop in different zones
		const body2 = JSON.stringify({
			start: inNiesky1,
			target: inLiebstein,
			startBusStops: [],
			targetBusStops: busStops,
			times: [dateInXMinutes(550)],
			startFixed: true,
			capacities
		});
		const blackResponse2 = await black(body2).then((r) => r.json());
		expect(blackResponse2.start.length).toBe(0);
		expect(blackResponse2.target.length).toBe(1);
		expect(blackResponse2.target[0][0]).toBe(false);
		expect(blackResponse2.direct.length).toBe(1);
		expect(blackResponse2.direct[0]).toBe(false);

		const whiteResponse2 = await white(body).then((r) => r.json());
		expect(whiteResponse2.start.length).toBe(0);
		expect(whiteResponse2.target.length).toBe(1);
		expect(whiteResponse2.target[0][0]).not.toBe(null);
		expect(whiteResponse2.direct.length).toBe(1);
		expect(whiteResponse2.direct[0]).toBe(null);
	});

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
			times: [dateInXMinutes(-msToMinutes(MAX_PASSENGER_WAITING_TIME_PICKUP) - 1)],
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
		events.forEach((e) => eventGroups.add(e.event_group));
		events2.forEach((e) => eventGroups.add(e.event_group));
		expect(eventGroups.size).toBe(3);
		expect(events[0].id).toBeLessThan(events[1].id);
		expect(events2[0].id).toBeLessThan(events2[1].id);
		expect(events[1].id).toBeLessThan(events2[0].id);
		expect(events[0].return_duration).toBe(events[1].approach_duration);
		expect(events[1].return_duration).toBe(events2[0].approach_duration);
		expect(events2[0].return_duration).toBe(events2[1].approach_duration);
	});

	it('successful connect', async () => {
		//company = await addCompany(Zone.NIESKY, inNiesky3);
		//taxi = await addTaxi(company, { passengers: 3, bikes: 0, wheelchairs: 0, luggage: 0 });
		//await setAvailability(taxi, dateInXMinutes(0), dateInXMinutes(600));
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
		bodyObj.times = [dateInXMinutes(10 + 30)];
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
			times: [dateInXMinutes(10 + 10)],
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
		tours3
			.flatMap((t) => t.requests.flatMap((r) => r.events))
			.forEach((e) => eventGroups.add(e.event_group));
		expect(eventGroups.size).toBe(4);

		const requests = tours3[0].requests;
		requests.sort((r1,r2) => {return r1.id-r2.id});

		const events1 = tours3[0].requests[0].events;
		events1.sort((e1, e2) => {return e1.id - e2.id});
		const events2 = tours3[0].requests[1].events;
		events2.sort((e1, e2) => {return e1.id - e2.id});
		const events3 = tours3[0].requests[2].events;
		events3.sort((e1, e2) => {return e1.id - e2.id});
		expect(events1[0].return_duration).toBe(events1[1].approach_duration);
		expect(events1[1].return_duration).toBe(events3[0].approach_duration);
		expect(events3[0].return_duration).toBe(events3[1].approach_duration);
		expect(events3[1].return_duration).toBe(events2[0].approach_duration);
		expect(events2[0].return_duration).toBe(events2[1].approach_duration);
	});

	it('pickup and dropoff inserted at different positions, both as connect', async () => {
		//company = await addCompany(Zone.NIESKY, inNiesky3);
		//taxi = await addTaxi(company, { passengers: 3, bikes: 0, wheelchairs: 0, luggage: 0 });
		//await setAvailability(taxi, dateInXMinutes(0), dateInXMinutes(600));
		const bodyObj = {
			start: inNiesky1,
			target: inBiehain,
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
			target: new Location(inBiehain, 'target address'),
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

		// Add a second request, which should be accepted by creating a new tour.
		const body2 = JSON.stringify({
			start: inHorka,
			target: inNiesky2,
			startBusStops: [],
			targetBusStops: [],
			times: [dateInXMinutes(10+50)],
			startFixed: true,
			capacities
		});

		const whiteResponse2 = await white(body2).then((r) => r.json());
		expect(whiteResponse2.direct.length).toBe(1);
		expect(whiteResponse2.direct[0]).not.toBe(null);

		const connection2: ExpectedConnection = {
			start: new Location(inHorka, 'start address'),
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

		// Add a third request, which should be accepted by creating a new tour.
		const body3 = JSON.stringify({
			start: inMoholz,
			target: inHorscha,
			startBusStops: [],
			targetBusStops: [],
			times: [dateInXMinutes(10 + 95)],
			startFixed: true,
			capacities
		});

		const whiteResponse3 = await white(body3).then((r) => r.json());
		expect(whiteResponse3.direct.length).toBe(1);
		expect(whiteResponse3.direct[0]).not.toBe(null);

		const connection3: ExpectedConnection = {
			start: new Location(inMoholz, 'start address'),
			target: new Location(inHorscha, 'target address'),
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
		expect(tours3.length).toBe(3);

		// Add a 4th request, which should connect the 3 existing tours
		const body4 = JSON.stringify({
			start: betweenHorkaBiehain,
			target: betweenNieskyMoholz,
			startBusStops: [],
			targetBusStops: [],
			times: [dateInXMinutes(10 + 30)],
			startFixed: true,
			capacities
		});
		console.log(await oneToMany(inBiehain, [betweenHorkaBiehain], true));
		console.log(await oneToMany(betweenHorkaBiehain, [inHorka], true));
		console.log(await oneToMany(inBiehain, [inHorka], true));

		const whiteResponse4 = await white(body4).then((r) => r.json());
		expect(whiteResponse4.direct.length).toBe(1);
		expect(whiteResponse4.direct[0]).not.toBe(null);

		const connection4: ExpectedConnection = {
			start: new Location(betweenHorkaBiehain, 'start address'),
			target: new Location(betweenNieskyMoholz, 'target address'),
			startTime: whiteResponse4.direct[0].pickupTime,
			targetTime: whiteResponse4.direct[0].dropoffTime
		};
		const bookingBody4 = JSON.stringify({
			connection1: null,
			connection2: connection4,
			capacities
		});

		await booking(bookingBody4);
		const tours4 = await getTours();
		expect(tours4.flatMap((t) => t.requests).length).toBe(4);
		expect(tours4.length).toBe(1);

		const events = tours4.flatMap((t) => t.requests.flatMap((r) => r.events));
		events.sort((e1,e2) => {return e1.id-e2.id});
		const eventGroups = new Set<string>();
		events.forEach((e) => eventGroups.add(e.event_group));
		expect(eventGroups.size).toBe(8);

		expect(events[0].return_duration).toBe(events[1].approach_duration);
		expect(events[2].return_duration).toBe(events[3].approach_duration);
		expect(events[4].return_duration).toBe(events[5].approach_duration);
		expect(events[1].return_duration).toBe(events[6].approach_duration);
		expect(events[3].return_duration).toBe(events[7].approach_duration);
	}, 30000);

	it('startFixed = false, simple success case', async () => {
		//await setAvailability(taxi, dateInXMinutes(0), dateInXMinutes(600));
		const tsts = [];
		for (let i = 0; i != 1; i++) {
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
		expect(new Date(tours2[0].departure).getTime()).not.toBe(
			new Date(tours[0].departure).getTime()
		);
		expect(new Date(tours2[0].arrival).getTime()).toBe(new Date(tours[0].arrival).getTime());
		const requests = tours2[0].requests;
		expect(requests.length).toBe(2);
		const events = requests[0].events;
		expect(events.length).toBe(2);
		const events2 = requests[1].events;
		expect(events.length).toBe(2);
		const eventGroups = new Set<string>();
		events.forEach((e) => eventGroups.add(e.event_group));
		events2.forEach((e) => eventGroups.add(e.event_group));
		expect(eventGroups.size).toBe(3);
	});

	it('3 companies', async () => {
		//company = await addCompany(Zone.NIESKY, inNiesky3);
		//taxi = await addTaxi(company, { passengers: 3, bikes: 0, wheelchairs: 0, luggage: 0 });
		//nieskyVehicle = taxi;
		//await setAvailability(taxi, dateInXMinutes(0), dateInXMinutes(600));


		company = await addCompany(Zone.NIESKY, inHorka);
		taxi = await addTaxi(company, { passengers: 3, bikes: 0, wheelchairs: 0, luggage: 0 });
		horkaVehicle = taxi;
		await setAvailability(taxi, dateInXMinutes(0), dateInXMinutes(600));

		company = await addCompany(Zone.NIESKY, inBiehain);
		taxi = await addTaxi(company, { passengers: 3, bikes: 0, wheelchairs: 0, luggage: 0 });
		biehainVehicle = taxi;
		await setAvailability(taxi, dateInXMinutes(0), dateInXMinutes(600));

		const body = JSON.stringify({
			start: inBiehain,
			target: inHorscha,
			startBusStops: [],
			targetBusStops: [],
			times: [dateInXMinutes(550)],
			startFixed: true,
			capacities: {
				passengers: 3,
				wheelchairs: 0,
				bikes: 0,
				luggage: 0
			}
		});

		const blackResponse = await black(body).then((r) => r.json());
		expect(blackResponse.direct[0]).toBe(true);

		const whiteResponse = await white(body).then((r) => r.json());
		expect(whiteResponse.direct[0]).not.toBe(null);

		const connection1: ExpectedConnection = {
			start: new Location(inBiehain, 'start address'),
			target: new Location(inHorscha, 'target address'),
			startTime: whiteResponse.direct[0].pickupTime,
			targetTime: whiteResponse.direct[0].dropoffTime
		};
		const bookingBody = JSON.stringify({
			connection1,
			connection2: null,
			capacities: {
				passengers: 3,
				wheelchairs: 0,
				bikes: 0,
				luggage: 0
			}
		});

		await booking(bookingBody);
		const tours = await getTours();
		expect(tours.length).toBe(1);
		expect(tours[0].vehicle).toBe(biehainVehicle);
		// Add the same request again, expect the next closest company to receive the order.
		const blackResponse2 = await black(body).then((r) => r.json());
		expect(blackResponse2.direct[0]).toBe(true);

		const whiteResponse2 = await white(body).then((r) => r.json());
		expect(whiteResponse2.direct[0]).not.toBe(null);

		connection1.startTime = whiteResponse2.direct[0].pickupTime;
		connection1.targetTime = whiteResponse2.direct[0].dropoffTime;
		const bookingBody2 = JSON.stringify({
			connection1: connection1,
			connection2: null,
			capacities: {
				passengers: 3,
				wheelchairs: 0,
				bikes: 0,
				luggage: 0
			}
		});

		await booking(bookingBody2);
		const tours2 = await getTours();
		expect(tours2.length).toBe(2);
		expect(tours2[1].vehicle).toBe(horkaVehicle);
		// Add the same request again, expect the next closest company to receive the order.
		const blackResponse3 = await black(body).then((r) => r.json());
		expect(blackResponse3.direct[0]).toBe(true);

		const whiteResponse3 = await white(body).then((r) => r.json());
		expect(whiteResponse3.direct[0]).not.toBe(null);

		connection1.startTime = whiteResponse3.direct[0].pickupTime;
		connection1.targetTime = whiteResponse3.direct[0].dropoffTime;
		const bookingBody3 = JSON.stringify({
			connection1: connection1,
			connection2: null,
			capacities: {
				passengers: 3,
				wheelchairs: 0,
				bikes: 0,
				luggage: 0
			}
		});

		await booking(bookingBody3);
		const tours3 = await getTours();
		expect(tours3.length).toBe(3);
		expect(tours3[2].vehicle).toBe(nieskyVehicle);
	});

	it('coordinates not found', async () => {
		const body = JSON.stringify({
			start: inNiesky1,
			target: inNowhere,
			startBusStops: [],
			targetBusStops: [],
			times: [dateInXMinutes(550)],
			startFixed: true,
			capacities
		});

		const blackResponse = await black(body).then((r) => r.json());
		expect(blackResponse.direct[0]).toBe(true);

		const whiteResponse = await white(body).then((r) => r.json());
		expect(whiteResponse.direct[0]).toBe(null);
	});

	it('many bus stops', async () => {
		//company = await addCompany(Zone.NIESKY, new Coordinates(51.23395283782045, 14.638699930592338));
		//taxi = await addTaxi(company, { passengers: 3, bikes: 0, wheelchairs: 0, luggage: 0 });
		//await setAvailability(taxi, dateInXMinutes(0), dateInXMinutes(600));
		const start = new Coordinates(51.29544187321241, 14.820560314788537);
		const target = new Coordinates(51.23395283782045, 14.638699930592338);
		const body = JSON.stringify({
			start,
			target,
			startBusStops: startBusStops,
			targetBusStops: targetBusStops,
			times: [dateInXMinutes(450)],
			startFixed: true,
			capacities
		});

		const blackResponse = await black(body).then((r) => r.json());
		expect(blackResponse.start.length).toBe(n);
		expect(blackResponse.target.length).toBe(n);
		expect(blackResponse.direct.length).toBe(1);
		expect(blackResponse.direct[0]).toBe(true);

		const whiteResponse = await white(body).then((r) => r.json());
		expect(whiteResponse.start.length).toBe(n);
		expect(whiteResponse.target.length).toBe(n);
		expect(whiteResponse.direct.length).toBe(1);
		expect(whiteResponse.direct[0]).not.toBe(null);

		// Verify that the blacklisting only provides false positives, if no route can be found and that there are no false negatives
		let falsePositives = new Array<Coordinates>();
		for (let i = 0; i != targetBusStops.length; ++i) {
			if (blackResponse.target[i][0] && whiteResponse.target[i][0] == null) {
				falsePositives.push(targetBusStops[i].coordinates);
				continue;
			}
			expect(blackResponse.target[i][0]).toBe(whiteResponse.target[i][0] != null);
		}
		const targetToTargetBus = await oneToMany(target, falsePositives, false);
		for (let i = 0; i != targetToTargetBus.length; ++i) {
			expect(targetToTargetBus[i]).toBe(undefined);
		}

		falsePositives = [];
		for (let i = 0; i != startBusStops.length; ++i) {
			if (blackResponse.start[i][0] && whiteResponse.start[i][0] == null) {
				falsePositives.push(startBusStops[i].coordinates);
				continue;
			}
		}
		const startToStartBus = await oneToMany(start, falsePositives, true);
		for (let i = 0; i != startToStartBus.length; ++i) {
			expect(startToStartBus[i]).toBe(undefined);
		}
	}, 30000);

	it('create tour concetanation, where pickup and dropoff are not inserted between the same 2 events', async () => {
		//console.log("1->2: ", await oneToMany(inNiesky1, [inNiesky2], false));
		//console.log("2->1: ", await oneToMany(inNiesky1, [inNiesky2], true));
		//console.log("1->3: ", await oneToMany(inNiesky1, [inNiesky3], false));
		//console.log("3->1: ", await oneToMany(inNiesky1, [inNiesky3], true));
		//console.log("2->3", await oneToMany(inNiesky2, [inNiesky3], false));
		//console.log("3->2", await oneToMany(inNiesky2, [inNiesky3], false));
		//company = await addCompany(Zone.NIESKY, inNiesky3);
		//taxi = await addTaxi(company, { passengers: 3, bikes: 0, wheelchairs: 0, luggage: 0 });
		//await setAvailability(taxi, dateInXMinutes(0), dateInXMinutes(600));
		
		const body = JSON.stringify({
			start: inNiesky1,
			target: inNiesky2,
			startBusStops: [],
			targetBusStops: [],
			times: [dateInXMinutes(550)],
			startFixed: false,
			capacities
		});
		const whiteResponse = await white(body).then((r) => r.json());
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

		// Add an other request, which should be appended to the existing tour.
		// The new requests start will be the last requests destination and as such some of the events will share the same eventgroup
		const body2 = JSON.stringify({
			start: inNiesky2,
			target: inNiesky1,
			startBusStops: [],
			targetBusStops: [],
			times: [dateInXMinutes(565)],
			startFixed: false,
			capacities
		});
		const whiteResponse2 = await white(body2).then((r) => r.json());
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
		expect(tours2[0].requests.length).toBe(2);

		// Add an other request, which should be appended to the existing tour.
		// The new requests start will be the last requests destination and as such some of the events will share the same eventgroup
		const body3 = JSON.stringify({
			start: inNiesky1,
			target: inNiesky2,
			startBusStops: [],
			targetBusStops: [],
			times: [dateInXMinutes(580)],
			startFixed: false,
			capacities
		});
		const whiteResponse3 = await white(body3).then((r) => r.json());
		const appendConnection2: ExpectedConnection = {
			start: new Location(inNiesky1, 'start address'),
			target: new Location(inNiesky2, 'target address'),
			startTime: whiteResponse3.direct[0].pickupTime,
			targetTime: whiteResponse3.direct[0].dropoffTime
		};
		const bookingBodyAppend2 = JSON.stringify({
			connection1: appendConnection2,
			connection2: null,
			capacities
		});
		await booking(bookingBodyAppend2);
		const tours3 = await getTours();
		expect(tours3.length).toBe(1);
		expect(tours3[0].requests.length).toBe(3);
	});
});
