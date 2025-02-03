import { sql, Transaction } from 'kysely';
import type { Capacities } from '$lib/capacities';
import type { NeighbourIds, InsertionEvaluation } from '$lib/bookingAPI/insertions';
import type { ExpectedConnection } from '$lib/bookingApiParameters';
import type { DirectDurations } from './directDrivingDurations';
import type { Database } from '$lib/types';
import type { EventGroupUpdate } from './eventGroups';

export async function insertRequest(
	connection: InsertionEvaluation,
	capacities: Capacities,
	c: ExpectedConnection,
	customer: string,
	updateEventGroupList: EventGroupUpdate[],
	mergeTourList: number[],
	startEventGroup: string,
	targetEventGroup: string,
	neighbourIds: NeighbourIds,
	direct: DirectDurations,
	trx: Transaction<Database>
) {
	mergeTourList = mergeTourList.filter((id) => id != connection.tour);
	const approachDurations = new Array<{ id: number; approach_duration: number }>();
	if (neighbourIds.nextDropoff != neighbourIds.nextPickup && neighbourIds.nextPickup) {
		approachDurations.push({
			id: neighbourIds.nextPickup,
			approach_duration: connection.pickupReturnDuration
		});
	}
	if (neighbourIds.nextDropoff) {
		approachDurations.push({
			id: neighbourIds.nextDropoff,
			approach_duration: connection.dropoffReturnDuration
		});
	}

	const returnDurations = new Array<{ id: number; return_duration: number }>();
	if (neighbourIds.prevPickup) {
		returnDurations.push({
			id: neighbourIds.prevPickup,
			return_duration: connection.pickupApproachDuration
		});
	}
	if (neighbourIds.prevDropoff != neighbourIds.prevPickup && neighbourIds.prevDropoff) {
		returnDurations.push({
			id: neighbourIds.prevDropoff,
			return_duration: connection.dropoffApproachDuration
		});
	}
	await sql`
        CALL create_and_merge_tours(
            ROW(${capacities.passengers}, ${capacities.wheelchairs}, ${capacities.bikes}, ${capacities.luggage}),
            ROW(${true}, ${c.start.coordinates.lat}, ${c.start.coordinates.lng}, ${connection.pickupTime}, ${connection.pickupTime}, ${customer}, ${connection.pickupApproachDuration}, ${connection.pickupReturnDuration},${direct.pickup},${c.start.address},${startEventGroup}),
            ROW(${false}, ${c.target.coordinates.lat}, ${c.target.coordinates.lng}, ${connection.dropoffTime}, ${connection.dropoffTime}, ${customer}, ${connection.dropoffApproachDuration}, ${connection.dropoffReturnDuration},${direct.dropoff},${c.target.address},${targetEventGroup}),
            ${mergeTourList},
            ROW(${connection.departure}, ${connection.arrival}, ${connection.vehicle}, ${connection.tour}),
			${JSON.stringify(updateEventGroupList)}::jsonb,
			${JSON.stringify(returnDurations)}::jsonb,
			${JSON.stringify(approachDurations)}::jsonb,
			${JSON.stringify(direct.updates)}::jsonb
        )`.execute(trx);
}
//TODOS:
// communicated/scheduled times
