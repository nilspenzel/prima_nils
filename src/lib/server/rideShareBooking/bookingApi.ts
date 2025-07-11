import { db } from '$lib/server/db';
import {
	bookSharedRide,
	type BookRideShareResponse,
	type ExpectedConnection
} from '$lib/server/rideShareBooking/bookRide';
import type { Capacities } from '$lib/util/booking/Capacities';
import { signEntry } from '$lib/server/rideShareBooking/signEntry';
import { insertRequest } from './insertRequest';
import { retry } from '../db/retryQuery';

export type BookingParameters = {
	connection1: ExpectedConnection | null;
	connection2: ExpectedConnection | null;
	capacities: Capacities;
};

function isSignatureInvalid(c: ExpectedConnection | null) {
	return (
		c !== null &&
		signEntry(
			c.start.lat,
			c.start.lng,
			c.target.lat,
			c.target.lng,
			c.startTime,
			c.targetTime,
			false
		) !== c.signature
	);
}

export async function rideShareApi(
	p: BookingParameters,
	customer: number,
	isLocalhost: boolean,
	kidsZeroToTwo: number,
	kidsThreeToFour: number,
	kidsFiveToSix: number,
	skipPromiseCheck?: boolean
): Promise<{
	message?: string;
	status: number;
	request1Id?: number;
	request2Id?: number;
	cost?: number;
	passengerDuration?: number;
	taxiTime?: number;
	waitingTime?: number;
}> {
	console.log(
		'BOOKING API PARAMS: ',
		JSON.stringify(p, null, 2),
		JSON.stringify(customer, null, 2),
		JSON.stringify(isLocalhost, null, 2),
		JSON.stringify(kidsZeroToTwo, null, 2),
		JSON.stringify(kidsThreeToFour, null, 2),
		JSON.stringify(kidsFiveToSix, null, 2),
		JSON.stringify(skipPromiseCheck, null, 2)
	);
	if (p.connection1 == null && p.connection2 == null) {
		return {
			message: 'Es wurde weder eine Anfrage für die erste noch für die letzte Meile gestellt.',
			status: 204
		};
	}
	if (!isLocalhost && (isSignatureInvalid(p.connection1) || isSignatureInvalid(p.connection2))) {
		return { status: 403 };
	}
	let request1Id: number | undefined = undefined;
	let request2Id: number | undefined = undefined;
	let message: string | undefined = undefined;
	let success = false;
	let cost = -1;
	let passengerDuration = -1;
	let waitingTime = -1;
	let taxiTime = -1;
	await retry(() =>
		db
			.transaction()
			.setIsolationLevel('serializable')
			.execute(async (trx) => {
				let firstConnection: undefined | BookRideShareResponse = undefined;
				let secondConnection: undefined | BookRideShareResponse = undefined;
				if (p.connection1 != null) {
					firstConnection = await bookSharedRide(
						p.connection1,
						p.capacities,
						trx,
						skipPromiseCheck
					);
					if (firstConnection == undefined) {
						message = 'Die Anfrage für die erste Meile kann nicht erfüllt werden.';
						return;
					}
					cost = firstConnection.best.cost;
					passengerDuration = firstConnection.best.passengerDuration;
					taxiTime = firstConnection.best.taxiDuration;
					waitingTime = firstConnection.best.taxiWaitingTime;
				}
				if (p.connection2 != null) {
					let blockedProviderId: number | undefined = undefined;
					if (firstConnection != undefined) {
						blockedProviderId = firstConnection.best.provider;
					}
					secondConnection = await bookSharedRide(
						p.connection2,
						p.capacities,
						trx,
						skipPromiseCheck,
						blockedProviderId
					);
					if (secondConnection == undefined) {
						message = 'Die Anfrage für die zweite Meile kann nicht erfüllt werden.';
						return;
					}
					cost = secondConnection.best.cost;
					passengerDuration = secondConnection.best.passengerDuration;
					taxiTime = secondConnection.best.taxiDuration;
					waitingTime = secondConnection.best.taxiWaitingTime;
				}
				if (firstConnection != null) {
					request1Id =
						(await insertRequest(
							firstConnection.best,
							p.capacities,
							p.connection1!,
							customer,
							firstConnection.scheduledTimes,
							trx
						)) ?? null;
				}
				if (secondConnection != null) {
					request2Id =
						(await insertRequest(
							secondConnection.best,
							p.capacities,
							p.connection2!,
							customer,
							secondConnection.scheduledTimes,
							trx
						)) ?? null;
				}
				message = 'Die Anfrage wurde erfolgreich bearbeitet.';
				success = true;
				return;
			})
	);
	if (message == undefined) {
		return { status: 500 };
	}
	return {
		message,
		request1Id,
		request2Id,
		status: success ? 200 : 400,
		cost,
		passengerDuration,
		waitingTime,
		taxiTime
	};
}
