import { Interval } from '$lib/util/interval';
import type { Coordinates } from '$lib/util/Coordinates';
import { sql, type Transaction } from 'kysely';
import type { Capacities } from '$lib/util/booking/Capacities';
import { db, type Database } from '$lib/server/db';
import { jsonArrayFrom } from 'kysely/helpers/postgres';

const dbQuery = async (
	requestCapacities: Capacities,
	searchInterval: Interval,
	trx: Transaction<Database> | undefined
) => {
	return (
		await (trx ?? db)
			.selectFrom('ride_share_tour')
			.where('ride_share_tour.passengers', '>=', requestCapacities.passengers)
			.where((eb) =>
				eb(
					'ride_share_tour.luggage',
					'>=',
					sql<number>`cast(${requestCapacities.passengers} as integer) + cast(${requestCapacities.luggage} as integer) - ${eb.ref('ride_share_tour.passengers')}`
				)
			)
			.where('ride_share_tour.cancelled', '=', false)
			.where((eb) =>
				eb(
					eb
						.selectFrom('request')
						.innerJoin('event', 'event.request', 'request.id')
						.select('event.scheduledTimeEnd')
						.whereRef('request.rideShareTour', '=', 'ride_share_tour.id')
						.orderBy('event.scheduledTimeEnd asc')
						.limit(1),
					'<=',
					searchInterval.endTime
				)
			)
			.where((eb) =>
				eb(
					eb
						.selectFrom('request')
						.innerJoin('event', 'event.request', 'request.id')
						.select('event.scheduledTimeStart')
						.whereRef('request.rideShareTour', '=', 'ride_share_tour.id')
						.orderBy('event.scheduledTimeStart desc')
						.limit(1),
					'>=',
					searchInterval.startTime
				)
			)
			.select((eb) => [
				'ride_share_tour.id as rideShareTour',
				'ride_share_tour.luggage',
				'ride_share_tour.passengers',
				'ride_share_tour.provider',
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
							'ride_share_tour.id as tourId',
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

export const getRideShareTours = async (
	userChosen: Coordinates,
	requestCapacities: Capacities,
	searchInterval: Interval,
	busStops: Coordinates[],
	trx?: Transaction<Database>
) => {
	console.log(
		'getRideShareTours params: ',
		JSON.stringify(
			{
				searchInterval: searchInterval.toString(),
				userChosen,
				requestCapacities,
				busStops
			},
			null,
			'\t'
		)
	);

	const dbResult = await dbQuery(requestCapacities, searchInterval, trx);

	console.log('getRideShareTours: dbResult=', JSON.stringify(dbResult, null, '\t'));
	return dbResult;
};

export type RideShareTour = Awaited<ReturnType<typeof getRideShareTours>>[0];
export type RideShareEvent = RideShareTour['events'][0];
