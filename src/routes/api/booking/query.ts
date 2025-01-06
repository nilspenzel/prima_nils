import { sql, Transaction } from 'kysely';
import type { Capacities } from '$lib/capacities';
import type { InsertionEvaluation, NeighbourIds } from '$lib/bookingAPI/insertions';
import type { ExpectedConnection } from '$lib/bookingApiParameters';
import type { EventGroupUpdateList } from './booking';
import type { Database } from '$lib/types';

export async function insertRequest(
	connection: InsertionEvaluation,
	capacities: Capacities,
	c: ExpectedConnection,
	customer: string,
	updateEventGroupList: EventGroupUpdateList,
	mergeTourList: number[],
	startEventGroup: string,
	targetEventGroup: string,
	neighbourIds: NeighbourIds,
	trx: Transaction<Database>
) {
	console.log(neighbourIds.prevPickup ?? -1);
	console.log(connection.pickupApproachDuration);
	console.log((neighbourIds.nextDropoff == neighbourIds.nextPickup ? -1 : neighbourIds.nextPickup) ?? -1);
	console.log(connection.pickupReturnDuration);
	console.log((neighbourIds.prevDropoff == neighbourIds.prevPickup ? -1 : neighbourIds.prevDropoff) ?? -1);
	console.log(connection.dropoffApproachDuration);
	console.log(neighbourIds.nextDropoff ?? -1);
	console.log(connection.dropoffReturnDuration);
	mergeTourList = mergeTourList.filter((id) => id != connection.tour);
	await sql`
        CALL create_and_merge_tours(
            ROW(${capacities.passengers}, ${capacities.wheelchairs}, ${capacities.bikes}, ${capacities.luggage}),
            ROW(${true}, ${c.start.coordinates.lat}, ${c.start.coordinates.lng}, ${connection.pickupTime}, ${connection.pickupTime}, ${customer}, ${connection.pickupApproachDuration}, ${connection.pickupReturnDuration},${c.start.address},${startEventGroup}),
            ROW(${false}, ${c.target.coordinates.lat}, ${c.target.coordinates.lng}, ${connection.dropoffTime}, ${connection.dropoffTime}, ${customer}, ${connection.dropoffApproachDuration}, ${connection.dropoffReturnDuration},${c.target.address},${targetEventGroup}),
            ${mergeTourList},
			${updateEventGroupList.ids},
			${updateEventGroupList.updates},
            ROW(${connection.departure}, ${connection.arrival}, ${connection.vehicle}, ${connection.tour}),
			${neighbourIds.prevPickup ?? -1},
			${connection.pickupApproachDuration},
			${(neighbourIds.nextDropoff == neighbourIds.nextPickup ? -1 : neighbourIds.nextPickup) ?? -1},
			${connection.pickupReturnDuration},
			${(neighbourIds.prevDropoff == neighbourIds.prevPickup ? -1 : neighbourIds.prevDropoff) ?? -1},
			${connection.dropoffApproachDuration},
			${neighbourIds.nextDropoff ?? -1},
			${connection.dropoffReturnDuration}
        )`.execute(trx);
}
//TODOS:
// communicated/scheduled times
// approach/return duration
