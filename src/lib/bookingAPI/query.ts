import { Coordinates } from '$lib/location.js';
import { Interval } from '$lib/interval.js';
import { jsonArrayFrom } from 'kysely/helpers/postgres';
import { sql } from 'kysely';
import { db } from '$lib/database';
import type { ExpressionBuilder, Kysely, Transaction } from 'kysely';
import type { Database } from '$lib/types';
import { MAX_TRAVEL_MS, SRID } from '$lib/constants';
import type { Company, Vehicle } from '$lib/compositionTypes';
import type { Capacities } from '$lib/capacities';
import type { Event } from '$lib/compositionTypes';

export type BookingApiQueryResult = {
	companies: Company[];
	busStopCompanyFilter: boolean[][];
};

export function forEachVehicle<T>(companies: Company[], fn: (c: Company, v: Vehicle) => T) {
	companies.forEach((c) =>
		c.vehicles.forEach((v) => {
			fn(c, v);
		})
	);
}

type DbEvent = {
	id: number;
	bikes: number;
	wheelchairs: number;
	passengers: number;
	luggage: number;
	is_pickup: boolean;
	scheduled_time: Date;
	communicated_time: Date;
	latitude: number;
	longitude: number;
	approach_duration: number;
	return_duration: number;
	event_group: string;
	direct_driving_duration: number | null;
};

type DbTour = {
	id: number;
	arrival: Date;
	departure: Date;
	events: DbEvent[];
};

type DbVehicle = {
	id: number;
	bike_capacity: number;
	wheelchair_capacity: number;
	seats: number;
	storage_space: number;
	tours: DbTour[];
	availabilities: DbAvailability[];
};

type DbAvailability = {
	start_time: Date;
	end_time: Date;
};

const createEvent = (e: DbEvent, t: DbTour): Event => {
	const scheduled: Date = new Date(e.scheduled_time);
	const communicated: Date = new Date(e.communicated_time);
	const arrival = new Date(t.arrival);
	const departure = new Date(t.departure);
	return {
		...e,
		tourId: t.id,
		arrival,
		departure,
		capacities: {
			bikes: e.bikes,
			wheelchairs: e.wheelchairs,
			luggage: e.luggage,
			passengers: e.passengers
		},
		coordinates: new Coordinates(e.latitude, e.longitude),
		time: new Interval(
			new Date(Math.min(scheduled.getTime(), communicated.getTime())),
			new Date(Math.max(scheduled.getTime(), communicated.getTime()))
		),
		communicated: new Date(communicated),
		approachDuration: e.approach_duration,
		returnDuration: e.return_duration,
		eventGroup: e.event_group
	};
};

const createVehicle = (v: DbVehicle, expandedSearchInterval: Interval) => {
	const tours = v.tours.filter((tour) =>
		expandedSearchInterval.overlaps(new Interval(new Date(tour.departure), new Date(tour.arrival)))
	);
	const toursBefore = v.tours.filter(
		(tour) => new Date(tour.arrival) < expandedSearchInterval.startTime
	);
	const toursAfter = v.tours.filter(
		(tour) => new Date(tour.departure) > expandedSearchInterval.endTime
	);
	return {
		id: v.id,
		capacities: {
			bikes: v.bike_capacity,
			wheelchairs: v.wheelchair_capacity,
			luggage: v.storage_space,
			passengers: v.seats
		},
		availabilities: Interval.merge(
			v.availabilities.map(
				(availbility) =>
					new Interval(new Date(availbility.start_time), new Date(availbility.end_time))
			)
		),
		tours: tours.map((tour) => {
			return {
				arrival: new Date(tour.arrival),
				departure: new Date(tour.departure)
			};
		}),
		events: tours.flatMap((t) => t.events.map((e) => createEvent(e, t))),
		lastEventBefore:
			toursBefore.length == 0
				? undefined
				: toursBefore
						.flatMap((tour) => tour.events.map((event) => createEvent(event, tour)))
						.reduce((max, current) => {
							return max == undefined
								? current
								: current.communicated > max.communicated
									? current
									: max;
						}),
		firstEventAfter:
			toursAfter.length == 0
				? undefined
				: toursAfter
						.flatMap((tour) => tour.events.map((event) => createEvent(event, tour)))
						.reduce((min, current) => {
							return min == undefined
								? current
								: current.communicated < min.communicated
									? current
									: min;
						})
	};
};

const selectAvailabilities = (eb: ExpressionBuilder<Database, 'vehicle'>, interval: Interval) => {
	return jsonArrayFrom(
		eb
			.selectFrom('availability')
			.whereRef('availability.vehicle', '=', 'vehicle.id')
			.where((eb) =>
				eb.and([
					eb('availability.start_time', '<=', interval.endTime),
					eb('availability.end_time', '>=', interval.startTime)
				])
			)
			.select(['availability.start_time', 'availability.end_time'])
	).as('availabilities');
};

const selectEvents = (eb: ExpressionBuilder<Database, 'tour'>) => {
	return jsonArrayFrom(
		eb
			.selectFrom('event')
			.whereRef('event.tour', '=', 'tour.id')
			.innerJoin('request', 'event.request', 'request.id')
			.select([
				'event.id',
				'event.communicated_time',
				'event.scheduled_time',
				'event.latitude',
				'event.longitude',
				'request.passengers',
				'request.bikes',
				'request.luggage',
				'request.wheelchairs',
				'event.is_pickup',
				'event.approach_duration',
				'event.return_duration',
				'event.event_group',
				'event.direct_driving_duration'
			])
	).as('events');
};

const selectTours = (eb: ExpressionBuilder<Database, 'vehicle'>, interval: Interval) => {
	return jsonArrayFrom(
		eb
			.selectFrom('tour')
			.whereRef('tour.vehicle', '=', 'vehicle.id')
			.where((eb) =>
				eb.and([
					eb('tour.departure', '<=', interval.endTime),
					eb('tour.arrival', '>=', interval.startTime)
				])
			)
			.select((eb) => ['tour.id', 'tour.departure', 'tour.arrival', selectEvents(eb)])
	).as('tours');
};

const selectVehicles = (
	eb: ExpressionBuilder<Database, 'company'>,
	expandedSearchInterval: Interval,
	twiceEpandedSearchInterval: Interval,
	requiredCapacities: Capacities
) => {
	return jsonArrayFrom(
		eb
			.selectFrom('vehicle')
			.whereRef('vehicle.company', '=', 'company.id')
			.where((eb) =>
				eb.and([
					eb('vehicle.wheelchair_capacity', '>=', requiredCapacities.wheelchairs),
					eb('vehicle.bike_capacity', '>=', requiredCapacities.bikes),
					eb('vehicle.seats', '>=', requiredCapacities.passengers),
					eb(
						'vehicle.storage_space',
						'>=',
						sql<number>`cast(${requiredCapacities.passengers} as integer) + cast(${requiredCapacities.luggage} as integer) - ${eb.ref('vehicle.seats')}`
					)
				])
			)
			.select((eb) => [
				'vehicle.id',
				'vehicle.bike_capacity',
				'vehicle.storage_space',
				'vehicle.wheelchair_capacity',
				'vehicle.seats',
				selectTours(eb, twiceEpandedSearchInterval),
				selectAvailabilities(eb, expandedSearchInterval)
			])
	).as('vehicles');
};

const selectCompanies = (
	eb: ExpressionBuilder<Database, 'company' | 'zone'>,
	expandedSearchInterval: Interval,
	twiceEpandedSearchInterval: Interval,
	requiredCapacities: Capacities
) => {
	return jsonArrayFrom(
		eb
			.selectFrom('company')
			.whereRef('company.zone', '=', 'zone.id')
			.where((eb) =>
				eb.and([
					eb('company.latitude', 'is not', null),
					eb('company.longitude', 'is not', null),
					eb('company.street', 'is not', null),
					eb('company.house_number', 'is not', null),
					eb('company.postal_code', 'is not', null),
					eb('company.city', 'is not', null),
					eb('company.name', 'is not', null),
					eb('company.zone', 'is not', null),
					eb('company.community_area', 'is not', null)
				])
			)
			.select([
				'company.latitude',
				'company.longitude',
				'company.id',
				'company.zone',
				selectVehicles(eb, expandedSearchInterval, twiceEpandedSearchInterval, requiredCapacities)
			])
	).as('companies');
};

export const bookingApiQuery = async (
	start: Coordinates,
	requiredCapacities: Capacities,
	searchInterval: Interval,
	busStops: Coordinates[],
	trx: Transaction<Database> | Kysely<Database> | null
): Promise<{ companies: Company[]; busStopPerm: (number | undefined)[] }> => {
	interface CoordinateTable {
		index: number;
		longitude: number;
		latitude: number;
	}
	const expandedSearchInterval = searchInterval.expand(MAX_TRAVEL_MS * 3, MAX_TRAVEL_MS * 3);
	const twiceExpandedSearchInterval = searchInterval.expand(MAX_TRAVEL_MS * 6, MAX_TRAVEL_MS * 6);
	if (trx == null) {
		trx = db;
	}
	const dbResult = await trx
		.with('busstops', (db) => {
			const cteValues = busStops.map(
				(busStop, i) =>
					sql<string>`SELECT cast(${i} as integer) AS index, ${busStop.lat} AS latitude, ${busStop.lng} AS longitude`
			);
			return db
				.selectFrom(
					sql<CoordinateTable>`(${sql.join(cteValues, sql<string>` UNION ALL `)})`.as('cte')
				)
				.selectAll();
		})
		.selectFrom('zone')
		.where('zone.is_community', '=', false)
		.where(
			sql<boolean>`ST_Covers(zone.area, ST_SetSRID(ST_MakePoint(${start.lng}, ${start.lat}), ${SRID}))`
		)
		.select((eb) => [
			selectCompanies(eb, expandedSearchInterval, twiceExpandedSearchInterval, requiredCapacities),
			jsonArrayFrom(
				eb
					.selectFrom('busstops')
					.where(
						sql<boolean>`ST_Covers(zone.area, ST_SetSRID(ST_MakePoint(cast(busstops.longitude as float), cast(busstops.latitude as float)), ${SRID}))`
					)
					.select(['busstops.index as busStopIndex'])
			).as('busStop')
		])
		.executeTakeFirst();
	if (dbResult == undefined) {
		return {
			companies: [],
			busStopPerm: []
		};
	}

	const companies = dbResult.companies
		.map((company) => {
			return {
				id: company.id,
				coordinates: new Coordinates(company.latitude!, company.longitude!),
				zoneId: company.zone!,
				vehicles: company.vehicles.map((v) => createVehicle(v, expandedSearchInterval))
			};
		})
		.filter((c) => c.vehicles.length != 0);
	companies.forEach((c) =>
		c.vehicles.forEach((v) => {
			v.tours.sort((t1, t2) => t1.departure.getTime() - t2.departure.getTime());
			v.events.sort((e1, e2) => e1.time.startTime.getTime() - e2.time.startTime.getTime());
		})
	);
	const busStopPerm = new Array<number | undefined>(busStops.length);
	let counter = 0;
	for (let i = 0; i != busStops.length; ++i) {
		if (dbResult.busStop.find((bs) => bs.busStopIndex == i) != undefined) {
			busStopPerm[i] = counter++;
		}
	}
	return {
		companies,
		busStopPerm
	};
};
