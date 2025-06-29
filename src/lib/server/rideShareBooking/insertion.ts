import {
	MIN_PREP,
	PASSENGER_TIME_COST_FACTOR,
	TAXI_DRIVING_TIME_COST_FACTOR,
	TAXI_WAITING_TIME_COST_FACTOR
} from '$lib/constants';
import {
	InsertDirection,
	type InsertionInfo,
	type InsertionType,
	isEarlierBetter,
	printInsertionType
} from './insertionTypes';
import {
	getAllowedOperationTimes,
	getPrevLegDuration,
	getArrivalWindow,
	getNextLegDuration
} from './durations';
import type { PromisedTimes } from './PromisedTimes';
import { Interval } from '$lib/util/interval';
import type { RoutingResults } from './routing';
import type { Capacities } from '$lib/util/booking/Capacities';
import { getScheduledEventTime } from '$lib/util/getScheduledEventTime';
import { roundToUnit, MINUTE } from '$lib/util/time';
import { iterateAllInsertions } from './iterateAllInsertions';
import { type Range } from '$lib/util/booking/getPossibleInsertions';
import { InsertWhat } from '$lib/util/booking/insertionTypes';
import { bookingLogs, iteration } from '$lib/testHelpers';
import type { RideShareEvent, RideShareTour } from './getBookingAvailability';

export type InsertionEvaluation = {
	pickupTime: number;
	dropoffTime: number;
	pickupCase: InsertionType;
	dropoffCase: InsertionType;
	taxiWaitingTime: number;
	taxiDuration: number;
	passengerDuration: number;
	cost: number;
	pickupPrevLegDuration: number;
	pickupNextLegDuration: number;
	dropoffPrevLegDuration: number;
	dropoffNextLegDuration: number;
};

export type Insertion = InsertionEvaluation & {
	pickupIdx: number;
	dropoffIdx: number;
	tour: number;
	prevPickupId: number;
	nextPickupId: number;
	prevDropoffId: number;
	nextDropoffId: number;
	pickupIdxInEvents: number;
	dropoffIdxInEvents: number;
};

type SingleInsertionEvaluation = {
	time: number;
	window: Interval;
	approachDuration: number;
	returnDuration: number;
	case: InsertionType;
	taxiWaitingTime: number;
	taxiDuration: number;
	passengerDuration: number;
	cost: number;
	prevId: number;
	nextId: number;
	idxInEvents: number;
};

type Evaluations = {
	busStopEvaluations: (SingleInsertionEvaluation | undefined)[][][];
	userChosenEvaluations: (SingleInsertionEvaluation | undefined)[];
	bothEvaluations: (Insertion | undefined)[][];
};

export type NeighbourIds = {
	prevPickup: number | undefined;
	nextPickup: number | undefined;
	prevDropoff: number | undefined;
	nextDropoff: number | undefined;
};

export function toInsertionWithISOStrings(i: Insertion | undefined) {
	return i === undefined
		? undefined
		: {
				...i,
				pickupTime: new Date(i.pickupTime).toISOString(),
				dropoffTime: new Date(i.dropoffTime).toISOString()
			};
}

export function printInsertionEvaluation(e: Insertion) {
	return (
		'pickupTime: ' +
		new Date(e.pickupTime).toISOString() +
		'\n' +
		'dropoffTime: ' +
		new Date(e.dropoffTime).toISOString() +
		'\n' +
		'pickupCase: ' +
		printInsertionType(e.pickupCase) +
		'\n' +
		'dropoffCase: ' +
		printInsertionType(e.dropoffCase) +
		'\n' +
		'taxiWaitingTime: ' +
		e.taxiWaitingTime +
		'\n' +
		'taxiDuration: ' +
		e.taxiDuration +
		'\n' +
		'passengerDuration: ' +
		e.passengerDuration +
		'\n' +
		'cost: ' +
		e.cost +
		'\n' +
		'tour: ' +
		e.tour +
		'\n' +
		'pickupprevLegDuration: ' +
		e.pickupPrevLegDuration +
		'\n' +
		'pickupnextLegDuration: ' +
		e.pickupNextLegDuration +
		'\n' +
		'dropoffprevLegDuration: ' +
		e.dropoffPrevLegDuration +
		'\n' +
		'dropoffnextLegDuration: ' +
		e.dropoffNextLegDuration +
		'\n'
	);
}

export function evaluateSingleInsertion(
	insertionCase: InsertionType,
	window: Interval,
	busStopWindow: Interval | undefined,
	routingResults: RoutingResults,
	insertionInfo: InsertionInfo,
	busStopIdx: number | undefined,
	prev: RideShareEvent,
	next: RideShareEvent,
	allowedTimes: Interval[],
	promisedTimes?: PromisedTimes
): SingleInsertionEvaluation | undefined {
	console.assert(insertionCase.what != InsertWhat.BOTH);
	const prevLegDuration = getPrevLegDuration(
		insertionCase,
		routingResults,
		insertionInfo,
		busStopIdx
	);
	const nextLegDuration = getNextLegDuration(
		insertionCase,
		routingResults,
		insertionInfo,
		busStopIdx
	);
	if (prevLegDuration == undefined || nextLegDuration == undefined) {
		return undefined;
	}
	const arrivalWindow = getArrivalWindow(
		insertionCase,
		window,
		0,
		busStopWindow,
		prevLegDuration,
		nextLegDuration,
		allowedTimes
	);
	if (arrivalWindow == undefined) {
		return undefined;
	}
	const passengerDuration =
		(insertionCase.what == InsertWhat.BUS_STOP) ==
		(insertionCase.direction == InsertDirection.BUS_STOP_PICKUP)
			? nextLegDuration
			: prevLegDuration;
	if (
		promisedTimes != undefined &&
		!keepsPromises(insertionCase, arrivalWindow, passengerDuration, promisedTimes)
	) {
		return undefined;
	}
	const taxiDuration = prevLegDuration + nextLegDuration - getOldDrivingTime(prev, next);
	console.assert(insertionCase.what != InsertWhat.BOTH);
	const time = isEarlierBetter(insertionCase) ? arrivalWindow.startTime : arrivalWindow.endTime;
	const taxiWaitingTime = getTaxiWaitingDelta(prevLegDuration + nextLegDuration, prev, next);
	const sie: SingleInsertionEvaluation = {
		time,
		window: arrivalWindow,
		approachDuration: prevLegDuration,
		returnDuration: nextLegDuration,
		case: structuredClone(insertionCase),
		passengerDuration,
		taxiDuration,
		taxiWaitingTime,
		cost: computeCost(passengerDuration, taxiDuration, taxiWaitingTime),
		prevId: prev.eventId,
		nextId: next.eventId,
		idxInEvents: insertionInfo.idxInTourEvents
	};
	return sie;
}

export function evaluateBothInsertion(
	insertionCase: InsertionType,
	window: Interval,
	passengerDuration: number | undefined,
	busStopWindow: Interval | undefined,
	routingResults: RoutingResults,
	insertionInfo: InsertionInfo,
	busStopIdx: number | undefined,
	prev: RideShareEvent,
	next: RideShareEvent,
	allowedTimes: Interval[],
	passengerCountBeforePrev: number,
	passengerCountNewRequest: number,
	promisedTimes?: PromisedTimes
): InsertionEvaluation | undefined {
	console.log(
		promisedTimes === undefined ? 'WHITELIST' : 'BOOKING API',
		'start of bothevaluation',
		printInsertionType(insertionCase)
	);
	console.assert(
		insertionCase.what == InsertWhat.BOTH,
		'Not inserting both in evaluateBothInsertion.'
	);
	const prevLegDuration = getPrevLegDuration(
		insertionCase,
		routingResults,
		insertionInfo,
		busStopIdx
	);
	const nextLegDuration = getNextLegDuration(
		insertionCase,
		routingResults,
		insertionInfo,
		busStopIdx
	);
	if (
		prevLegDuration == undefined ||
		nextLegDuration == undefined ||
		passengerDuration == undefined
	) {
		console.log('duration undefined: ', prevLegDuration, nextLegDuration, passengerDuration);
		return undefined;
	}
	const arrivalWindow = getArrivalWindow(
		insertionCase,
		window,
		passengerDuration,
		busStopWindow,
		prevLegDuration,
		nextLegDuration,
		allowedTimes
	);
	if (arrivalWindow == undefined) {
		console.log(
			promisedTimes === undefined ? 'WHITELIST' : 'BOOKING API',
			'arrival window undefined',
			printInsertionType(insertionCase),
			{ window: window.toString() },
			{ passengerDuration: passengerDuration.toString() },
			{ busStopWindow: busStopWindow?.toString() },
			{ prevLegDuration: prevLegDuration.toString() },
			{ nextLegDuration: nextLegDuration.toString() },
			{ allowedTimes: allowedTimes.toString() }
		);
		return undefined;
	}
	if (
		promisedTimes != undefined &&
		!keepsPromises(insertionCase, arrivalWindow, passengerDuration, promisedTimes)
	) {
		console.log('promise not kept', promisedTimes);
		return undefined;
	}
	const taxiDuration =
		prevLegDuration + nextLegDuration + passengerDuration - getOldDrivingTime(prev, next);

	const pickupTime =
		insertionCase.direction == InsertDirection.BUS_STOP_PICKUP
			? arrivalWindow.startTime
			: arrivalWindow.endTime - passengerDuration;
	const dropoffTime =
		insertionCase.direction == InsertDirection.BUS_STOP_PICKUP
			? arrivalWindow.startTime + passengerDuration
			: arrivalWindow.endTime;

	const passengerCountAfterPrev = prev
		? passengerCountBeforePrev + (prev.isPickup ? prev.passengers : -prev.passengers)
		: 0;
	let weightedPassengerDuration =
		(passengerCountAfterPrev + passengerCountNewRequest) * (dropoffTime - pickupTime);
	if (next && prev) {
		const passengerCountAfterNext =
			passengerCountAfterPrev + (next.isPickup ? prev.passengers : -prev.passengers);
		const existingPassengerTimeOld = getScheduledEventTime(next) - getScheduledEventTime(prev);
		const newPrevTime = prev.isPickup ? pickupTime - prevLegDuration : getScheduledEventTime(prev);
		const newNextTime = next.isPickup ? getScheduledEventTime(next) : dropoffTime + nextLegDuration;
		const existingPassengerTimeNew = newNextTime - newPrevTime;
		const additionalWeightedTimeExistingPasengers =
			passengerCountAfterPrev * (existingPassengerTimeNew - existingPassengerTimeOld) -
			passengerCountBeforePrev * (getScheduledEventTime(prev) - newPrevTime) -
			passengerCountAfterNext * (newNextTime - getScheduledEventTime(next));
		weightedPassengerDuration += additionalWeightedTimeExistingPasengers;
	}
	const taxiWaitingTime = getTaxiWaitingDelta(
		prevLegDuration + nextLegDuration + passengerDuration,
		prev,
		next
	);
	bookingLogs.push({
		type: printInsertionType(insertionCase),
		prevEvent: prev.eventId,
		nextEvent: next.eventId,
		prevLegDuration,
		nextLegDuration,
		cost: computeCost(passengerDuration, taxiDuration, taxiWaitingTime),
		iter: iteration,
		waitingTime: taxiWaitingTime,
		taxiDuration,
		oldDrivingTime: getOldDrivingTime(prev, next),
		passengerDuration: passengerDuration,
		weightedPassengerDuration
	});
	console.log(
		promisedTimes === undefined ? 'WHITELIST' : 'BOOKING API',
		'bothevaluation',
		printInsertionType(insertionCase),
		{ pickupTime: pickupTime.toString() },
		{ dropoffTime: dropoffTime.toString() }
	);
	return {
		pickupTime,
		dropoffTime,
		pickupCase: structuredClone(insertionCase),
		dropoffCase: structuredClone(insertionCase),
		passengerDuration,
		taxiDuration,
		taxiWaitingTime,
		cost: computeCost(weightedPassengerDuration, taxiDuration, taxiWaitingTime),
		pickupPrevLegDuration: prevLegDuration,
		pickupNextLegDuration: passengerDuration,
		dropoffPrevLegDuration: passengerDuration,
		dropoffNextLegDuration: nextLegDuration
	};
}

export function evaluateSingleInsertions(
	tours: RideShareTour[],
	required: Capacities,
	startFixed: boolean,
	expandedSearchInterval: Interval,
	insertionRanges: Map<number, Range[]>,
	busStopTimes: Interval[][],
	routingResults: RoutingResults,
	travelDurations: (number | undefined)[],
	allowedTimes: Interval[],
	promisedTimes?: PromisedTimes
): Evaluations {
	const bothEvaluations: (Insertion | undefined)[][] = [];
	const userChosenEvaluations: (SingleInsertionEvaluation | undefined)[] = [];
	const busStopEvaluations: (SingleInsertionEvaluation | undefined)[][][] = new Array<
		(SingleInsertionEvaluation | undefined)[][]
	>(busStopTimes.length);
	for (let i = 0; i != busStopTimes.length; ++i) {
		busStopEvaluations[i] = new Array<(SingleInsertionEvaluation | undefined)[]>(
			busStopTimes[i].length
		);
		for (let j = 0; j != busStopTimes[i].length; ++j) {
			busStopEvaluations[i][j] = new Array<SingleInsertionEvaluation | undefined>();
		}
		bothEvaluations[i] = new Array<Insertion | undefined>(busStopTimes[i].length);
	}
	const prepTime = Date.now() + MIN_PREP;
	const direction = startFixed ? InsertDirection.BUS_STOP_PICKUP : InsertDirection.BUS_STOP_DROPOFF;

	let passengers = 0;
	iterateAllInsertions(tours, insertionRanges, (insertionInfo: InsertionInfo) => {
		const prev: RideShareEvent | undefined =
			insertionInfo.tour.events[insertionInfo.idxInTourEvents - 1];
		const next: RideShareEvent | undefined =
			insertionInfo.tour.events[insertionInfo.idxInTourEvents];
		const insertionCase = {
			what: InsertWhat.BUS_STOP,
			direction
		};
		const window = getAllowedOperationTimes(prev, next, expandedSearchInterval, prepTime);
		if (window === undefined) {
			return;
		}
		for (let busStopIdx = 0; busStopIdx != busStopTimes.length; ++busStopIdx) {
			for (let busTimeIdx = 0; busTimeIdx != busStopTimes[busStopIdx].length; ++busTimeIdx) {
				insertionCase.what = InsertWhat.BOTH;
				const resultBoth = evaluateBothInsertion(
					insertionCase,
					window,
					travelDurations[busStopIdx],
					busStopTimes[busStopIdx][busTimeIdx],
					routingResults,
					insertionInfo,
					busStopIdx,
					prev,
					next,
					allowedTimes,
					passengers,
					required.passengers,
					promisedTimes
				);
				if (
					resultBoth != undefined &&
					(bothEvaluations[busStopIdx][busTimeIdx] == undefined ||
						resultBoth.cost < bothEvaluations[busStopIdx][busTimeIdx]!.cost)
				) {
					bothEvaluations[busStopIdx][busTimeIdx] = {
						...resultBoth,
						tour: insertionInfo.tourIdx,
						pickupIdx: insertionInfo.idxInTourEvents,
						dropoffIdx: insertionInfo.idxInTourEvents,
						prevPickupId: prev.eventId,
						nextPickupId: next.eventId,
						prevDropoffId: prev.eventId,
						nextDropoffId: next.eventId,
						pickupIdxInEvents: insertionInfo.idxInTourEvents,
						dropoffIdxInEvents: insertionInfo.idxInTourEvents
					};
				}
				insertionCase.what = InsertWhat.BUS_STOP;
				const resultBus = evaluateSingleInsertion(
					insertionCase,
					window,
					busStopTimes[busStopIdx][busTimeIdx],
					routingResults,
					insertionInfo,
					busStopIdx,
					prev,
					next,
					allowedTimes,
					promisedTimes
				);
				if (
					resultBus != undefined &&
					(busStopEvaluations[busStopIdx][busTimeIdx] == undefined ||
						busStopEvaluations[busStopIdx][busTimeIdx][insertionInfo.insertionIdx] == undefined ||
						resultBus.cost <
							busStopEvaluations[busStopIdx][busTimeIdx][insertionInfo.insertionIdx]!.cost)
				) {
					busStopEvaluations[busStopIdx][busTimeIdx][insertionInfo.insertionIdx] = resultBus;
				}
			}
		}
		insertionCase.what = InsertWhat.USER_CHOSEN;
		const resultUserChosen = evaluateSingleInsertion(
			insertionCase,
			window,
			undefined,
			routingResults,
			insertionInfo,
			undefined,
			prev,
			next,
			allowedTimes,
			promisedTimes
		);
		if (
			resultUserChosen != undefined &&
			(userChosenEvaluations[insertionInfo.insertionIdx] == undefined ||
				resultUserChosen.cost < userChosenEvaluations[insertionInfo.insertionIdx]!.cost)
		) {
			userChosenEvaluations[insertionInfo.insertionIdx] = resultUserChosen;
		}
		passengers += prev?.passengers ?? 0;
	});
	return { busStopEvaluations, userChosenEvaluations, bothEvaluations };
}

export function evaluatePairInsertions(
	tours: RideShareTour[],
	startFixed: boolean,
	insertionRanges: Map<number, Range[]>,
	busStopTimes: Interval[][],
	busStopEvaluations: (SingleInsertionEvaluation | undefined)[][][],
	userChosenEvaluations: (SingleInsertionEvaluation | undefined)[]
): (Insertion | undefined)[][] {
	const bestEvaluations: (Insertion | undefined)[][] = new Array<(Insertion | undefined)[]>(
		busStopTimes.length
	);
	for (let i = 0; i != busStopTimes.length; ++i) {
		bestEvaluations[i] = new Array<Insertion | undefined>(busStopTimes[i].length);
	}
	iterateAllInsertions(tours, insertionRanges, (insertionInfo: InsertionInfo) => {
		const events = insertionInfo.tour.events;
		const pickupIdx = insertionInfo.idxInTourEvents;
		let pickupInvalid = false;
		for (
			let dropoffIdx = pickupIdx + 1;
			dropoffIdx != insertionInfo.currentRange.latestDropoff + 1;
			++dropoffIdx
		) {
			if (pickupInvalid) {
				break;
			}
			for (let busStopIdx = 0; busStopIdx != busStopTimes.length; ++busStopIdx) {
				if (pickupInvalid) {
					break;
				}
				for (let timeIdx = 0; timeIdx != busStopTimes[busStopIdx].length; ++timeIdx) {
					const pickup = startFixed
						? busStopEvaluations[busStopIdx][timeIdx][insertionInfo.insertionIdx]
						: userChosenEvaluations[insertionInfo.insertionIdx];
					if (pickup == undefined) {
						pickupInvalid = true;
						break;
					}
					const dropoff = startFixed
						? userChosenEvaluations[insertionInfo.insertionIdx + dropoffIdx - pickupIdx]
						: busStopEvaluations[busStopIdx][timeIdx][
								insertionInfo.insertionIdx + dropoffIdx - pickupIdx
							];
					if (dropoff == undefined) {
						continue;
					}
					if (dropoffIdx < pickupIdx + 3) {
						let availableDistance =
							dropoff.time - pickup.time - dropoff.approachDuration - pickup.returnDuration;
						const prevDropoff = events[dropoffIdx - 1];
						if (pickupIdx + 2 === dropoffIdx) {
							availableDistance -= prevDropoff.prevLegDuration;
						}
						if (availableDistance - 2 < 0) {
							continue;
						}
					}
					const window = new Interval(pickup.time!, dropoff.time!);
					let eventOverlap = 0;
					if (pickupIdx !== 0 && window.covers(events[pickupIdx - 1].scheduledTimeEnd)) {
						eventOverlap += window.intersect(events[pickupIdx - 1].time)?.size() ?? 0;
					}
					if (
						pickupIdx < events.length - 1 &&
						window.covers(events[pickupIdx + 1].scheduledTimeStart)
					) {
						eventOverlap += window.intersect(events[pickupIdx + 1].time)?.size() ?? 0;
					}
					if (dropoffIdx !== 0 && window.covers(events[dropoffIdx - 1].scheduledTimeEnd)) {
						eventOverlap += window.intersect(events[dropoffIdx - 1].time)?.size() ?? 0;
					}
					if (
						dropoffIdx < events.length - 1 &&
						window.covers(events[dropoffIdx + 1].scheduledTimeStart)
					) {
						eventOverlap += window.intersect(events[dropoffIdx + 1].time)?.size() ?? 0;
					}
					const taxiDuration = pickup.taxiDuration + dropoff.taxiDuration;
					const taxiWaitingTime = dropoff.taxiWaitingTime + pickup.taxiWaitingTime;
					const passengerDuration = dropoff.time! - pickup.time! + eventOverlap;
					const cost = computeCost(passengerDuration, taxiDuration, taxiWaitingTime);

					bookingLogs.push({
						pickupType: printInsertionType(pickup.case),
						dropoffType: printInsertionType(dropoff.case),
						pickupPrevLegDuration: pickup.approachDuration,
						pickupNextLegDuration: pickup.returnDuration,
						dropoffPrevLegDuration: dropoff.approachDuration,
						dropoffNextLegDuration: dropoff.returnDuration,
						cost,
						iter: iteration,
						pickupWaitingTime: pickup.taxiWaitingTime,
						dropoffWaitingTime: dropoff.taxiWaitingTime,
						pickupTaxiDuration: pickup.taxiDuration,
						dropoffTaxiDuration: dropoff.taxiDuration,
						waitingTime: pickup.taxiWaitingTime + dropoff.taxiWaitingTime,
						taxiDuration: taxiDuration,
						passengerDuration,
						pickupTime: pickup.time,
						dropoffTime: dropoff.time,
						pickupNextId: pickup.nextId,
						dropoffPrevId: dropoff.prevId
					});
					if (
						bestEvaluations[busStopIdx][timeIdx] == undefined ||
						cost < bestEvaluations[busStopIdx][timeIdx]!.cost
					) {
						bestEvaluations[busStopIdx][timeIdx] = {
							pickupTime: pickup.time,
							dropoffTime: dropoff.time,
							pickupCase: structuredClone(pickup.case),
							dropoffCase: structuredClone(dropoff.case),
							pickupIdx,
							dropoffIdx,
							taxiWaitingTime,
							taxiDuration,
							passengerDuration,
							cost,
							tour: insertionInfo.tourIdx,
							pickupPrevLegDuration: pickup.approachDuration,
							pickupNextLegDuration: pickup.returnDuration,
							dropoffPrevLegDuration: dropoff.approachDuration,
							dropoffNextLegDuration: dropoff.returnDuration,
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

const computeCost = (passengerDuration: number, taxiDuration: number, taxiWaitingTime: number) => {
	return (
		TAXI_DRIVING_TIME_COST_FACTOR * taxiDuration +
		PASSENGER_TIME_COST_FACTOR * passengerDuration +
		TAXI_WAITING_TIME_COST_FACTOR * taxiWaitingTime
	);
};

function getTaxiWaitingDelta(
	drivingDuration: number,
	prev: RideShareEvent,
	next: RideShareEvent
): number {
	const oldWaitingTime =
		getScheduledEventTime(next!) - getScheduledEventTime(prev!) - prev!.nextLegDuration;
	const prevTaskTime = getScheduledEventTime(prev!);
	const nextTaskTime = getScheduledEventTime(next!);
	const newWaitingTime = Math.max(nextTaskTime - prevTaskTime - drivingDuration, 0);
	return newWaitingTime - oldWaitingTime;
}

const getOldDrivingTime = (prev: RideShareEvent, next: RideShareEvent): number => {
	return next.prevLegDuration + prev.nextLegDuration;
};

const keepsPromises = (
	insertionCase: InsertionType,
	arrivalWindow: Interval,
	directDuration: number,
	promisedTimes: PromisedTimes
): boolean => {
	const expandToFullMinutes = (interval: Interval) => {
		return new Interval(
			roundToUnit(interval.startTime, MINUTE, Math.floor),
			roundToUnit(interval.endTime, MINUTE, Math.ceil)
		);
	};
	const w = arrivalWindow.shift(
		insertionCase.direction == InsertDirection.BUS_STOP_PICKUP ? directDuration : -directDuration
	);
	const pickupWindow = expandToFullMinutes(
		insertionCase.direction == InsertDirection.BUS_STOP_PICKUP ? arrivalWindow : w
	);
	const dropoffWindow = expandToFullMinutes(
		insertionCase.direction == InsertDirection.BUS_STOP_DROPOFF ? arrivalWindow : w
	);

	let checkPickup = false;
	let checkDropoff = false;
	switch (insertionCase.what) {
		case InsertWhat.BOTH:
			checkPickup = true;
			checkDropoff = true;
			break;

		case InsertWhat.BUS_STOP:
			if (insertionCase.direction == InsertDirection.BUS_STOP_PICKUP) {
				checkPickup = true;
			} else {
				checkDropoff = true;
			}
			break;

		case InsertWhat.USER_CHOSEN:
			if (insertionCase.direction != InsertDirection.BUS_STOP_PICKUP) {
				checkPickup = true;
			} else {
				checkDropoff = true;
			}
	}
	console.log('KEEPS PROMISE', { checkPickup, checkDropoff });
	if (checkPickup && !pickupWindow.covers(promisedTimes.pickup)) {
		console.log('PROMISE CHECK: PICKUP WINDOW FAILED', {
			pickupWindow: pickupWindow.toString(),
			pickup: new Date(promisedTimes.pickup).toISOString()
		});
		return false;
	}
	if (checkDropoff && !dropoffWindow.covers(promisedTimes.dropoff)) {
		console.log('PROMISE CHECK: DROPOFF WINDOW FAILED', {
			dropoffWindow: dropoffWindow.toString(),
			dropoff: new Date(promisedTimes.dropoff).toISOString()
		});
		return false;
	}
	return true;
};

export const takeBest = (
	evals1: (Insertion | undefined)[][],
	evals2: (Insertion | undefined)[][]
): (Insertion | undefined)[][] => {
	const takeBetter = (e1: Insertion | undefined, e2: Insertion | undefined) => {
		if (e1 == undefined) {
			return e2;
		}
		if (e2 == undefined) {
			return e1;
		}
		return e1.cost < e2.cost ? e1 : e2;
	};
	console.assert(
		evals1.length == evals2.length,
		'in takeBest, evaluations do not have matching length.'
	);
	const result = new Array<(Insertion | undefined)[]>(evals1.length);
	for (let busStopIdx = 0; busStopIdx != evals1.length; ++busStopIdx) {
		console.assert(
			evals1[busStopIdx].length == evals2[busStopIdx].length,
			"in takeBest, evaluations' inner arrays do not have matching length."
		);
		result[busStopIdx] = new Array<Insertion | undefined>(evals1[busStopIdx].length);
		for (let timeIdx = 0; timeIdx != evals1[busStopIdx].length; ++timeIdx) {
			const e1 = evals1[busStopIdx][timeIdx];
			const e2 = evals2[busStopIdx][timeIdx];
			result[busStopIdx][timeIdx] = takeBetter(e1, e2);
		}
	}
	return result;
};
