import type { Capacity } from '$lib/capacities';
import { groupBy } from '$lib/collection_utils';
import type { Company } from '$lib/compositionTypes';
import { SRID } from '$lib/constants';
import { db } from '$lib/database';
import { Interval } from '$lib/interval';
import { Coordinates, type Location } from '$lib/location';
import type { Database } from '$lib/types';
import { sql, Transaction, type ExpressionBuilder } from 'kysely';
import { jsonArrayFrom } from 'kysely/helpers/postgres';

export const getBookingIssues = async (
	from: Location,
	to: Location,
	startTime: Date,
	targetTime: Date,
	numPassengers: number,
	numWheelchairs: number,
	numBikes: number,
	luggage: number,
	customerId: string,
	bestCompany: { departure: Date; arrival: Date; vehicleId: number }
): Promise<Response | undefined> => {
	return undefined;
};

export const bookingQuery = async (
	trx: Transaction<Database>,
	from: Location,
	to: Location,
	startTime: Date,
	targetTime: Date,
	numPassengers: number,
	numWheelchairs: number,
	numBikes: number,
	luggage: number,
	customerId: string
) => {
	trx
		.with('startAddress', (db) =>
			db
				.insertInto('address')
				.values({
					street: from.address.street,
					house_number: from.address.house_number,
					postal_code: from.address.postal_code,
					city: from.address.city
				})
				.onConflict((oc) => oc.constraint('unique_addres').doUpdateSet({}))
				.returning('id')
		)
		.with('targetAddress', (db) =>
			db
				.insertInto('address')
				.values({
					street: to.address.street,
					house_number: to.address.house_number,
					postal_code: to.address.postal_code,
					city: to.address.city
				})
				.onConflict((oc) => oc.constraint('unique_addres').doUpdateSet({}))
				.returning('id')
		)
		.with('insertedTour', (db) => {
			return db
				.insertInto('tour')
				.values({
					departure: bestCompany.departure,
					arrival: bestCompany.arrival,
					vehicle: bestCompany.vehicleId!
				})
				.returning('id');
		})
		.with('insertedRequest', (db) => {
			return db
				.insertInto('request')
				.values((eb) => ({
					tour: eb.selectFrom('insertedTour').select(['insertedTour.id']),
					passengers: numPassengers,
					bikes: numBikes,
					wheelchairs: numWheelchairs,
					luggage
				}))
				.returning('id');
		})
		.insertInto('event')
		.values((eb) => [
			{
				is_pickup: true,
				latitude: from.coordinates.lat,
				longitude: from.coordinates.lng,
				scheduled_time: startTime,
				communicated_time: startTime, // TODO
				address: eb.selectFrom('startAddress').select(['startAddress.id']),
				request: eb.selectFrom('insertedRequest').select(['insertedRequest.id'])!,
				tour: eb.selectFrom('insertedTour').select(['insertedTour.id'])!,
				customer: customerId,
				passengers: numPassengers,
				bikes: numBikes,
				wheelchairs: numWheelchairs,
				luggage
			},
			{
				is_pickup: false,
				latitude: to.coordinates.lat,
				longitude: to.coordinates.lng,
				scheduled_time: targetTime,
				communicated_time: targetTime, // TODO
				address: eb.selectFrom('targetAddress').select(['targetAddress.id']),
				request: eb.selectFrom('insertedRequest').select(['insertedRequest.id'])!,
				tour: eb.selectFrom('insertedTour').select(['insertedTour.id'])!,
				customer: customerId,
				passengers: numPassengers,
				bikes: numBikes,
				wheelchairs: numWheelchairs,
				luggage
			}
		])
		.execute();
};


export type BookingApiQueryResult = {
	companies: Company[];
	targetZoneIds: Map<number, number[]>;
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
			.selectFrom('request')
			.whereRef('request.tour', '=', 'tour.id')
			.innerJoin('event', 'request.id', 'event.request')
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
				'event.is_pickup'
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
	interval: Interval,
	requiredCapacities: Capacity
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
				selectTours(eb, interval),
				selectAvailabilities(eb, interval)
			])
	).as('vehicles');
};

const selectCompanies = (
	eb: ExpressionBuilder<Database, 'company' | 'zone'>,
	interval: Interval,
	requiredCapacities: Capacity
) => {
	return jsonArrayFrom(
		eb
			.selectFrom('company')
			.whereRef('company.zone', '=', 'zone.id')
			.where((eb) =>
				eb.and([
					eb('company.latitude', 'is not', null),
					eb('company.longitude', 'is not', null),
					eb('company.address', 'is not', null),
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
				selectVehicles(eb, interval, requiredCapacities)
			])
	).as('companies');
};

export const bookingApiQuery = async (
	start: Coordinates,
	requiredCapacities: Capacity,
	expandedSearchInterval: Interval,
	targets: Coordinates[]
): Promise<BookingApiQueryResult> => {
	interface CoordinateTable {
		index: number;
		longitude: number;
		latitude: number;
	}

	const dbResult = await db
		.with('targets', (db) => {
			const cteValues = targets.map(
				(target, i) =>
					sql<string>`SELECT cast(${i} as integer) AS index, ${target.lat} AS latitude, ${target.lng} AS longitude`
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
			selectCompanies(eb, expandedSearchInterval, requiredCapacities),
			jsonArrayFrom(
				eb
					.selectFrom('targets')
					.where(
						sql<boolean>`ST_Covers(zone.area, ST_SetSRID(ST_MakePoint(cast(targets.longitude as float), cast(targets.latitude as float)), ${SRID}))`
					)
					.select(['targets.index as targetIndex', 'zone.id as zoneId'])
			).as('target')
		])
		.executeTakeFirst();

	if (dbResult == undefined) {
		return { companies: [], targetZoneIds: new Map<number, number[]>() };
	}

	const companies = dbResult.companies
		.map((c) => {
			return {
				id: c.id,
				coordinates: new Coordinates(c.latitude!, c.longitude!),
				zoneId: c.zone!,
				vehicles: c.vehicles
					.filter((v) => v.availabilities.length != 0)
					.map((v) => {
						return {
							id: v.id,
							bike_capacity: v.bike_capacity,
							seats: v.seats,
							wheelchair_capacity: v.wheelchair_capacity,
							storage_space: v.storage_space,
							availabilities: Interval.merge(
								v.availabilities.map((a) => new Interval(a.start_time, a.end_time))
							),
							tours: v.tours.map((t) => {
								return {
									id: t.id,
									departure: t.departure,
									arrival: t.arrival,
									events: t.events.map((e) => {
										const scheduled: Date = new Date(e.scheduled_time);
										const communicated: Date = new Date(e.communicated_time);
										return {
											tourId: t.id,
											id: e.id,
											bikes: e.bikes,
											wheelchairs: e.wheelchairs,
											luggage: e.luggage,
											passengers: e.passengers,
											is_pickup: e.is_pickup,
											coordinates: new Coordinates(e.latitude, e.longitude),
											time: new Interval(
												new Date(Math.min(scheduled.getTime(), communicated.getTime())),
												new Date(Math.max(scheduled.getTime(), communicated.getTime()))
											)
										};
									})
								};
							})
						};
					})
			};
		})
		.filter((c) => c.vehicles.length != 0);
	companies.forEach((c) =>
		c.vehicles.forEach((v) => {
			v.tours.sort((t1, t2) => t1.departure.getTime() - t2.departure.getTime());
			v.tours.forEach((t) =>
				t.events.sort((e1, e2) => e1.time.startTime.getTime() - e2.time.startTime.getTime())
			);
		})
	);
	return {
		companies,
		targetZoneIds: groupBy(
			dbResult.target,
			(t) => t.targetIndex,
			(t) => t.zoneId
		)
	};
};
