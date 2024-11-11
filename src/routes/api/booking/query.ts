import { sql } from 'kysely';
import { db } from '$lib/database';
import type { Capacities } from '$lib/capacities';
import type { EvNew } from './+server';
import { Coordinates } from '$lib/location';
import type { InsertionEvaluation } from '../whitelist/insertions';
import type { ExpectedConnection } from '$lib/bookingApiParameters';

export const bookingApiQuery22 = async () => {
	const requestData = {
		passengers: 3,
		wheelchairs: 0,
		bikes: 1,
		luggage: 2
	};

	const event1Data = {
		is_pickup: true,
		location: { coordinates: new Coordinates(1.0, 1.0), address: 'Baker St' },
		scheduledTime: new Date('2023-10-15T10:00:00Z'),
		communicatedTime: new Date('2023-10-15T09:45:00Z'),
		customer: 'egfrfme3qe0er5y',
		approachDuration: 15,
		returnDuration: 10
	};

	const event2Data = {
		is_pickup: false,
		location: { coordinates: new Coordinates(1.0, 1.0), address: 'Oxford St' },
		scheduledTime: new Date('2023-10-15T12:00:00Z'),
		communicatedTime: new Date('2023-10-15T11:30:00Z'),
		customer: 'egfrfme3qe0er5y',
		approachDuration: 20,
		returnDuration: 15
	};

	const mergeTourList: number[] = [];
	const tourId = null;

	const departure = new Date('2023-10-15T10:00:00Z');
	const arrival = new Date('2023-10-15T12:00:00Z');
	const vehicleId = 1;

	insertRequest2(
		requestData,
		event1Data,
		event2Data,
		mergeTourList,
		departure,
		arrival,
		tourId,
		vehicleId
	);
};

export async function insertRequest2(
	capacities: Capacities,
	event1: EvNew,
	event2: EvNew,
	mergeTourList: number[],
	departure: Date,
	arrival: Date,
	tourId: number | null,
	vehicleId: number
) {
	await sql`
        CALL create_and_merge_tours(
            ROW(${capacities.passengers}, ${capacities.wheelchairs}, ${capacities.bikes}, ${capacities.luggage}),
            ROW(${true}, ${event1.location.coordinates.lat}, ${event1.location.coordinates.lng}, ${event1.scheduledTime}, ${event1.communicatedTime}, ${event1.customer}, ${event1.approachDuration}, ${event1.returnDuration},${event1.location.address}),
            ROW(${false}, ${event2.location.coordinates.lng}, ${event2.location.coordinates.lng}, ${event2.scheduledTime}, ${event2.communicatedTime}, ${event2.customer}, ${event2.approachDuration}, ${event2.returnDuration},${event2.location.address}),
            ${mergeTourList},
            ROW(${departure}, ${arrival}, ${vehicleId}, ${tourId})
        )`.execute(db);
}

export async function insertRequest(
	connection: InsertionEvaluation,
	capacities: Capacities,
	c: ExpectedConnection,
	customer: string
) {
	/*
	const event1: EvNew = {
		location: c.start,
		scheduledTime: connection.pickupTime,
		communicatedTime: connection.pickupTime,
		approachDuration: connection.passengerDuration,//TODO
		returnDuration: connection.passengerDuration,//TODO
		customer: customer
	};
	const event2: EvNew = {
		location: c.target,
		scheduledTime: connection.dropoffTime,
		communicatedTime: connection.dropoffTime,
		approachDuration: connection.passengerDuration,//TODO
		returnDuration: connection.passengerDuration,//TODO
		customer: customer
	};*/

	const mergeTourList: number[] = []; //TODO
	const departure = new Date();
	const arrival = new Date();
	const tourId = 21;
	await sql`
        CALL create_and_merge_tours(
            ROW(${capacities.passengers}, ${capacities.wheelchairs}, ${capacities.bikes}, ${capacities.luggage}),
            ROW(${true}, ${c.start.coordinates.lat}, ${c.start.coordinates.lng}, ${connection.pickupTime}, ${connection.pickupTime}, ${customer}, ${connection.passengerDuration}, ${connection.passengerDuration},${c.start.address}),
            ROW(${true}, ${c.target.coordinates.lat}, ${c.target.coordinates.lng}, ${connection.dropoffTime}, ${connection.dropoffTime}, ${customer}, ${connection.passengerDuration}, ${connection.passengerDuration},${c.target.address}),
            ${mergeTourList},
            ROW(${departure}, ${arrival}, ${connection.vehicle}, ${tourId})
        )`.execute(db);
}
