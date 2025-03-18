import { WGS84, EARLIEST_SHIFT_START, LATEST_SHIFT_END, MIN_PREP } from '$lib/constants';
import { db } from '$lib/server/db';
import { covers } from '$lib/server/db/covers';
import { sql } from 'kysely';
import type { Coordinates } from '$lib/util/Coordinates';
import type { Capacities } from '$lib/server/booking/Capacities';
import { Interval } from '$lib/util/interval';
import { getAllowedTimes } from '$lib/util/getAllowedTimes';
import type { UnixtimeMs } from '$lib/util/UnixtimeMs';
import { jsonArrayFrom } from 'kysely/helpers/postgres';

interface CoordinatesTable {
	busStopIndex: number;
	lat: number;
	lng: number;
}

const withBusStops = (busStops: Coordinates[]) => {
	return db.with('busstops', (db) => {
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

export const getViableBusStops = async (
	userChosen: Coordinates,
	busStops: Coordinates[],
	capacities: Capacities,
	earliest: UnixtimeMs,
	latest: UnixtimeMs
): Promise<BlacklistingResult[]> => {
	if (busStops.length == 0) {
		return [];
	}
	const response = await withBusStops(busStops)
		.selectFrom('zone')
		.where(covers(userChosen))
		.select((eb) => [
			jsonArrayFrom(
				eb
					.selectFrom('busstops')
					.where(
						sql<boolean>`ST_Covers(zone.area, ST_SetSRID(ST_MakePoint(busstops.lng, busstops.lat), ${WGS84}))`
					)
					.select((eb) => [
						'busstops.busStopIndex',
						jsonArrayFrom(
							eb
								.selectFrom('company')
								.innerJoin('vehicle', 'vehicle.company', 'company.id')
								.innerJoin('availability', 'vehicle.id', 'availability.vehicle')
								.whereRef('company.zone', '=', 'zone.id')
								.where('vehicle.passengers', '>=', capacities.passengers)
								.where('vehicle.bikes', '>=', capacities.bikes)
								.where('vehicle.wheelchairs', '>=', capacities.wheelchairs)
								.where(
									sql<boolean>`"vehicle"."luggage" >= cast(${capacities.luggage} as integer) + cast(${capacities.passengers} as integer) - cast("vehicle"."passengers" as integer)`
								)
								.where('availability.startTime', '<=', latest)
								.where('availability.endTime', '>=', earliest)
								.select(['availability.startTime', 'availability.endTime'])
						).as('intervals')
					])
			).as('valid')
		])
		.executeTakeFirst();
	if (response === undefined || response.valid.length === 0) {
		return [];
	}
	const lastValidTime = 8640000000000000;
	const afterPreptime = new Interval(Date.now() + MIN_PREP, lastValidTime);
	const allowedTimes = Interval.intersect(
		getAllowedTimes(earliest, latest, EARLIEST_SHIFT_START, LATEST_SHIFT_END),
		[afterPreptime]
	);
	console.log('BLACKLIST QUERY RESULT: ', JSON.stringify(response, null, '\t'));
	return response.valid.map((r) => {
		return {
			...r,
			intervals: Interval.intersect(
				Interval.merge(r.intervals.map((i) => new Interval(i.startTime, i.endTime))),
				allowedTimes
			)
		};
	});
};

export type BlacklistingResult = {
	busStopIndex: number;
	intervals: { startTime: number; endTime: number }[];
};
