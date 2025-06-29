import { db } from '$lib/server/db';
import {
	bookRide,
	type BookRideResponse,
	type ExpectedConnection
} from '$lib/server/rideShareBooking/bookRide';
import type { Capacities } from '$lib/util/booking/Capacities';
import { signEntry } from '$lib/server/rideShareBooking/signEntry';
import { insertRequest } from './insertRequest';
import { retry } from '../db/retryQuery';
import { PASSENGER_CHANGE_DURATION } from '$lib/constants';

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

export async function bookingApi(
	p: BookingParameters,
	customer: number,
	isLocalhost: boolean,
	skipPromiseCheck?: boolean
): Promise<{
	message?: string;
	status: number;
	request1Id?: number;
	request2Id?: number;
	communicatedPickup1?: number;
	communicatedDropoff1?: number;
	communicatedPickup2?: number;
	communicatedDropoff2?: number;
}> {
	console.log(
		'BOOKING API PARAMS: ',
		JSON.stringify(p, null, 2),
		JSON.stringify(customer, null, 2),
		JSON.stringify(isLocalhost, null, 2),
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
	let communicatedPickup1: number | undefined = undefined;
	let communicatedDropoff1: number | undefined = undefined;
	let communicatedPickup2: number | undefined = undefined;
	let communicatedDropoff2: number | undefined = undefined;
	let message: string | undefined = undefined;
	let success = false;
	await retry(() =>
		db
			.transaction()
			.setIsolationLevel('serializable')
			.execute(async (trx) => {
				let firstConnection: undefined | BookRideResponse = undefined;
				let secondConnection: undefined | BookRideResponse = undefined;
				if (p.connection1 != null) {
					firstConnection = await bookRide(p.connection1, p.capacities, trx, skipPromiseCheck);
					if (firstConnection == undefined) {
						message = 'Die Anfrage für die erste Meile kann nicht erfüllt werden.';
						return;
					}
				}
				if (p.connection2 != null) {
					secondConnection = await bookRide(p.connection2, p.capacities, trx, skipPromiseCheck);
					if (secondConnection == undefined) {
						message = 'Die Anfrage für die zweite Meile kann nicht erfüllt werden.';
						return;
					}
				}
				if (firstConnection != null) {
					request1Id =
						(await insertRequest(
							firstConnection.best,
							p.capacities,
							p.connection1!,
							customer,
							firstConnection.neighbourIds,
							firstConnection.scheduledTimes,
							trx
						)) ?? null;
					communicatedPickup1 = firstConnection.best.pickupTime - PASSENGER_CHANGE_DURATION;
					communicatedDropoff1 = firstConnection.best.dropoffTime + PASSENGER_CHANGE_DURATION;
				}
				if (secondConnection != null) {
					request2Id =
						(await insertRequest(
							secondConnection.best,
							p.capacities,
							p.connection2!,
							customer,
							secondConnection.neighbourIds,
							secondConnection.scheduledTimes,
							trx
						)) ?? null;
					communicatedPickup2 = secondConnection.best.pickupTime;
					communicatedDropoff2 = secondConnection.best.dropoffTime;
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
		communicatedPickup1,
		communicatedDropoff1,
		communicatedPickup2,
		communicatedDropoff2,
		status: success ? 200 : 400
	};
}
