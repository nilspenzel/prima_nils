import {
	MAX_PASSENGER_WAITING_TIME_PICKUP,
	MAX_PASSENGER_WAITING_TIME_DROPOFF,
	WGS84
} from '$lib/constants';
import { db, type Database } from '$lib/server/db';
import { covers } from '$lib/server/db/covers';
import type { ExpressionBuilder } from 'kysely';
import { sql } from 'kysely';
import type { Coordinates } from '$lib/util/Coordinates';
import type { Capacities } from '$lib/server/booking/Capacities';
import type { BusStop } from '$lib/server/booking/BusStop';
import { getAllowedTimes } from '$lib/server/booking/evaluateRequest';
import { Interval } from '$lib/server/util/interval';
import { v4 as uuidv4 } from 'uuid';

const doesAvailabilityExist = (eb: ExpressionBuilder<Database, 'vehicle' | 'times'>) => {
	return eb.exists(
		eb
			.selectFrom('availability')
			.whereRef('availability.vehicle', '=', 'vehicle.id')
			.whereRef('availability.startTime', '<=', 'times.endTime')
			.whereRef('availability.endTime', '>=', 'times.startTime')
	);
};

const doesTourExist = (eb: ExpressionBuilder<Database, 'vehicle' | 'times'>) => {
	return eb.exists(
		eb
			.selectFrom('tour')
			.whereRef('tour.vehicle', '=', 'vehicle.id')
			.where((eb) =>
				eb.and([
					eb('tour.cancelled', '=', false),
					sql<boolean>`tour.departure <= times.end_time`,
					sql<boolean>`tour.arrival >= times.start_time`
				])
			)
	);
};

const doesVehicleExist = (
	eb: ExpressionBuilder<Database, 'company' | 'zone' | 'bus' | 'times'>,
	capacities: Capacities
) => {
	return eb.exists((eb) =>
		eb
			.selectFrom('vehicle')
			.whereRef('vehicle.company', '=', 'company.id')
			.where((eb) =>
				eb.and([
					eb('vehicle.passengers', '>=', capacities.passengers),
					eb('vehicle.bikes', '>=', capacities.bikes),
					eb('vehicle.wheelchairs', '>=', capacities.wheelchairs),
					sql<boolean>`"vehicle"."luggage" >= cast(${capacities.luggage} as integer) + cast(${capacities.passengers} as integer) - cast(${eb.ref('vehicle.passengers')} as integer)`,
					eb.or([doesAvailabilityExist(eb), doesTourExist(eb)])
				])
			)
	);
};

const doesCompanyExist = (
	eb: ExpressionBuilder<Database, 'zone' | 'bus' | 'times'>,
	capacities: Capacities
) => {
	return eb.exists(
		eb
			.selectFrom('company')
			.where((eb) =>
				eb.and([eb('company.zone', '=', eb.ref('zone.id')), doesVehicleExist(eb, capacities)])
			)
	);
};

export const getViableBusStops = async (
	userChosen: Coordinates,
	busStops: BusStop[],
	startFixed: boolean,
	capacities: Capacities
): Promise<BlacklistingResult[]> => {
	if (busStops.length == 0 || !busStops.some((b) => b.times.length != 0)) {
		return [];
	}

	// Find the smallest Interval containing all availabilities and tours of the companies received as a parameter.
	let earliest = Number.MAX_VALUE;
	let latest = 0;
	let busStopIntervals = busStops.map((b) =>
		b.times.map(
			(t) =>
				new Interval(
					startFixed ? t : t - MAX_PASSENGER_WAITING_TIME_DROPOFF,
					!startFixed ? t : t + MAX_PASSENGER_WAITING_TIME_PICKUP
				)
		)
	);
	busStopIntervals.forEach((b) =>
		b.forEach((i) => {
			if (i.startTime < earliest) {
				earliest = i.startTime;
			}
			if (i.endTime > latest) {
				latest = i.endTime;
			}
		})
	);
	if (earliest >= latest) {
		return [];
	}
	const allowedTimes = getAllowedTimes(earliest, latest);
	busStopIntervals = busStopIntervals.map((b) =>
		b.map((t) => {
			const allowed = Interval.intersect(allowedTimes, [t]);
			console.assert(
				allowed.length < 2,
				'Intersecting an array of intervals with a second array of intervals with only one entry produced an array of more than one interval in viableBusStops.'
			);
			return allowed.length === 0 ? new Interval(0, 0) : allowed[0];
		})
	);

	const queryId = uuidv4();
	await db.insertInto('bus').values(
		busStops.map((busStop, i) => ({
			queryId: queryId,
			busIdx: i,
			lat: busStop.lat,
			lng: busStop.lng
		}))
	).execute();

	const t = busStopIntervals.flatMap((busStop, i) =>
		busStop.map((interval, j) => ({
			queryId: queryId,
			busIdx: i,
			timeIdx: j,             
			startTime: interval.startTime,
			endTime: interval.endTime     
		}))
	);
	const n = 1000;
	for(let i=0;i<busStopIntervals.length;i+=n) {
		await db.insertInto('times').values(t.slice(i, i+n)).execute();
	}

	return db.selectFrom('zone')
		.where(covers(userChosen))
		.innerJoinLateral(
			(eb) =>
				eb
					.selectFrom('bus')
					.where('bus.queryId', '=', queryId)
					.where(
						sql<boolean>`ST_Covers(zone.area, ST_SetSRID(ST_MakePoint(bus.lng, bus.lat), ${WGS84}))`
					)
					.selectAll()
					.as('bus'),
			(join) => join.onTrue()
		)
		.innerJoin('times', 'times.busIdx', 'bus.busIdx')
		.where('times.queryId', '=', queryId)
		.where((eb) => doesCompanyExist(eb, capacities))
		.select(['times.timeIdx as timeIndex', 'times.busIdx as busStopIndex'])
		.execute();
};

export type BlacklistingResult = {
	timeIndex: number;
	busStopIndex: number;
};
