import { db, type Database } from '$lib/server/db';
import { bookRide, type BookRideResponse } from '$lib/server/booking/taxi/bookRide';
import type { ExpectedConnection } from '$lib/server/booking/expectedConnection';
import type { Capacities } from '$lib/util/booking/Capacities';
import { signEntry } from '$lib/server/booking/signEntry';
import { insertRequest } from './insertRequest';
import { retry } from '$lib/server/db/retryQuery';
import { DIRECT_FREQUENCY, DIRECT_RIDE_TIME_DIFFERENCE } from '$lib/constants';
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
	cost: number;
	passengerDuration: number;
	waitingTime: number;
	approachPlusReturnDurationDelta: number;
	fullyPayedDurationDelta: number;
};

const failedAttempt = (message: string): BookingAttemptResult => ({
	success: false,
	message,
	cost: -1,
	passengerDuration: -1,
	waitingTime: -1,
	approachPlusReturnDurationDelta: -1,
	fullyPayedDurationDelta: -1
});

const getCommonTour = (l1: number[], l2: number[]) => {
	for (const e of l1) {
		if (l2.find((l) => l === e)) {
			return e;
		}
	}
	return undefined;
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
			false,
			undefined
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

export async function bookingApi(
	p: BookingParameters,
	customer: number,
	withoutQr: boolean,
	isLocalhost: boolean,
	kidsZeroToTwo: number,
	kidsThreeToFour: number,
	kidsFiveToSix: number,
	kidsSevenToFourteen: number,
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
		'BOOKING API PARAMS: ',
		JSON.stringify(p, null, 2),
		JSON.stringify(customer, null, 2),
		JSON.stringify(isLocalhost, null, 2),
		JSON.stringify(kidsZeroToTwo, null, 2),
		JSON.stringify(kidsThreeToFour, null, 2),
		JSON.stringify(kidsFiveToSix, null, 2),
		JSON.stringify(kidsSevenToFourteen, null, 2),
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
		if (p.connection2) {
			p.connection2!.requestedTime = rt;
		} else {
			p.connection1!.requestedTime = rt;
		}
		const executeBooking = async (trx: Transaction<Database>): Promise<BookingAttemptResult> => {
			let firstConnection: undefined | BookRideResponse = undefined;
			let secondConnection: undefined | BookRideResponse = undefined;
			if (p.connection1 != null) {
				firstConnection = await bookRide(p.connection1, p.capacities, trx, skipPromiseCheck);
				if (firstConnection == undefined) {
					return failedAttempt('Die Anfrage für die erste Meile kann nicht erfüllt werden.');
				}
			}
			if (p.connection2 != null) {
				let blockedVehicleId: number | undefined = undefined;
				if (firstConnection != undefined) {
					blockedVehicleId = firstConnection.best.vehicle;
				}
				secondConnection = await bookRide(
					p.connection2,
					p.capacities,
					trx,
					skipPromiseCheck,
					blockedVehicleId
				);
				if (secondConnection == undefined) {
					return failedAttempt('Die Anfrage für die zweite Meile kann nicht erfüllt werden.');
				}
			}
			if (
				p.connection1 != null &&
				p.connection2 != null &&
				firstConnection!.tour != undefined &&
				secondConnection!.tour != undefined
			) {
				const newTour = getCommonTour(
					firstConnection!.mergeTourList,
					secondConnection!.mergeTourList
				);
				if (newTour != undefined) {
					firstConnection!.tour = newTour;
					secondConnection!.tour = newTour;
				}
			}
			const request1Id =
				firstConnection === undefined
					? undefined
					: await insertRequest(
							firstConnection,
							p.capacities,
							p.connection1!,
							customer,
							withoutQr,
							kidsZeroToTwo,
							kidsThreeToFour,
							kidsFiveToSix,
							kidsSevenToFourteen,
							trx
						);
			const request2Id =
				secondConnection === undefined
					? undefined
					: await insertRequest(
							secondConnection,
							p.capacities,
							p.connection2!,
							customer,
							withoutQr,
							kidsZeroToTwo,
							kidsThreeToFour,
							kidsFiveToSix,
							kidsSevenToFourteen,
							trx
						);
			const result = secondConnection ?? firstConnection!;
			return {
				success: true,
				message: 'Die Anfrage wurde erfolgreich bearbeitet.',
				request1Id,
				request2Id,
				cost: result.best.cost,
				passengerDuration: result.best.passengerDuration,
				waitingTime: result.best.taxiWaitingTime,
				approachPlusReturnDurationDelta: result.best.approachPlusReturnDurationDelta,
				fullyPayedDurationDelta: result.best.fullyPayedDurationDelta
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
		status: lastAttempt.success ? 200 : 400,
		cost: lastAttempt.cost,
		passengerDuration: lastAttempt.passengerDuration,
		waitingTime: lastAttempt.waitingTime,
		approachPlusReturnDurationDelta: lastAttempt.approachPlusReturnDurationDelta,
		fullyPayedDurationDelta: lastAttempt.fullyPayedDurationDelta
	};
}
