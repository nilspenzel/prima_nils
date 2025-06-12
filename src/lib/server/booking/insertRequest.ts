import type { ExpectedConnection } from '$lib/server/booking/bookRide';
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
import type { ScheduledTimes } from './getScheduledTimes';
import type { BookingParameters } from './bookingApi';

export type BookingApiParameters = {
	p: BookingParameters;
	customer: number;
	isLocalhost: boolean;
	kidsZeroToTwo: number;
	kidsThreeToFour: number;
	kidsFiveToSix: number;
};

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
	prevLegDurations: { event: number; duration: number | null }[],
	nextLegDurations: { event: number; duration: number | null }[],
	kidsZeroToTwo: number,
	kidsThreeToFour: number,
	kidsFiveToSix: number,
	scheduledTimes: ScheduledTimes,
	bookingApiParameters: BookingApiParameters,
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
			${JSON.stringify(scheduledTimes.updates)}::jsonb,
			${JSON.stringify(prevLegDurations)}::jsonb,
			${JSON.stringify(nextLegDurations)}::jsonb
       ) AS request`.execute(trx)
	).rows[0].request;

	if (bookingApiParameters.isLocalhost && bookingApiParameters.kidsFiveToSix === -5) {
		trx
			.insertInto('bookingApiParameters')
			.values({
				start_lat1: bookingApiParameters.p.connection1?.start.lat ?? null,
				start_lng1: bookingApiParameters.p.connection1?.start.lat ?? null,
				target_lat1: bookingApiParameters.p.connection1?.target.lat,
				target_lng1: bookingApiParameters.p.connection1?.target.lng,
				start_time1: bookingApiParameters.p.connection1?.startTime,
				target_time1: bookingApiParameters.p.connection1?.targetTime,
				start_address1: bookingApiParameters.p.connection1?.start.address,
				target_address1: bookingApiParameters.p.connection1?.target.address,
				start_fixed1: bookingApiParameters.p.connection1?.startFixed,
				start_lat2: bookingApiParameters.p.connection2?.start.lat,
				start_lng2: bookingApiParameters.p.connection2?.start.lng,
				target_lat2: bookingApiParameters.p.connection2?.target.lat,
				target_lng2: bookingApiParameters.p.connection2?.target.lng,
				start_time2: bookingApiParameters.p.connection2?.startTime,
				target_time2: bookingApiParameters.p.connection2?.targetTime,
				start_address2: bookingApiParameters.p.connection2?.start.address,
				target_address2: bookingApiParameters.p.connection2?.target.address,
				start_fixed2: bookingApiParameters.p.connection2?.startFixed,
				kidsZeroToTwo: bookingApiParameters.kidsZeroToTwo,
				kidsThreeToFour: bookingApiParameters.kidsThreeToFour,
				kidsFiveToSix: bookingApiParameters.kidsFiveToSix,
				passengers: bookingApiParameters.p.capacities.passengers,
				wheelchairs: bookingApiParameters.p.capacities.wheelchairs,
				bikes: bookingApiParameters.p.capacities.bikes,
				luggage: bookingApiParameters.p.capacities.luggage
			})
			.execute();
	}

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
