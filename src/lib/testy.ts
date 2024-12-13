import { sql } from 'kysely';
import { booking, oneToMany, wl } from './api';
import { BUFFER_TIME, PASSENGER_CHANGE_MINUTES } from './constants';
import { db } from './database';
import { Coordinates, Location } from './location';
import { minutesToMs } from './time_utils';
import type { NewAvailability, NewCompany, NewVehicle } from './types';

const c1 = new Location(new Coordinates(51.526934461032994, 14.57712544716437), '');
const c2 = new Location(new Coordinates(51.50633993767909, 14.6429459429732), '');
const baseDate = new Date('2024-12-10T15:14:13.572Z');
const date2 = new Date('2024-12-10T15:40:48.572Z');

export const ttt = async (event: any) => {
	await booking(event, c1, c2, true, baseDate, 3, 0, 0, 0);
	await booking(event, c1, c2, true, baseDate, 3, 0, 0, 0);
	await booking(event, c1, c2, true, baseDate, 3, 0, 0, 0);
	await booking(event, c1, c2, true, baseDate, 3, 0, 0, 0);
	await booking(event, c1, c2, true, baseDate, 3, 0, 0, 0);
};

export const ttt2 = async (event: any) => {
	console.log((await oneToMany(c2.coordinates, [c1.coordinates], true)).map((f) => f / 1000 / 60));
	console.log((await oneToMany(c2.coordinates, [c1.coordinates], false)).map((f) => f / 1000 / 60));
	console.log(PASSENGER_CHANGE_MINUTES + BUFFER_TIME);
	console.log(
		await booking(event, c2, c1, false, new Date(baseDate.getTime() + minutesToMs(-1)), 3, 0, 0, 0)
	);
};

const toLoc = (c: Coordinates) => {
	return new Location(c, '');
};

const p1 = toLoc(new Coordinates(51.50758235013154, 14.619843263940453));
const p2 = toLoc(new Coordinates(51.50839360487163, 14.645228172954035));

export const ttt3 = async (yes: boolean, event: any) => {
	const company1 = new Coordinates(51.501877615097754, 14.638380773336081);
	await clearDatabase();
	if (yes) {
		await createCompany(company1, 2);
	}
	await createVehicle();
	await createAvailability();

	//const whitel = await wl(event, p1.coordinates, p2.coordinates, true, [baseDate], {bikes:0,wheelchairs:0,luggage:0,passengers:1},[],[]);
	//console.log(await whitel.json());
	const r1 = await booking(event, p1, p2, true, new Date(baseDate), 3, 0, 0, 0);
	//const r2 = await booking(event, p1,p2,true,new Date(date2),3,0,0,0);
	//const td = (await oneToMany(p2.coordinates,[p1.coordinates],true))[0]/1000/60
	//console.log("td",td);
	//const r3 = await booking(event,p2,p1,false,new Date(date2),3,0,0,0);
	//console.log(r1);
	//console.log(r2);
	//console.log(r3);
};

export const te = async (event: any) => {
	const r3 = await booking(event, p2, p1, false, new Date(baseDate), 3, 0, 0, 0);
};

const isClose = (n1: number, n2: number) => {
	return Math.abs(n1 - n2) < 0.00001;
};

export const ttt4 = async () => {
	console.log('base date: ', baseDate);
	await logAll();
	const pickups = await db
		.selectFrom('event')
		.where('event.is_pickup', '=', true)
		.select(['event.longitude', 'event.scheduled_time', 'event.is_pickup'])
		.execute();
	const dropoffs = await db
		.selectFrom('event')
		.where('event.is_pickup', '=', false)
		.select(['event.longitude', 'event.scheduled_time', 'event.is_pickup'])
		.execute();
	console.log(
		isClose(pickups[0].longitude, p1.coordinates.lng) ? 'pickup ok' : 'bad pickup location'
	);
	console.log(
		isClose(dropoffs[0].longitude, p2.coordinates.lng) ? 'dropoff ok' : 'bad dropoff location'
	);
	console.log(
		baseDate.getTime() == dropoffs[0].scheduled_time.getTime()
			? 'dropoff time ok'
			: 'bad dropoff time'
	);
	const td = await oneToMany(p1.coordinates, [p2.coordinates], false);
	console.log(
		baseDate.getTime() - td[0] - minutesToMs(PASSENGER_CHANGE_MINUTES) - minutesToMs(BUFFER_TIME) ==
			pickups[0].scheduled_time.getTime()
			? 'pickup time ok'
			: 'bad pickup time'
	);
};

const logAll = async () => {
	console.log(
		await db
			.selectFrom('tour')
			.select(['tour.arrival', 'tour.departure', 'tour.vehicle', 'tour.id'])
			.execute()
	);
	console.log(
		await db
			.selectFrom('event')
			.select(['event.longitude', 'event.scheduled_time', 'event.is_pickup'])
			.execute()
	);
};

const clearDatabase = async () => {
	await db.deleteFrom('event').executeTakeFirstOrThrow();
	await db.deleteFrom('request').executeTakeFirstOrThrow();
	await db.deleteFrom('tour').executeTakeFirstOrThrow();
	await db.deleteFrom('availability').executeTakeFirstOrThrow();
	await db.deleteFrom('vehicle').executeTakeFirstOrThrow();
};

const createCompany = async (coordinates: Coordinates, zone: number) => {
	const c: NewCompany = {
		zone,
		community_area: 7,
		latitude: coordinates.lat,
		longitude: coordinates.lng
	};
	await db.insertInto('company').values(c).execute();
};

let currentV = 0;
const createVehicle = async () => {
	currentV++;
	const v: NewVehicle = {
		company: (await db.selectFrom('company').select('id').execute())[0].id,
		license_plate: currentV.toString(),
		seats: 3,
		storage_space: 1,
		bike_capacity: 1,
		wheelchair_capacity: 1
	};
	await db.insertInto('vehicle').values(v).execute();
};

const createAvailability = async () => {
	const a: NewAvailability = {
		vehicle: (await db.selectFrom('vehicle').select('id').execute())[0].id,
		start_time: new Date(),
		end_time: new Date('2026-09-30T08:47:00Z')
	};
	await db.insertInto('availability').values(a).execute();
};
