import { v4 as uuidv4 } from 'uuid';
import { jsonArrayFrom } from 'kysely/helpers/postgres';
import type { Coordinates } from '$lib/util/Coordinates';
import type { UnixtimeMs } from '$lib/util/UnixtimeMs';
import type { Capacities } from '$lib/util/booking/Capacities';
import { db } from '$lib/server/db';
import type { BusStop } from './server/booking/BusStop';
import type { TourWithRequests } from './util/getToursTypes';
import { getScheduledEventTime } from './util/getScheduledEventTime';

export enum Zone {
	NIESKY = 1,
	WEIßWASSER = 2,
	GÖRLITZ = 3,
	LÖBAU = 4,
	ZITTAU = 5,
	ALTKREIS_BAUTZEN = 6
}

export const addCompany = async (
	zone: Zone,
	coordinates: Coordinates = { lat: 1, lng: 1 }
): Promise<number> => {
	return (
		await db
			.insertInto('company')
			.values({
				...coordinates,
				zone: zone,
				name: 'name',
				address: 'address'
			})
			.returning('id')
			.executeTakeFirstOrThrow()
	).id;
};

export const addTaxi = async (company: number, capacities: Capacities): Promise<number> => {
	return (
		await db
			.insertInto('vehicle')
			.values({
				licensePlate: uuidv4(),
				company,
				passengers: capacities.passengers,
				wheelchairs: capacities.wheelchairs,
				bikes: capacities.bikes,
				luggage: capacities.luggage
			})
			.returning('id')
			.executeTakeFirstOrThrow()
	).id;
};

export const setAvailability = async (
	vehicle: number,
	startTime: UnixtimeMs,
	endTime: UnixtimeMs
) => {
	await db.insertInto('availability').values({ vehicle, startTime, endTime }).execute();
};

export const setTour = async (
	vehicle: number,
	departure: UnixtimeMs,
	arrival: UnixtimeMs,
	fare?: number
) => {
	return await db
		.insertInto('tour')
		.values({ vehicle, arrival, departure, cancelled: false, fare: fare ?? null })
		.returning('tour.id')
		.executeTakeFirst();
};

export const setRequest = async (
	tour: number,
	customer: number,
	ticketCode: string,
	passengers?: number,
	ticketChecked?: boolean
) => {
	return await db
		.insertInto('request')
		.values({
			passengers: passengers ?? 1,
			bikes: 0,
			luggage: 0,
			wheelchairs: 0,
			tour,
			customer,
			ticketCode,
			ticketChecked: ticketChecked == undefined ? false : ticketChecked,
			cancelled: false,
			kidsFiveToSix: 0,
			kidsThreeToFour: 0,
			kidsZeroToTwo: 0,
			ticketPrice: (passengers ?? 1) * 300
		})
		.returning('id')
		.executeTakeFirstOrThrow();
};

export const setEvent = async (
	requestId: number,
	t: UnixtimeMs,
	isPickup: boolean,
	lat: number,
	lng: number
) => {
	return (
		await db
			.insertInto('event')
			.values({
				request: requestId,
				communicatedTime: t,
				scheduledTimeStart: t,
				scheduledTimeEnd: t,
				prevLegDuration: 0,
				nextLegDuration: 0,
				eventGroup: '',
				lat,
				lng,
				isPickup,
				address: '',
				cancelled: false
			})
			.returning('event.id')
			.executeTakeFirstOrThrow()
	).id;
};

export const addTestUser = async (company?: number) => {
	return await db
		.insertInto('user')
		.values({
			email: company === undefined ? 'test@user.de' : 'company@owner.de',
			name: '',
			isTaxiOwner: company !== undefined,
			isAdmin: false,
			isEmailVerified: true,
			passwordHash:
				'$argon2id$v=19$m=19456,t=2,p=1$4lXilBjWTY+DsYpN0eATrw$imFLatxSsy9WjMny7MusOJeAJE5ZenrOEqD88YsZv8o',
			companyId: company
		})
		.returning('id')
		.executeTakeFirstOrThrow();
};

export const clearDatabase = async () => {
	await db.deleteFrom('availability').execute();
	await db.deleteFrom('event').execute();
	await db.deleteFrom('request').execute();
	await db.deleteFrom('journey').execute();
	await db.deleteFrom('tour').execute();
	await db.deleteFrom('vehicle').execute();
	await db.deleteFrom('session').execute();
	await db.deleteFrom('user').execute();
	await db.deleteFrom('company').execute();
};

export const clearTours = async () => {
	await db.deleteFrom('event').execute();
	await db.deleteFrom('request').execute();
	await db.deleteFrom('tour').execute();
};

export const getTours = async () => {
	return await db
		.selectFrom('tour')
		.selectAll()
		.select((eb) => [
			jsonArrayFrom(
				eb
					.selectFrom('request')
					.whereRef('request.tour', '=', 'tour.id')
					.selectAll()
					.select((eb) => [
						jsonArrayFrom(
							eb.selectFrom('event').whereRef('event.request', '=', 'request.id').selectAll()
						).as('events')
					])
			).as('requests')
		])
		.execute();
};

export const selectEvents = async () => {
	console.log('did selectEvents');
	return await db
		.selectFrom('tour')
		.innerJoin('request', 'tour.id', 'request.tour')
		.innerJoin('event', 'event.request', 'request.id')
		.select([
			'event.id as eventid',
			'request.id as requestid',
			'tour.id as tourid',
			'event.cancelled as eventCancelled',
			'event.nextLegDuration',
			'event.prevLegDuration',
			'request.cancelled as requestCancelled',
			'tour.cancelled as tourCancelled',
			'tour.message'
		])
		.execute();
};

export function assertArraySizes<T>(
	response: T[][],
	request: BusStop[],
	caller: string,
	checkForUndefined: boolean
): void {
	console.assert(response.length === request.length, 'Array size mismatch in ' + caller);
	for (let i = 0; i != response.length; ++i) {
		console.assert(
			response[i].length === request[i].times.length,
			'Array size mismatch in ' + caller
		);
		if (checkForUndefined) {
			for (let j = 0; j != response[i].length; ++j) {
				console.assert(
					response[i][j] != null && response[i][j] != undefined,
					'Undefined in ' + caller
				);
			}
		}
	}
}

export const bookingLogs: BookingLogs[] = [];
export let iteration = 0;

export function increment() {
	++iteration;
}

export type BookingLogs = {
	type?: string;
	pickupType?: string;
	dropoffType?: string;
	cost?: number;
	prevEvent?: number;
	nextEvent?: number;
	pickupPrevLegDuration?: number;
	pickupNextLegDuration?: number;
	dropoffPrevLegDuration?: number;
	dropoffNextLegDuration?: number;
	prevLegDuration?: number;
	nextLegDuration?: number;
	iter: number;
	waitingTime?: number;
	taxiDuration?: number;
	pickupWaitingTime?: number;
	dropoffWaitingTime?: number;
	pickupTaxiDuration?: number;
	dropoffTaxiDuration?: number;
	cumulatedTaxiDrivingDelta?: number;
	oldDrivingTime?: number;
	passengerDuration?: number;
	weightedPassengerDuration?: number;
	eventOverlap?: number;
	pickupTime?: number;
	dropoffTime?: number;
	pickupNextId?: number;
	dropoffPrevId?: number;
	whitelist?: boolean;
};

export function getCost(tour: TourWithRequests) {
	const events = sortEventsByTime(
		tour.requests.flatMap((r) => r.events).filter((e) => !e.cancelled)
	);
	if (events.length === 0) {
		return {
			weightedPassengerDuration: 0,
			drivingTime: 0,
			waitingTime: 0
		};
	}
	const drivingTime = events.reduce(
		(acc, curr) => (acc += curr.nextLegDuration),
		events[0].prevLegDuration
	);
	const waitingTime = tour.endTime - tour.startTime - drivingTime;
	let weightedPassengerDuration = 0;
	let passengers = 0;
	for (let i = 0; i != events.length - 1; ++i) {
		const event = events[i];
		const nextEvent = events[i + 1];
		passengers += event.isPickup ? event.passengers : -event.passengers;
		weightedPassengerDuration +=
			(getScheduledEventTime(nextEvent) - getScheduledEventTime(event)) * passengers;
	}
	return {
		weightedPassengerDuration,
		drivingTime,
		waitingTime
	};
}

export function sortEventsByTime<
	T extends { scheduledTimeStart: number; scheduledTimeEnd: number }[]
>(events: T): T {
	return events.sort((a, b) => {
		const startDiff = a.scheduledTimeStart - b.scheduledTimeStart;
		if (startDiff !== 0) {
			return startDiff;
		}
		return a.scheduledTimeEnd - b.scheduledTimeEnd;
	});
}
