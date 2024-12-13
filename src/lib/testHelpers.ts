import type { Capacities } from './capacities';
import { db } from './database';
import { v4 as uuidv4 } from 'uuid';
import { jsonArrayFrom } from 'kysely/helpers/postgres';
import { Coordinates } from './location';

let plate = 1;

export enum Zone {
	ALTKREIS_BAUTZEN = 1,
	WEIßWASSER = 2,
	NIESKY = 3,
	GÖRLITZ = 4,
	LÖBAU = 5,
	ZITTAU = 6
}

export const addCompany = async (zone: Zone, coordinates: Coordinates = new Coordinates(1,1)): Promise<number> => {
	return (
		await db
			.insertInto('company')
			.values({
				zone: zone,
				name: 'name',
				street: 'street',
				house_number: 'house',
				city: 'city',
				latitude: coordinates.lat,
				longitude: coordinates.lng,
				postal_code: 'zip',
				community_area: 60
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
				license_plate: uuidv4(),
				company,
				seats: capacities.passengers,
				wheelchair_capacity: capacities.wheelchairs,
				bike_capacity: capacities.bikes,
				storage_space: capacities.luggage
			})
			.returning('id')
			.executeTakeFirstOrThrow()
	).id;
};

export const setAvailability = async (vehicle: number, start_time: Date, end_time: Date) => {
	await db.insertInto('availability').values({ vehicle, start_time, end_time }).execute();
};

export const setTour = async (vehicle: number, departure: Date, arrival: Date) => {
	await db.insertInto('tour').values({ vehicle, arrival, departure }).execute();
};

export const addTestUser = async () => {
	await db
		.insertInto('auth_user')
		.values({
			id: '58zzc8y1dorgva0',
			email: 'test@user.de',
			is_entrepreneur: false,
			is_maintainer: false,
			password_hash:
				'$argon2id$v=19$m=19456,t=2,p=1$4lXilBjWTY+DsYpN0eATrw$imFLatxSsy9WjMny7MusOJeAJE5ZenrOEqD88YsZv8o'
		})
		.execute();
};

export const clearDatabase = async () => {
	await db.deleteFrom('availability').execute();
	await db.deleteFrom('event').execute();
	await db.deleteFrom('request').execute();
	await db.deleteFrom('tour').execute();
	await db.deleteFrom('vehicle').execute();
	await db.deleteFrom('user_session').execute();
	await db.deleteFrom('auth_user').execute();
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
