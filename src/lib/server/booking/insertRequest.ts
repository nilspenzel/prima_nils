import type { ExpectedConnection } from '$lib/server/booking/bookRide';
import type { Capacities } from '$lib/util/booking/Capacities';
import type { DirectDrivingDurations } from '$lib/server/booking/getDirectDrivingDurations';
import type { Insertion, NeighbourIds } from '$lib/server/booking/insertion';
import { type Database } from '$lib/server/db';
import { sql, Transaction } from 'kysely';
import { sendNotifications } from '$lib/server/firebase/notifications';
import { TourChange } from '$lib/server/firebase/firebase';
import { env } from '$env/dynamic/public';
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

export async function insertRequest(
	connection: Insertion,
	capacities: Capacities,
	c: ExpectedConnection,
	customer: number,
	mergeTourList: number[],
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

	const ticketPrice =
		(capacities.passengers - kidsZeroToTwo - kidsThreeToFour - kidsFiveToSix) *
		parseInt(env.PUBLIC_FIXED_PRICE);
	const requestId = (
		await sql<{ request: number }>`
        SELECT create_and_merge_tours(
            ROW(${capacities.passengers}, ${kidsZeroToTwo}, ${kidsThreeToFour}, ${kidsFiveToSix}, ${capacities.wheelchairs}, ${capacities.bikes}, ${capacities.luggage}, ${customer}, ${ticketPrice}),
            ROW(${true}, ${c.start.lat}, ${c.start.lng}, ${scheduledTimes.newPickupStartTime}, ${connection.pickupTime}, ${scheduledTimes.newPickupStartTime}, ${connection.pickupPrevLegDuration}, ${connection.pickupNextLegDuration}, ${c.start.address}, ${''}),
            ROW(${false}, ${c.target.lat}, ${c.target.lng}, ${connection.dropoffTime}, ${scheduledTimes.newDropoffEndTime}, ${scheduledTimes.newDropoffEndTime}, ${connection.dropoffPrevLegDuration}, ${connection.dropoffNextLegDuration}, ${c.target.address}, ${''}),
            ${mergeTourList},
            ROW(${connection.departure ?? null}, ${connection.arrival ?? null}, ${connection.vehicle}, ${direct.thisTour?.directDrivingDuration ?? null}, ${connection.tour ?? null}),
            ${JSON.stringify(returnDurations)}::jsonb,
            ${JSON.stringify(approachDurations)}::jsonb,
            ROW(${direct.nextTour?.tourId ?? null}, ${direct.nextTour?.directDrivingDuration ?? null}),
            ROW(${direct.thisTour?.tourId ?? null}, ${direct.thisTour?.directDrivingDuration ?? null}),
			${JSON.stringify(scheduledTimes.updates)}::jsonb,
			${JSON.stringify(prevLegDurations)}::jsonb,
			${JSON.stringify(nextLegDurations)}::jsonb
       ) AS request`.execute(trx)
	).rows[0].request;

	if (bookingApiParameters.isLocalhost) {
		await trx
			.insertInto('bookingApiParameters')
			.values({
				startLat1: bookingApiParameters.p.connection1?.start.lat ?? null,
				startLng1: bookingApiParameters.p.connection1?.start.lat ?? null,
				targetLat1: bookingApiParameters.p.connection1?.target.lat,
				targetLng1: bookingApiParameters.p.connection1?.target.lng,
				startTime1: bookingApiParameters.p.connection1?.startTime,
				targetTime1: bookingApiParameters.p.connection1?.targetTime,
				startAddress1: bookingApiParameters.p.connection1?.start.address,
				targetAddress1: bookingApiParameters.p.connection1?.target.address,
				startFixed1: bookingApiParameters.p.connection1?.startFixed,
				startLat2: bookingApiParameters.p.connection2?.start.lat,
				startLng2: bookingApiParameters.p.connection2?.start.lng,
				targetLat2: bookingApiParameters.p.connection2?.target.lat,
				targetLng2: bookingApiParameters.p.connection2?.target.lng,
				startTime2: bookingApiParameters.p.connection2?.startTime,
				targetTime2: bookingApiParameters.p.connection2?.targetTime,
				startAddress2: bookingApiParameters.p.connection2?.start.address,
				targetAddress2: bookingApiParameters.p.connection2?.target.address,
				startFixed2: bookingApiParameters.p.connection2?.startFixed,
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
