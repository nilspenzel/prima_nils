import { SCHEDULED_TIME_BUFFER } from '$lib/constants';
import type { Coordinates } from '$lib/util/Coordinates';
import { db } from '../db';
import { oneToManyCarRouting } from '../util/oneToManyCarRouting';

export const addRideShareTour = async (
	time: number,
	startFixed: boolean,
	passengers: number,
	luggage: number,
	provider: number,
	start: Coordinates,
	target: Coordinates
): Promise<number> => {
	const duration = (await oneToManyCarRouting(start, [target], false))[0]!;
	const startTime = startFixed ? time : time + duration;
	const endTime = startFixed ? time - duration : time;

	const tourId = (
		await db
			.insertInto('ride_share_tour')
			.values({
				passengers,
				luggage,
				fare: null,
				cancelled: false,
				message: null,
				provider,
				communicatedStartTime: startTime - SCHEDULED_TIME_BUFFER,
				communicatedEndTime: endTime + SCHEDULED_TIME_BUFFER,
				scheduledStartTime: startTime,
				scheduledEndTime: endTime
			})
			.returning('id')
			.executeTakeFirstOrThrow()
	).id;
	const requestId = (
		await db
			.insertInto('request')
			.values({
				passengers: 0,
				kidsZeroToTwo: 0,
				kidsThreeToFour: 0,
				kidsFiveToSix: 0,
				wheelchairs: 0,
				bikes: 0,
				luggage: 0,
				tour: null,
				rideShareTour: tourId,
				customer: provider,
				ticketCode: '',
				ticketChecked: false,
				ticketPrice: 300,
				cancelled: false
			})
			.returning('id')
			.execute()
	)[0].id;
	await db
		.insertInto('event')
		.values({
			isPickup: true,
			lat: start.lat,
			lng: start.lat,
			scheduledTimeStart: startTime - SCHEDULED_TIME_BUFFER,
			scheduledTimeEnd: startTime,
			communicatedTime: startTime - SCHEDULED_TIME_BUFFER,
			prevLegDuration: 0,
			nextLegDuration: duration,
			eventGroup: '',
			address: '',
			request: requestId,
			cancelled: false
		})
		.execute();
	await db
		.insertInto('event')
		.values({
			isPickup: false,
			lat: target.lat,
			lng: target.lat,
			scheduledTimeStart: endTime,
			scheduledTimeEnd: endTime + SCHEDULED_TIME_BUFFER,
			communicatedTime: endTime + SCHEDULED_TIME_BUFFER,
			prevLegDuration: duration,
			nextLegDuration: 0,
			eventGroup: '',
			address: '',
			request: requestId,
			cancelled: false
		})
		.execute();
	return tourId;
};
