import type { ExpectedConnection } from '$lib/server/rideShareBooking/bookRide';
import type { Capacities } from '$lib/util/booking/Capacities';
import type { Insertion } from '$lib/server/rideShareBooking/insertion';
import { type Database } from '$lib/server/db';
import { sql, Transaction } from 'kysely';
import { env } from '$env/dynamic/public';
import type { ScheduledTimes } from './getScheduledTimes';

export async function insertRequest(
	connection: Insertion,
	capacities: Capacities,
	c: ExpectedConnection,
	customer: number,
	scheduledTimes: ScheduledTimes,
	trx: Transaction<Database>
): Promise<number> {
	const ticketPrice = capacities.passengers * parseInt(env.PUBLIC_FIXED_PRICE);
	const requestId = (
		await sql<{ request: number }>`
        SELECT add_ride_share_request(
            ROW(${capacities.passengers}, ${0}, ${0}, ${0}, ${capacities.wheelchairs}, ${capacities.bikes}, ${capacities.luggage}, ${customer}, ${ticketPrice}),
            ROW(${true}, ${c.start.lat}, ${c.start.lng}, ${connection.pickupTime}, ${connection.scheduledPickupTime}, ${connection.pickupTime}, ${connection.pickupPrevLegDuration}, ${connection.pickupNextLegDuration}, ${c.start.address}, ${''}),
            ROW(${false}, ${c.target.lat}, ${c.target.lng}, ${connection.scheduledDropoffTime}, ${connection.dropoffTime}, ${connection.dropoffTime}, ${connection.dropoffPrevLegDuration}, ${connection.dropoffNextLegDuration}, ${c.target.address}, ${''}),
            ROW(${connection.rideShareTour}),
			${JSON.stringify([
				{ event: connection.prevDropoffId, duration: connection.dropoffPrevLegDuration },
				{ event: connection.prevPickupId, duration: connection.pickupPrevLegDuration }
			])}::jsonb,
			${JSON.stringify([
				{ event: connection.nextDropoffId, duration: connection.dropoffNextLegDuration },
				{ event: connection.nextPickupId, duration: connection.pickupNextLegDuration }
			])}::jsonb,
			${JSON.stringify(scheduledTimes.updates)}::jsonb
       ) AS request`.execute(trx)
	).rows[0].request;
	return requestId;
}
