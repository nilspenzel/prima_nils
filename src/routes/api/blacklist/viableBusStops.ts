import {
	MAX_PASSENGER_WAITING_TIME_PICKUP,
	MAX_PASSENGER_WAITING_TIME_DROPOFF,
	WGS84,
	EARLIEST_SHIFT_START,
	LATEST_SHIFT_END
} from '$lib/constants';
import { db, type Database } from '$lib/server/db';
import { covers } from '$lib/server/db/covers';
import type { ExpressionBuilder } from 'kysely';
import { sql } from 'kysely';
import type { Coordinates } from '$lib/util/Coordinates';
import type { Capacities } from '$lib/server/booking/Capacities';
import { Interval } from '$lib/util/interval';
import { getAllowedTimes } from '$lib/util/getAllowedTimes';
import type { UnixtimeMs } from '$lib/util/UnixtimeMs';

interface CoordinatesTable {
	busStopIndex: number;
	lat: number;
	lng: number;
}

type TmpDatabase = Database & { busstopzone: CoordinatesTable };

const withBusStops = (busStops: Coordinates[]) => {
	return db
		.with('busstops', (db) => {
			const busStopsSelect = busStops.map(
				(busStop, i) =>
					sql<string>`SELECT
									cast(${i} as INTEGER) AS bus_stop_index,
									cast(${busStop.lat} as decimal) AS lat,
									cast(${busStop.lng} as decimal) AS lng`
			);
			return db
				.selectFrom(
					sql<CoordinatesTable>`(${sql.join(busStopsSelect, sql<string>` UNION ALL `)})`.as(
						'busstops'
					)
				)
				.selectAll();
		});
};

const doesAvailabilityExist = (eb: ExpressionBuilder<TmpDatabase, 'vehicle' | 'times'>) => {
	return eb.exists(
		eb
			.selectFrom('availability')
			.whereRef('availability.vehicle', '=', 'vehicle.id')
			.whereRef('availability.startTime', '<=', 'times.endTime')
			.whereRef('availability.endTime', '>=', 'times.startTime')
	);
};

const doesTourExist = (eb: ExpressionBuilder<TmpDatabase, 'vehicle' | 'times'>) => {
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
	eb: ExpressionBuilder<TmpDatabase, 'company' | 'zone' | 'busstopzone' | 'times'>,
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
	eb: ExpressionBuilder<TmpDatabase, 'zone' | 'busstopzone' | 'times'>,
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
	busStops: Coordinates[],
	startFixed: boolean,
	capacities: Capacities,
	earliest: UnixtimeMs,
	latest: UnixtimeMs
): Promise<BlacklistingResult[]> => {
	if (busStops.length == 0) {
		return [];
	}

	const allowedTimes = getAllowedTimes(earliest, latest, EARLIEST_SHIFT_START, LATEST_SHIFT_END);
	const searchIntervals = allowedTimes.map((allowed) => allowed.intersect(new Interval(earliest, latest))).filter((i) => i != undefined);
	const response = withBusStops(busStops)
		.selectFrom('zone')
		.where(covers(userChosen))
		.innerJoinLateral(
			(eb) =>
				eb
					.selectFrom('busstops')
					.where(
						sql<boolean>`ST_Covers(zone.area, ST_SetSRID(ST_MakePoint(busstops.lng, busstops.lat), ${WGS84}))`
					)
					.selectAll()
					.as('busstopzone'),
			(join) => join.onTrue()
		)
		.where((eb) => doesCompanyExist(eb, capacities))
		.select(['busstopzone.busStopIndex'])
		.execute();
	console.log('BLACKLIST QUERY RESULT: ', JSON.stringify(response, null, '\t'));
	return response;
};

export type BlacklistingResult = {
	busStopIndex: number;
};
