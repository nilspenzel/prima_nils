import type { ExpectedConnection } from '$lib/server/rideShareBooking/bookRide';
import type { Capacities } from '$lib/util/booking/Capacities';
import type { Insertion, NeighbourIds } from '$lib/server/rideShareBooking/insertion';
import { type Database } from '$lib/server/db';
import { sql, Transaction } from 'kysely';
import { env } from '$env/dynamic/public';
import type { ScheduledTimes } from './getScheduledTimes';

export async function insertRequest(
	connection: Insertion,
	capacities: Capacities,
	c: ExpectedConnection,
	customer: number,
	neighbourIds: NeighbourIds,
	scheduledTimes: ScheduledTimes,
	trx: Transaction<Database>
): Promise<number> {
	const approachDurations = new Array<{ id: number; prev_leg_duration: number }>();
	if (neighbourIds.nextDropoff != neighbourIds.nextPickup && neighbourIds.nextPickup) {
		approachDurations.push({
			id: neighbourIds.nextPickup,
			prev_leg_duration: connection.pickupNextLegDuration
		});
	}
	if (neighbourIds.nextDropoff) {
		approachDurations.push({
			id: neighbourIds.nextDropoff,
			prev_leg_duration: connection.dropoffNextLegDuration
		});
	}

	const returnDurations = new Array<{ id: number; next_leg_duration: number }>();
	if (neighbourIds.prevPickup) {
		returnDurations.push({
			id: neighbourIds.prevPickup,
			next_leg_duration: connection.pickupPrevLegDuration
		});
	}
	if (neighbourIds.prevDropoff != neighbourIds.prevPickup && neighbourIds.prevDropoff) {
		returnDurations.push({
			id: neighbourIds.prevDropoff,
			next_leg_duration: connection.dropoffPrevLegDuration
		});
	}

	const ticketPrice = capacities.passengers * parseInt(env.PUBLIC_FIXED_PRICE);
	const requestId = (
		await sql<{ request: number }>`
        SELECT add_ride_share_request(
            ROW(${capacities.passengers}, ${0}, ${0}, ${0}, ${capacities.wheelchairs}, ${capacities.bikes}, ${capacities.luggage}, ${customer}, ${ticketPrice}),
            ROW(${true}, ${c.start.lat}, ${c.start.lng}, ${scheduledTimes.newPickupStartTime}, ${connection.pickupTime}, ${scheduledTimes.newPickupStartTime}, ${connection.pickupPrevLegDuration}, ${connection.pickupNextLegDuration}, ${c.start.address}, ${''}),
            ROW(${false}, ${c.target.lat}, ${c.target.lng}, ${connection.dropoffTime}, ${scheduledTimes.newDropoffEndTime}, ${scheduledTimes.newDropoffEndTime}, ${connection.dropoffPrevLegDuration}, ${connection.dropoffNextLegDuration}, ${c.target.address}, ${''}),
            ROW(${connection.tour}),
            ${JSON.stringify(returnDurations)}::jsonb,
            ${JSON.stringify(approachDurations)}::jsonb,
			${JSON.stringify(scheduledTimes.updates)}::jsonb
       ) AS request`.execute(trx)
	).rows[0].request;
	return requestId;
}
