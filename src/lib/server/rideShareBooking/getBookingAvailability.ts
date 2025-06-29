import { MAX_TRAVEL } from '$lib/constants';
import { Interval } from '$lib/util/interval';
import type { Coordinates } from '$lib/util/Coordinates';
import { sql, type Transaction } from 'kysely';
import type { Capacities } from '$lib/util/booking/Capacities';
import { db, type Database } from '$lib/server/db';
import { jsonArrayFrom } from 'kysely/helpers/postgres';
import { DAY } from '$lib/util/time';

const dbQuery = async (
	requestCapacities: Capacities,
	expandedSearchInterval: Interval,
	trx: Transaction<Database> | undefined
) => {
	return (
		await (trx ?? db)
			.selectFrom('rideShareTour')
			.where('rideShareTour.passengers', '>=', requestCapacities.passengers)
			.where((eb) =>
				eb(
					'rideShareTour.luggage',
					'>=',
					sql<number>`cast(${requestCapacities.passengers} as integer) + cast(${requestCapacities.luggage} as integer) - ${eb.ref('rideShareTour.passengers')}`
				)
			)
			.where('rideShareTour.cancelled', '=', false)
			.where((eb) =>
				eb(
					eb
						.selectFrom('request')
						.innerJoin('event', 'event.request', 'request.id')
						.select('event.scheduledTimeStart')
						.whereRef('request.rideShareTour', '=', 'rideShareTour.id'),
					'=',
					1
				)
			)
			.where((eb) =>
				eb(
					eb
						.selectFrom('request')
						.innerJoin('event', 'event.request', 'request.id')
						.select('event.scheduledTimeStart')
						.whereRef('request.rideShareTour', '=', 'rideShareTour.id'),
					'<=',
					expandedSearchInterval.endTime
				)
			)
			.where((eb) =>
				eb(
					eb
						.selectFrom('request')
						.innerJoin('event', 'event.request', 'request.id')
						.select('event.scheduledTimeEnd')
						.whereRef('request.rideShareTour', '=', 'rideShareTour.id'),
					'>=',
					expandedSearchInterval.startTime
				)
			)
			.select((eb) => [
				'rideShareTour.id as rideShareTour',
				'rideShareTour.luggage',
				'rideShareTour.passengers',
				jsonArrayFrom(
					eb
						.selectFrom('request')
						.innerJoin('event', 'event.request', 'request.id')
						.orderBy('event.scheduledTimeEnd asc')
						.orderBy('event.scheduledTimeStart asc')
						.select([
							'event.id as eventId',
							'request.id as requestId',
							'event.lat',
							'event.lng',
							'event.scheduledTimeStart',
							'event.scheduledTimeEnd',
							'event.isPickup',
							'event.prevLegDuration',
							'event.nextLegDuration',
							'rideShareTour.id as tourId',
							'request.passengers',
							'request.luggage',
							'request.wheelchairs',
							'request.bikes'
						])
				).as('events')
			])
			.execute()
	).map((t) => {
		return {
			...t,
			wheelchairs: 0,
			bikes: 0,
			events: t.events.map((e) => {
				return {
					...e,
					time: new Interval(e.scheduledTimeStart, e.scheduledTimeEnd)
				};
			})
		};
	});
};

export type DbResult = NonNullable<Awaited<ReturnType<typeof dbQuery>>>;

export const getBookingAvailability = async (
	userChosen: Coordinates,
	requestCapacities: Capacities,
	searchInterval: Interval,
	busStops: Coordinates[],
	trx?: Transaction<Database>
) => {
	const expandedSearchInterval = searchInterval.expand(MAX_TRAVEL * 3, MAX_TRAVEL * 3);
	const twiceExpandedSearchInterval = searchInterval.expand(DAY, DAY);
	console.log(
		'getBookingAvailability params: ',
		JSON.stringify(
			{
				searchInterval: searchInterval.toString(),
				expandedSearchInterval: expandedSearchInterval.toString(),
				twiceExpandedSearchInterval: twiceExpandedSearchInterval.toString(),
				userChosen,
				requestCapacities,
				busStops
			},
			null,
			'\t'
		)
	);

	const dbResult = await dbQuery(requestCapacities, expandedSearchInterval, trx);

	console.log('getBookingAvailabilty: dbResult=', JSON.stringify(dbResult, null, '\t'));
	return dbResult;
};

export type RideShareTour = Awaited<ReturnType<typeof getBookingAvailability>>[0];
export type RideShareEvent = RideShareTour['events'][0];
