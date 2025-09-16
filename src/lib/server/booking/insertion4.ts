import { SCHEDULED_TIME_BUFFER_PICKUP, MAX_WAITING_TIME } from '$lib/constants';
import { type InsertionInfo, type InsertionType, printInsertionType } from './insertionTypes';
import { comesFromCompany, returnsToCompany } from './durations';
import type { PromisedTimes } from './PromisedTimes';
import { Interval } from '$lib/util/interval';
import type { Company, Event } from './getBookingAvailability';
import type { Capacities } from '$lib/util/booking/Capacities';
import { getScheduledEventTime } from '$lib/util/getScheduledEventTime';
import { iterateAllInsertions } from './iterateAllInsertions';
import { type Range } from '$lib/util/booking/getPossibleInsertions';
import { InsertHow } from '$lib/util/booking/insertionTypes';
import { getScheduledTimeBufferDropoff } from '$lib/util/getScheduledTimeBuffer';
import { computeCost } from './insertion';

type SingleInsertionEvaluation = {
	window: Interval;
	prevLegDuration: number;
	nextLegDuration: number;
	case: InsertionType;
	taxiWaitingTime: number;
	approachPlusReturnDurationDelta: number;
	fullyPayedDurationDelta: number;
	cost: number;
	prevId: number | undefined;
	nextId: number | undefined;
	idxInEvents: number;
	time: number;
};

export type InsertionEvaluation = {
	pickupTime: number;
	dropoffTime: number;
	scheduledPickupTimeStart: number;
	scheduledPickupTimeEnd: number;
	scheduledDropoffTimeStart: number;
	scheduledDropoffTimeEnd: number;
	pickupCase: InsertionType;
	dropoffCase: InsertionType;
	taxiWaitingTime: number;
	approachPlusReturnDurationDelta: number;
	fullyPayedDurationDelta: number;
	passengerDuration: number;
	cost: number;
	departure: number | undefined;
	arrival: number | undefined;
	pickupPrevLegDuration: number;
	pickupNextLegDuration: number;
	dropoffPrevLegDuration: number;
	dropoffNextLegDuration: number;
};

export type Insertion = InsertionEvaluation & {
	pickupIdx: number | undefined;
	dropoffIdx: number | undefined;
	company: number;
	vehicle: number;
	tour: number | undefined;
	prevPickupId: number | undefined;
	nextPickupId: number | undefined;
	prevDropoffId: number | undefined;
	nextDropoffId: number | undefined;
	pickupIdxInEvents: number | undefined;
	dropoffIdxInEvents: number | undefined;
};

type Times = {
	scheduledPickupTimeStart: number;
	scheduledPickupTimeEnd: number;
	scheduledDropoffTimeStart: number;
	scheduledDropoffTimeEnd: number;
};

type InsertionContext = {
	pickupIdx: number;
	dropoffIdx: number;
	prevPickup: Event | undefined;
	twoBeforePickup: Event | undefined;
	nextPickup: Event | undefined;
	prevDropoff: Event | undefined;
	nextDropoff: Event | undefined;
	twoAfterDropoff: Event | undefined;
};

export function evaluatePairInsertions(
	companies: Company[],
	startFixed: boolean,
	insertionRanges: Map<number, Range[]>,
	busStopTimes: Interval[][],
	busStopEvaluations: (SingleInsertionEvaluation | undefined)[][][],
	userChosenEvaluations: (SingleInsertionEvaluation | undefined)[],
	required: Capacities,
	whitelist?: boolean,
	promisedTimes?: PromisedTimes
): (Insertion | undefined)[][] {
	const bestEvaluations: (Insertion | undefined)[][] = new Array<(Insertion | undefined)[]>(
		busStopTimes.length
	);
	for (let i = 0; i != busStopTimes.length; ++i) {
		bestEvaluations[i] = new Array<Insertion | undefined>(busStopTimes[i].length);
	}
	iterateAllInsertions(companies, insertionRanges, (insertionInfo: InsertionInfo) => {
		const insertionIdx = insertionInfo.insertionIdx;
		const events = insertionInfo.vehicle.events;
		const pickupIdx = insertionInfo.idxInVehicleEvents;
		if (isInvalidPickupTransition(events, pickupIdx)) {
			return;
		}
		let cumulatedTaxiDrivingDelta = 0;
		for (
			let dropoffIdx = pickupIdx + 1;
			dropoffIdx != insertionInfo.currentRange.latestDropoff + 1;
			++dropoffIdx
		) {
			if (
				dropoffIdx > 1 &&
				dropoffIdx - 1 !== pickupIdx &&
				dropoffIdx != events.length &&
				events[dropoffIdx - 1].tourId != events[dropoffIdx - 2].tourId
			) {
				const drivingTime = events[dropoffIdx - 1].directDuration;
				if (drivingTime == null) {
					return;
				}
				cumulatedTaxiDrivingDelta +=
					drivingTime -
					events[dropoffIdx - 1].prevLegDuration -
					events[dropoffIdx - 2].nextLegDuration;
			}

			const context = buildInsertionContext(events, pickupIdx, dropoffIdx);

			for (let busStopIdx = 0; busStopIdx != busStopTimes.length; ++busStopIdx) {
				for (let timeIdx = 0; timeIdx != busStopTimes[busStopIdx].length; ++timeIdx) {
					const pickup = startFixed
						? busStopEvaluations[busStopIdx][timeIdx][insertionIdx]
						: userChosenEvaluations[insertionIdx];
					if (pickup == undefined) {
						continue;
					}
					const dropoff = startFixed
						? userChosenEvaluations[insertionIdx + dropoffIdx - pickupIdx]
						: busStopEvaluations[busStopIdx][timeIdx][insertionIdx + dropoffIdx - pickupIdx];
					if (dropoff == undefined) {
						continue;
					}

					const times = {
						...computePickupTimes(pickup, promisedTimes),
						...computeDropoffTimes(pickup, dropoff, promisedTimes)
					};
					if (
						!arePickupDropoffCompatible(
							pickupIdx,
							dropoffIdx,
							times,
							pickup,
							dropoff,
							events
						)
					) {
						continue;
					}

					const approachPlusReturnDurationDelta =
						pickup.approachPlusReturnDurationDelta + dropoff.approachPlusReturnDurationDelta;
					const fullyPayedDurationDelta =
						pickup.fullyPayedDurationDelta +
						dropoff.fullyPayedDurationDelta +
						cumulatedTaxiDrivingDelta;

					const relevantEvents = events.slice(
						pickup.case.how === InsertHow.CONNECT ? pickupIdx - 1 : pickupIdx,
						dropoff.case.how === InsertHow.CONNECT ? dropoffIdx + 1 : dropoffIdx
					);
					const taxiWaitingTime = computeWaitingTime(
						pickup,
						dropoff,
						times,
						approachPlusReturnDurationDelta + fullyPayedDurationDelta,
						context,
						relevantEvents
					);
					if (waitsTooLong(taxiWaitingTime)) {
						continue;
					}

					const weightedPassengerDuration = getWeightedPassengerDurationDelta(
						pickup,
						dropoff,
						times,
						context,
						required
					);

					const cost = computeCost(
						weightedPassengerDuration,
						approachPlusReturnDurationDelta,
						fullyPayedDurationDelta,
						taxiWaitingTime
					);

					console.log(
						whitelist ? 'WHITELIST' : 'BOOKING API',
						'valid insertion found,',
						'pickup: ',
						printInsertionType(pickup.case),
						'dropoff: ',
						printInsertionType(dropoff.case),
						{ prevPickupId: context.prevPickup?.id },
						{ nextPickupId: context.nextPickup?.id },
						{ prevDropoffId: context.prevDropoff?.id },
						{ nextDropoffId: context.nextDropoff?.id },
						{ cost },
						{ weightedPassengerDuration },
						{ taxiWaitingTime }
					);

					if (
						bestEvaluations[busStopIdx][timeIdx] == undefined ||
						cost < bestEvaluations[busStopIdx][timeIdx]!.cost
					) {
						const tour = events[pickupIdx].tourId;
						bestEvaluations[busStopIdx][timeIdx] = {
							pickupTime: times.scheduledPickupTimeEnd,
							dropoffTime: times.scheduledDropoffTimeStart,
							...times,
							pickupCase: pickup.case,
							dropoffCase: dropoff.case,
							pickupIdx,
							dropoffIdx,
							taxiWaitingTime,
							approachPlusReturnDurationDelta,
							fullyPayedDurationDelta,
							passengerDuration: weightedPassengerDuration,
							cost,
							company: insertionInfo.companyIdx,
							vehicle: insertionInfo.vehicle.id,
							tour,
							departure: comesFromCompany(pickup.case)
								? new Date(times.scheduledPickupTimeEnd - pickup.prevLegDuration).getTime()
								: undefined,
							arrival: returnsToCompany(dropoff.case)
								? new Date(times.scheduledDropoffTimeStart + dropoff.nextLegDuration).getTime()
								: undefined,
							pickupPrevLegDuration: pickup.prevLegDuration,
							pickupNextLegDuration: pickup.nextLegDuration,
							dropoffPrevLegDuration: dropoff.prevLegDuration,
							dropoffNextLegDuration: dropoff.nextLegDuration,
							prevPickupId: pickup.prevId,
							nextPickupId: pickup.nextId,
							prevDropoffId: dropoff.prevId,
							nextDropoffId: dropoff.nextId,
							pickupIdxInEvents: pickup.idxInEvents,
							dropoffIdxInEvents: dropoff.idxInEvents
						};
					}
				}
			}
		}
	});
	return bestEvaluations;
}

function buildInsertionContext(
	events: Event[],
	pickupIdx: number,
	dropoffIdx: number
): InsertionContext {
	return {
		pickupIdx,
		dropoffIdx,
		prevPickup: events[pickupIdx - 1],
		twoBeforePickup: events[pickupIdx - 2],
		nextPickup: events[pickupIdx],
		prevDropoff: events[dropoffIdx - 1],
		nextDropoff: events[dropoffIdx],
		twoAfterDropoff: events[dropoffIdx + 1]
	};
}

function getPassengerDurationSingleEvent(
	type: InsertionType,
	prev: Event | undefined,
	next: Event | undefined,
	prevShift: number,
	nextShift: number
) {
	const passengersEnteringInPrev = !comesFromCompany(type) && prev!.isPickup ? prev!.passengers : 0;
	const passengerExitingAtNext = !returnsToCompany(type) && !next!.isPickup ? next!.passengers : 0;
	return passengersEnteringInPrev * prevShift + passengerExitingAtNext * nextShift;
}

function getWeightedPassengerDurationDelta(
	pickup: SingleInsertionEvaluation,
	dropoff: SingleInsertionEvaluation,
	times: Times,
	context: InsertionContext,
	required: Capacities
) {
	let prevShiftPickup = 0;
	if (!comesFromCompany(pickup.case) && context.prevPickup!.isPickup) {
		prevShiftPickup = Math.max(
			0,
			getScheduledEventTime(context.prevPickup!) -
				times.scheduledPickupTimeEnd +
				pickup.prevLegDuration
		);
	}
	let nextShiftPickup = 0;
    console.log("blak", context.nextPickup)
	if (!returnsToCompany(pickup.case) && !context.nextPickup!.isPickup) {
		nextShiftPickup = Math.max(
			0,
			times.scheduledPickupTimeStart +
				pickup.nextLegDuration -
				getScheduledEventTime(context.nextPickup!)
		);
	}
	let prevShiftDropoff = 0;
	if (!comesFromCompany(dropoff.case) && context.prevDropoff!.isPickup) {
		prevShiftDropoff = Math.max(
			0,
			getScheduledEventTime(context.prevDropoff!) -
				times.scheduledDropoffTimeEnd +
				dropoff.prevLegDuration
		);
	}
	let nextShiftDropoff = 0;
	if (!returnsToCompany(dropoff.case) && !context.nextDropoff!.isPickup) {
		nextShiftDropoff = Math.max(
			0,
			times.scheduledDropoffTimeStart +
				dropoff.nextLegDuration -
				getScheduledEventTime(context.nextDropoff!)
		);
	}
	let weightedPassengerDuration =
		required.passengers * (times.scheduledDropoffTimeEnd - times.scheduledPickupTimeStart);
	weightedPassengerDuration += getPassengerDurationSingleEvent(
		pickup.case,
		context.prevPickup,
		context.nextPickup,
		prevShiftPickup,
		nextShiftPickup
	);
	weightedPassengerDuration += getPassengerDurationSingleEvent(
		dropoff.case,
		context.prevDropoff,
		context.nextDropoff,
		prevShiftDropoff,
		nextShiftDropoff
	);
	return weightedPassengerDuration;
}

function waitsTooLong(waitingTime: number) {
	return waitingTime > MAX_WAITING_TIME;
}

function computeWaitingTime(
	pickup: SingleInsertionEvaluation,
	dropoff: SingleInsertionEvaluation,
	times: Times,
	drivingDuration: number,
	context: InsertionContext,
	relevantEvents: Event[]
) {
	const tours = new Set<number>();
	let oldTourDurationSum = 0;
	relevantEvents.forEach((e) => {
		if (!tours.has(e.tourId)) {
			oldTourDurationSum += e.arrival - e.departure;
			tours.add(e.tourId);
		}
	});
	const newDeparture = comesFromCompany(pickup.case)
		? times.scheduledPickupTimeEnd - pickup.prevLegDuration
		: context.prevPickup!.tourId !== context.twoBeforePickup?.tourId
			? Math.min(
					times.scheduledPickupTimeStart - pickup.prevLegDuration,
					getScheduledEventTime(context.prevPickup!)
				) - context.prevPickup!.prevLegDuration
			: context.prevPickup!.departure;
	const newArrival = returnsToCompany(dropoff.case)
		? times.scheduledDropoffTimeStart + dropoff.nextLegDuration
		: context.nextDropoff!.tourId !== context.twoAfterDropoff?.tourId
			? Math.max(
					times.scheduledDropoffTimeEnd + dropoff.nextLegDuration,
					getScheduledEventTime(context.nextDropoff!)
				) + context.nextDropoff!.nextLegDuration
			: context.nextDropoff!.arrival;
	const tourDurationDelta = newArrival - newDeparture - oldTourDurationSum;
	const oldArrival = context.prevDropoff!.arrival;
	const oldDeparture = context.prevDropoff!.departure;
			console.log("toki12", oldTourDurationSum, new Date(newArrival).toISOString());
	return tourDurationDelta - drivingDuration;
}

function isInvalidPickupTransition(events: Event[], pickupIdx: number): boolean {
	const nextPickup = events[pickupIdx];
	const twoAfterPickup = events[pickupIdx + 1];
	return (
		pickupIdx < events.length - 1 &&
		nextPickup?.tourId !== twoAfterPickup?.tourId &&
		twoAfterPickup.scheduledTimeEnd -
			nextPickup.scheduledTimeStart -
			twoAfterPickup.directDuration! <
			0
	);
}

function arePickupDropoffCompatible(
	pickupIdx: number,
	dropoffIdx: number,
    times: Times,
	pickup: SingleInsertionEvaluation,
	dropoff: SingleInsertionEvaluation,
	events: Event[]
): boolean {
	const nextPickup = events[pickupIdx + 1];
	const prevDropoff = events[dropoffIdx - 1];
	if (dropoffIdx >= pickupIdx + 3) {
		return true;
	}
	let availableDistance =
		times.scheduledDropoffTimeStart -
		times.scheduledPickupTimeEnd -
		dropoff.prevLegDuration -
		pickup.nextLegDuration;
	if (pickupIdx + 2 === dropoffIdx) {
		availableDistance -=
			nextPickup.tourId !== prevDropoff.tourId
				? (prevDropoff.directDuration ?? Number.MAX_SAFE_INTEGER / 2)
				: prevDropoff.prevLegDuration;
	}
	if (availableDistance - 2 < 0) {
		return false;
	}
	return true;
}

function computePickupTimes(pickup: SingleInsertionEvaluation, promisedTimes?: PromisedTimes) {
	const scheduledPickupTimeEnd =
		promisedTimes !== undefined
			? promisedTimes.pickup
			: Math.min(pickup.window.startTime + SCHEDULED_TIME_BUFFER_PICKUP, pickup.window.endTime);
	const scheduledPickupTimeStart = Math.max(
		pickup.window.startTime,
		scheduledPickupTimeEnd - SCHEDULED_TIME_BUFFER_PICKUP
	);
	return { scheduledPickupTimeStart, scheduledPickupTimeEnd };
}

function computeDropoffTimes(
	pickup: SingleInsertionEvaluation,
	dropoff: SingleInsertionEvaluation,
	promisedTimes?: PromisedTimes
) {
	const scheduledDropoffTimeStart =
		promisedTimes !== undefined
			? promisedTimes.dropoff
			: Math.max(
					dropoff.window.endTime -
						getScheduledTimeBufferDropoff(dropoff.window.startTime - pickup.window.endTime),
					dropoff.window.startTime
				);
	const scheduledDropoffTimeEnd = Math.min(
		scheduledDropoffTimeStart +
			getScheduledTimeBufferDropoff(dropoff.window.startTime - pickup.window.endTime),
		dropoff.window.endTime
	);
	return { scheduledDropoffTimeStart, scheduledDropoffTimeEnd };
}
