import type { ExpectedConnection, ScheduledTimes } from '$lib/server/booking/bookRide';
import type { Capacities } from '$lib/util/booking/Capacities';
import type { DirectDrivingDurations } from '$lib/server/booking/getDirectDrivingDurations';
import type { EventGroupUpdate } from '$lib/server/booking/getEventGroupInfo';
import type { Insertion, NeighbourIds } from '$lib/server/booking/insertion';
import { type Database } from '$lib/server/db';
import { sql, Transaction } from 'kysely';
import { sendNotifications } from '$lib/server/firebase/notifications';
import { TourChange } from '$lib/server/firebase/firebase';
import { env } from '$env/dynamic/public';
import { exec } from 'child_process';
import path from 'path';
import { config } from 'dotenv';

config();

const BACKUP_DIR = './';

const dbUrl = 'postgresql://postgres:pw@localhost:6500/prima';
const dbUser = process.env.POSTGRES_USER;
const dbPassword = process.env.POSTGRES_PASSWORD;
const targetDatabase = process.env.POSTGRES_DB || 'prima';

console.log(`Starting full backup for database "${targetDatabase}"...`);
let counter = 0;

export async function insertRequest(
	connection: Insertion,
	capacities: Capacities,
	c: ExpectedConnection,
	customer: number,
	updateEventGroupList: EventGroupUpdate[],
	mergeTourList: number[],
	startEventGroup: string,
	targetEventGroup: string,
	neighbourIds: NeighbourIds,
	direct: DirectDrivingDurations,
	kidsZeroToTwo: number,
	kidsThreeToFour: number,
	kidsFiveToSix: number,
	scheduledTimes: ScheduledTimes,
	trx: Transaction<Database>
): Promise<number> {
	mergeTourList = mergeTourList.filter((id) => id != connection.tour);
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

	counter++;
	const timestamp = new Date().toISOString().replace(/[-T:.Z]/g, '_');
	const FILE_NAME = `full_backup_${timestamp}${counter}.sql`;
	const BACKUP_FILE_PATH = path.join(BACKUP_DIR, FILE_NAME);
	const command = `PGPASSWORD=${dbPassword} pg_dump --dbname=${dbUrl} --username=${dbUser} --no-password --format=plain --file="${BACKUP_FILE_PATH}"`;
	exec(command, (error, _, stderr) => {
		if (error) {
			console.error(`Error during backup: ${error.message}`);
			return;
		}
		if (stderr) {
			console.warn(`Backup stderr: ${stderr}`);
		}
		console.log(`Full backup successful! Backup saved to ${BACKUP_FILE_PATH}`);
	});
	const ticketPrice =
		(capacities.passengers - kidsZeroToTwo - kidsThreeToFour - kidsFiveToSix) *
		parseInt(env.PUBLIC_FIXED_PRICE);
	const requestId = (
		await sql<{ request: number }>`
        SELECT create_and_merge_tours(
            ROW(${capacities.passengers}, ${kidsZeroToTwo}, ${kidsThreeToFour}, ${kidsFiveToSix}, ${capacities.wheelchairs}, ${capacities.bikes}, ${capacities.luggage}, ${customer}, ${ticketPrice}),
            ROW(${true}, ${c.start.lat}, ${c.start.lng}, ${scheduledTimes.newPickupStartTime}, ${connection.pickupTime}, ${scheduledTimes.newPickupStartTime}, ${connection.pickupPrevLegDuration}, ${connection.pickupNextLegDuration}, ${c.start.address}, ${startEventGroup}),
            ROW(${false}, ${c.target.lat}, ${c.target.lng}, ${connection.dropoffTime}, ${scheduledTimes.newDropoffEndTime}, ${scheduledTimes.newDropoffEndTime}, ${connection.dropoffPrevLegDuration}, ${connection.dropoffNextLegDuration}, ${c.target.address}, ${targetEventGroup}),
            ${mergeTourList},
            ROW(${connection.departure}, ${connection.arrival}, ${connection.vehicle}, ${direct.thisTour?.directDrivingDuration ?? null}, ${connection.tour ?? null}),
            ${JSON.stringify(updateEventGroupList)}::jsonb,
            ${JSON.stringify(returnDurations)}::jsonb,
            ${JSON.stringify(approachDurations)}::jsonb,
            ROW(${direct.nextTour?.tourId ?? null}, ${direct.nextTour?.directDrivingDuration ?? null}),
            ROW(${direct.thisTour?.tourId ?? null}, ${direct.thisTour?.directDrivingDuration ?? null}),
			${JSON.stringify(scheduledTimes.updates)}::jsonb
       ) AS request`.execute(trx)
	).rows[0].request;

	const notificationParams = await trx
		.selectFrom('tour')
		.innerJoin('request', 'request.tour', 'tour.id')
		.innerJoin('vehicle', 'tour.vehicle', 'vehicle.id')
		.where('request.id', '=', requestId)
		.select(['tour.id as tourId', 'vehicle.company as companyId'])
		.executeTakeFirst();

	await sendNotifications(notificationParams!.companyId, {
		tourId: notificationParams!.tourId,
		pickupTime: connection.pickupTime,
		wheelchairs: capacities.wheelchairs,
		vehicleId: connection.vehicle,
		change: TourChange.BOOKED
	});

	return requestId;
}
