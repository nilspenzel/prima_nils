import { db, type Database } from '$lib/server/db';
import type { Capacities } from '$lib/util/booking/Capacities';
import { retry } from '$lib/server/db/retryQuery';
import { DIRECT_FREQUENCY, DIRECT_RIDE_TIME_DIFFERENCE } from '$lib/constants';
import { bookSharedRide, type BookRideShareResponse } from './bookRide';
import { signEntry } from '../signEntry';
import { insertRideShareRequest } from './insertRideShareRequest';
import type { ExpectedConnection } from '$lib/server/booking/expectedConnection';
import type { Transaction } from 'kysely';

export type BookingParameters = {
	connection1: ExpectedConnection | null;
	connection2: ExpectedConnection | null;
	capacities: Capacities;
};

type BookingAttemptResult = {
	success: boolean;
	message: string;
	request1Id?: number;
	request2Id?: number;
};

const failedAttempt = (message: string): BookingAttemptResult => ({
	success: false,
	message
});

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
			false,
			c.tourId
				? JSON.stringify({
						tour: c.tourId,
						rT: c.requestedTime,
						pT: c.pickupTime,
						dT: c.dropoffTime
					})
				: undefined
		) !== c.signature
	);
}

function getPossibleRequestedTimes(rt: number): number[] {
	const possibleRequestedTimes = [];
	const earliestPossibleRequestedTime1 = rt - 2 * DIRECT_RIDE_TIME_DIFFERENCE;
	const latestPossibleRequestedTime1 = rt + 2 * DIRECT_RIDE_TIME_DIFFERENCE;
	for (
		let requestedTimeCandidate = rt;
		requestedTimeCandidate >= earliestPossibleRequestedTime1;
		requestedTimeCandidate -= DIRECT_FREQUENCY
	) {
		possibleRequestedTimes.push(requestedTimeCandidate);
	}
	for (
		let requestedTimeCandidate = rt;
		requestedTimeCandidate <= latestPossibleRequestedTime1;
		requestedTimeCandidate += DIRECT_FREQUENCY
	) {
		possibleRequestedTimes.push(requestedTimeCandidate);
	}
	return possibleRequestedTimes.sort((t1, t2) => Math.abs(t1 - rt) - Math.abs(t2 - rt));
}

export async function rideShareApi(
	p: BookingParameters,
	customer: number,
	isLocalhost: boolean,
	kidsZeroToTwo: number,
	kidsThreeToFour: number,
	kidsFiveToSix: number,
	skipPromiseCheck?: boolean,
	transaction?: Transaction<Database>
): Promise<{
	message?: string;
	status: number;
	request1Id?: number;
	request2Id?: number;
	cost?: number;
	passengerDuration?: number;
	approachPlusReturnDurationDelta?: number;
	fullyPayedDurationDelta?: number;
	waitingTime?: number;
}> {
	console.log(
		'RIDE SHARE API PARAMS: ',
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
		console.log(
			'Attempt to book with invalid signature.',
			JSON.stringify(p, null, 2),
			JSON.stringify(customer, null, 2),
			JSON.stringify(isLocalhost, null, 2),
			JSON.stringify(kidsZeroToTwo, null, 2),
			JSON.stringify(kidsThreeToFour, null, 2),
			JSON.stringify(kidsFiveToSix, null, 2),
			JSON.stringify(skipPromiseCheck, null, 2)
		);
		return { status: 403 };
	}
	let possibleRequestedTimes1: number[] = [];
	let possibleRequestedTimes2: number[] = [];
	let lastAttempt: BookingAttemptResult | undefined;
	if (p.connection1) {
		possibleRequestedTimes1 = getPossibleRequestedTimes(p.connection1.requestedTime);
	}
	if (p.connection2) {
		possibleRequestedTimes2 = getPossibleRequestedTimes(p.connection2.requestedTime);
	}
	const possibleRequestedTimes =
		possibleRequestedTimes1.length === 0 ? possibleRequestedTimes2 : possibleRequestedTimes1;
	for (const rt of possibleRequestedTimes) {
		const connection1 = p.connection1 === null ? null : { ...p.connection1 };
		const connection2 = p.connection2 === null ? null : { ...p.connection2 };
		if (connection2) {
			connection2.requestedTime = rt;
		} else {
			connection1!.requestedTime = rt;
		}
		const executeBooking = async (trx: Transaction<Database>): Promise<BookingAttemptResult> => {
			let firstConnection: undefined | BookRideShareResponse = undefined;
			let secondConnection: undefined | BookRideShareResponse = undefined;
			if (connection1 != null) {
				firstConnection = await bookSharedRide(connection1, p.capacities, trx, skipPromiseCheck);
				if (firstConnection == undefined) {
					return failedAttempt('Die Anfrage für die erste Meile kann nicht erfüllt werden.');
				}
			}
			if (connection2 != null) {
				let blockedProviderId: number | undefined = undefined;
				if (firstConnection != undefined) {
					blockedProviderId = firstConnection.best.tour;
				}
				secondConnection = await bookSharedRide(
					connection2,
					p.capacities,
					trx,
					skipPromiseCheck,
					blockedProviderId
				);
				if (secondConnection == undefined) {
					return failedAttempt('Die Anfrage für die zweite Meile kann nicht erfüllt werden.');
				}
			}
			const request1Id =
				firstConnection === undefined
					? undefined
					: await insertRideShareRequest(
							firstConnection,
							p.capacities,
							connection1!,
							customer,
							connection1!.startFixed ? connection1!.startTime : connection1!.targetTime,
							connection1!.requestedTime,
							connection1!.startFixed,
							trx
						);
			const request2Id =
				secondConnection === undefined
					? undefined
					: await insertRideShareRequest(
							secondConnection,
							p.capacities,
							connection2!,
							customer,
							connection2!.startFixed ? connection2!.startTime : connection2!.targetTime,
							connection2!.requestedTime,
							connection2!.startFixed,
							trx
						);
			return {
				success: true,
				message: 'Die Anfrage wurde erfolgreich bearbeitet.',
				request1Id,
				request2Id
			};
		};
		if (transaction) {
			lastAttempt = await executeBooking(transaction);
		} else {
			lastAttempt = await retry(() =>
				db.transaction().setIsolationLevel('serializable').execute(executeBooking)
			);
		}
		if (lastAttempt.success) {
			break;
		}
	}
	if (lastAttempt === undefined) {
		return { status: 500 };
	}
	return {
		message: lastAttempt.message,
		request1Id: lastAttempt.request1Id,
		request2Id: lastAttempt.request2Id,
		status: lastAttempt.success ? 200 : 400
	};
}
