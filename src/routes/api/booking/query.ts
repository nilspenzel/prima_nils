import { sql } from 'kysely';
import { db } from '$lib/database';
import type { Capacities } from '$lib/capacities';
import type { InsertionEvaluation } from '../whitelist/insertions';
import type { ExpectedConnection } from '$lib/bookingApiParameters';

export async function insertRequest(
	connection: InsertionEvaluation,
	capacities: Capacities,
	c: ExpectedConnection,
	customer: string
) {
	const mergeTourList: number[] = []; //TODO
	const tourId = connection.tour;
	// create_and_merge_tours is a stored procedure introduced in migrations/2024-10-24-stored-procedures.js
	await sql`
        CALL create_and_merge_tours(
            ROW(${capacities.passengers}, ${capacities.wheelchairs}, ${capacities.bikes}, ${capacities.luggage}),
            ROW(${true}, ${c.start.coordinates.lat}, ${c.start.coordinates.lng}, ${connection.pickupTime}, ${connection.pickupTime}, ${customer}, ${connection.passengerDuration}, ${connection.passengerDuration},${c.start.address}),
            ROW(${true}, ${c.target.coordinates.lat}, ${c.target.coordinates.lng}, ${connection.dropoffTime}, ${connection.dropoffTime}, ${customer}, ${connection.passengerDuration}, ${connection.passengerDuration},${c.target.address}),
            ${mergeTourList},
            ROW(${connection.departure}, ${connection.arrival}, ${connection.vehicle}, ${tourId})
        )`.execute(db);
}
