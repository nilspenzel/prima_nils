import {
	MIN_PREP,
	PASSENGER_TIME_COST_FACTOR,
	SCHEDULED_TIME_BUFFER,
	TAXI_DRIVING_TIME_COST_FACTOR,
	TAXI_WAITING_TIME_COST_FACTOR
} from '$lib/constants';
import {
	comesFromCompany,
	getAllowedOperationTimes,
	getPrevLegDuration,
	getArrivalWindow,
	getNextLegDuration,
	returnsToCompany
} from './durations';
import type { PromisedTimes } from './PromisedTimes';
import { Interval } from '$lib/util/interval';
import type { RoutingResults } from './routing';
import type { Capacities } from '$lib/util/booking/Capacities';
import { type Range } from '$lib/util/booking/getPossibleInsertions';
import { getScheduledEventTime } from '$lib/util/getScheduledEventTime';
import { roundToUnit, MINUTE } from '$lib/util/time';
import { iterateAllInsertions } from './iterateAllInsertions';
import { InsertHow, InsertWhat } from '$lib/util/booking/insertionTypes';
import { bookingLogs, iteration } from '$lib/testHelpers';
import type { RideShareEvent, RideShareTour } from './getBookingAvailability';
import {
	canCaseBeValid,
	INSERT_HOW_OPTIONS,
	InsertDirection,
	InsertWhere,
	isCaseValid,
	printInsertionType,
	type InsertionType
} from '../booking/insertionTypes';
import type { InsertionInfo } from './insertionTypes';

export type InsertionEvaluation = {
	pickupTime: number;
	dropoffTime: number;
	scheduledPickupTime: number;
	scheduledDropoffTime: number;
	pickupCase: InsertionType;
	dropoffCase: InsertionType;
	taxiWaitingTime: number;
	taxiDuration: number;
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
	rideShareTour: number;
	prevPickupId: number | undefined;
	nextPickupId: number | undefined;
	prevDropoffId: number | undefined;
	nextDropoffId: number | undefined;
	pickupIdxInEvents: number | undefined;
	dropoffIdxInEvents: number | undefined;
	provider: number;
};

type SingleInsertionEvaluation = {
	window: Interval;
	prevLegDuration: number;
	nextLegDuration: number;
	case: InsertionType;
	taxiWaitingTime: number;
	taxiDuration: number;
	cost: number;
	prevId: number | undefined;
	nextId: number | undefined;
	idxInEvents: number;
	time: number;
	provider: number;
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
				dropoffTime: new Date(i.dropoffTime).toISOString(),
				scheduledPickupTime: new Date(i.scheduledPickupTime).toISOString(),
				scheduledDropoffTime: new Date(i.scheduledDropoffTime).toISOString(),
				departure: i.departure == undefined ? undefined : new Date(i.departure).toISOString(),
				arrival: i.arrival == undefined ? undefined : new Date(i.arrival).toISOString()
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
		e.rideShareTour +
		'\n' +
		'departure: ' +
		(e.departure ? new Date(e.departure).toISOString() : undefined) +
		'\n' +
		'arrival: ' +
		(e.arrival ? new Date(e.arrival).toISOString() : undefined) +
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

function isPickup(type: InsertionType) {
	if (type.what === InsertWhat.BOTH) {
		return false;
	}
	return (
		(type.what === InsertWhat.BUS_STOP) === (type.direction === InsertDirection.BUS_STOP_PICKUP)
	);
}

export function evaluateSingleInsertion(
	insertionCase: InsertionType,
	windows: Interval[],
	busStopWindow: Interval | undefined,
	routingResults: RoutingResults,
	insertionInfo: InsertionInfo,
	busStopIdx: number | undefined,
	prev: RideShareEvent | undefined,
	next: RideShareEvent | undefined,
	allowedTimes: Interval[],
	promisedTimes?: PromisedTimes
): SingleInsertionEvaluation | undefined {
	console.assert(insertionCase.what != InsertWhat.BOTH);
	const events = insertionInfo.events;
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
		windows,
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
		console.log('Promise not kept', printInsertionType(insertionCase));
		return undefined;
	}
	const taxiDurationDelta =
		prevLegDuration + nextLegDuration - getOldDrivingTime(insertionCase, prev, next);
	console.assert(insertionCase.what != InsertWhat.BOTH);
	const communicatedTime =
		promisedTimes === undefined
			? arrivalWindow.startTime
			: isPickup(insertionCase)
				? arrivalWindow.covers(promisedTimes.pickup)
					? promisedTimes.pickup
					: arrivalWindow.startTime
				: arrivalWindow.covers(promisedTimes.dropoff)
					? promisedTimes.dropoff
					: arrivalWindow.endTime;
	const scheduledShift = Math.min(arrivalWindow.size(), SCHEDULED_TIME_BUFFER);
	const scheduledTimeCandidate =
		communicatedTime + (isPickup(insertionCase) ? scheduledShift : -scheduledShift);
	let newEndTimePrev = undefined;
	if (
		!comesFromCompany(insertionCase) &&
		prev!.isPickup &&
		communicatedTime - prev!.scheduledTimeEnd - prevLegDuration < 0
	) {
		newEndTimePrev = communicatedTime - prevLegDuration;
	}
	let newStartTimeNext = undefined;
	if (
		!returnsToCompany(insertionCase) &&
		!next!.isPickup &&
		communicatedTime - next!.scheduledTimeEnd - nextLegDuration < 0
	) {
		newStartTimeNext = communicatedTime + nextLegDuration;
	}
	const prevShift =
		newEndTimePrev !== undefined ? getScheduledEventTime(prev!) - newEndTimePrev : 0;
	const nextShift =
		newStartTimeNext !== undefined ? newStartTimeNext - getScheduledEventTime(next!) : 0;
	const taxiWaitingTime = getWaitingTimeDelta(
		prev,
		next,
		events,
		prevShift,
		nextShift,
		taxiDurationDelta
	);
	const passengersEnteringInPrev =
		!comesFromCompany(insertionCase) && prev!.isPickup ? prev!.passengers : 0;
	const passengerExitingAtNext =
		!returnsToCompany(insertionCase) && !next!.isPickup ? next!.passengers : 0;
	const weightedPassengerDuration =
		passengersEnteringInPrev * prevShift + passengerExitingAtNext * nextShift;
	const sie: SingleInsertionEvaluation = {
		window: arrivalWindow,
		prevLegDuration: prevLegDuration,
		nextLegDuration: nextLegDuration,
		case: structuredClone(insertionCase),
		taxiDuration: taxiDurationDelta,
		taxiWaitingTime,
		cost: computeCost(weightedPassengerDuration, taxiDurationDelta, taxiWaitingTime),
		prevId: prev?.eventId,
		nextId: next?.eventId,
		time: scheduledTimeCandidate,
		idxInEvents: insertionInfo.idxInEvents,
		provider: insertionInfo.provider
	};
	return sie;
}

export function evaluateBothInsertion(
	insertionCase: InsertionType,
	windows: Interval[],
	passengerDuration: number | undefined,
	busStopWindow: Interval | undefined,
	routingResults: RoutingResults,
	insertionInfo: InsertionInfo,
	busStopIdx: number | undefined,
	prev: RideShareEvent | undefined,
	next: RideShareEvent | undefined,
	allowedTimes: Interval[],
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
	const events = insertionInfo.events;
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
		windows,
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
			{ windows: windows.toString() },
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
	const taxiDurationDelta =
		prevLegDuration +
		nextLegDuration +
		passengerDuration -
		getOldDrivingTime(insertionCase, prev, next);

	const leeway = Math.min(arrivalWindow.size(), SCHEDULED_TIME_BUFFER);
	const leewayNewTour = Math.min(Math.floor(arrivalWindow.size() / 2), SCHEDULED_TIME_BUFFER);
	const pickupLeeway = (() => {
		switch (insertionCase.how) {
			case InsertHow.APPEND:
				return 0;
			case InsertHow.PREPEND:
				return leeway;
			case InsertHow.INSERT:
				return 0;
			case InsertHow.NEW_TOUR:
				return leewayNewTour;
			case InsertHow.CONNECT:
				return 0;
		}
	})();
	const dropoffLeeway = (() => {
		switch (insertionCase.how) {
			case InsertHow.APPEND:
				return leeway;
			case InsertHow.PREPEND:
				return 0;
			case InsertHow.INSERT:
				return 0;
			case InsertHow.NEW_TOUR:
				return leewayNewTour;
			case InsertHow.CONNECT:
				return 0;
		}
	})();
	let communicatedPickupTime = -1;
	let communicatedDropoffTime = -1;
	let pickupScheduledEndTime = -1;
	let dropoffScheduledStartTime = -1;
	if (insertionCase.direction == InsertDirection.BUS_STOP_PICKUP) {
		communicatedPickupTime =
			promisedTimes === undefined
				? arrivalWindow.startTime
				: arrivalWindow.covers(promisedTimes.pickup)
					? promisedTimes.pickup
					: arrivalWindow.startTime;
		pickupScheduledEndTime = communicatedPickupTime + pickupLeeway;
		dropoffScheduledStartTime = pickupScheduledEndTime + passengerDuration;
		communicatedDropoffTime = dropoffScheduledStartTime + dropoffLeeway;
	} else {
		communicatedDropoffTime =
			promisedTimes === undefined
				? arrivalWindow.endTime
				: arrivalWindow.covers(promisedTimes.dropoff)
					? promisedTimes.dropoff
					: arrivalWindow.endTime;
		dropoffScheduledStartTime = communicatedDropoffTime - dropoffLeeway;
		pickupScheduledEndTime = dropoffScheduledStartTime - passengerDuration;
		communicatedPickupTime = pickupScheduledEndTime - pickupLeeway;
	}

	let prevShift = 0;
	if (!comesFromCompany(insertionCase) && prev!.isPickup) {
		prevShift = Math.max(
			getScheduledEventTime(prev!) - communicatedPickupTime + prevLegDuration,
			0
		);
	}
	let nextShift = 0;
	if (!returnsToCompany(insertionCase) && !next!.isPickup) {
		nextShift = Math.max(
			communicatedDropoffTime + nextLegDuration - getScheduledEventTime(next!),
			0
		);
	}

	let weightedPassengerDuration =
		passengerCountNewRequest * (dropoffScheduledStartTime - pickupScheduledEndTime);
	weightedPassengerDuration += getWeightedPassengerDurationDelta(
		insertionCase,
		prev,
		next,
		prevShift,
		nextShift
	);
	const departure = comesFromCompany(insertionCase)
		? pickupScheduledEndTime - prevLegDuration
		: undefined;
	const arrival = returnsToCompany(insertionCase)
		? dropoffScheduledStartTime + nextLegDuration
		: undefined;

	const taxiWaitingTime = getWaitingTimeDelta(
		prev,
		next,
		events,
		prevShift,
		nextShift,
		taxiDurationDelta
	);

	const cost = computeCost(weightedPassengerDuration, taxiDurationDelta, taxiWaitingTime);
	bookingLogs.push({
		type: printInsertionType(insertionCase),
		prevEvent: prev?.eventId,
		nextEvent: next?.eventId,
		prevLegDuration,
		nextLegDuration,
		cost,
		iter: iteration,
		waitingTime: taxiWaitingTime,
		taxiDuration: taxiDurationDelta,
		oldDrivingTime: getOldDrivingTime(insertionCase, prev, next),
		passengerDuration: passengerDuration,
		weightedPassengerDuration,
		whitelist: promisedTimes === undefined
	});
	console.log(
		promisedTimes === undefined ? 'WHITELIST' : 'BOOKING API',
		'bothevaluation',
		printInsertionType(insertionCase),
		{ pickupTime: pickupScheduledEndTime.toString() },
		{ dropoffTime: dropoffScheduledStartTime.toString() }
	);
	console.log(
		promisedTimes === undefined ? 'WHITELIST' : 'BOOKING API',
		'valid insertion found,',
		printInsertionType(insertionCase),
		{ prevId: prev?.eventId },
		{ nextId: next?.eventId },
		{ cost },
		{ weightedPassengerDuration },
		{ taxiDurationDelta },
		{ taxiWaitingTime }
	);
	return {
		pickupTime: communicatedPickupTime,
		dropoffTime: communicatedDropoffTime,
		scheduledPickupTime: pickupScheduledEndTime,
		scheduledDropoffTime: dropoffScheduledStartTime,
		pickupCase: structuredClone(insertionCase),
		dropoffCase: structuredClone(insertionCase),
		passengerDuration: weightedPassengerDuration,
		taxiDuration: taxiDurationDelta,
		taxiWaitingTime,
		cost,
		departure,
		arrival,
		pickupPrevLegDuration: prevLegDuration,
		pickupNextLegDuration: passengerDuration,
		dropoffPrevLegDuration: passengerDuration,
		dropoffNextLegDuration: nextLegDuration
	};
}

export function evaluateSingleInsertions(
	companies: RideShareTour[],
	required: Capacities,
	startFixed: boolean,
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

	iterateAllInsertions(companies, insertionRanges, (insertionInfo: InsertionInfo) => {
		const events = insertionInfo.events;
		if (insertionInfo.idxInEvents === 0 || insertionInfo.idxInEvents === events.length) {
			return;
		}
		const prev: RideShareEvent = events[insertionInfo.idxInEvents - 1];
		const next: RideShareEvent = events[insertionInfo.idxInEvents];
		INSERT_HOW_OPTIONS.forEach((insertHow) => {
			const insertionCase = {
				how: insertHow,
				where: InsertWhere.BETWEEN_EVENTS,
				what: InsertWhat.BUS_STOP,
				direction
			};
			if (!canCaseBeValid(insertionCase)) {
				return undefined;
			}
			const windows = getAllowedOperationTimes(insertionCase, prev, next, prepTime);

			for (let busStopIdx = 0; busStopIdx != busStopTimes.length; ++busStopIdx) {
				for (let busTimeIdx = 0; busTimeIdx != busStopTimes[busStopIdx].length; ++busTimeIdx) {
					insertionCase.what = InsertWhat.BOTH;
					const resultBoth = evaluateBothInsertion(
						insertionCase,
						windows,
						travelDurations[busStopIdx],
						busStopTimes[busStopIdx][busTimeIdx],
						routingResults,
						insertionInfo,
						busStopIdx,
						prev,
						next,
						allowedTimes,
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
							rideShareTour: next!.tourId,
							pickupIdx: insertionInfo.idxInEvents,
							dropoffIdx: insertionInfo.idxInEvents,
							prevPickupId: prev?.eventId,
							nextPickupId: next?.eventId,
							prevDropoffId: prev?.eventId,
							nextDropoffId: next?.eventId,
							pickupIdxInEvents: insertionInfo.idxInEvents,
							dropoffIdxInEvents: insertionInfo.idxInEvents,
							provider: insertionInfo.provider
						};
					}

					insertionCase.what = InsertWhat.BUS_STOP;
					if (!isCaseValid(insertionCase)) {
						continue;
					}
					const resultBus = evaluateSingleInsertion(
						insertionCase,
						windows,
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
			if (!isCaseValid(insertionCase)) {
				return;
			}
			const resultUserChosen = evaluateSingleInsertion(
				insertionCase,
				windows,
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
		});
	});
	return { busStopEvaluations, userChosenEvaluations, bothEvaluations };
}

export function evaluatePairInsertions(
	companies: RideShareTour[],
	startFixed: boolean,
	insertionRanges: Map<number, Range[]>,
	busStopTimes: Interval[][],
	busStopEvaluations: (SingleInsertionEvaluation | undefined)[][][],
	userChosenEvaluations: (SingleInsertionEvaluation | undefined)[],
	required: Capacities,
	whitelist?: boolean
): (Insertion | undefined)[][] {
	const bestEvaluations: (Insertion | undefined)[][] = new Array<(Insertion | undefined)[]>(
		busStopTimes.length
	);
	for (let i = 0; i != busStopTimes.length; ++i) {
		bestEvaluations[i] = new Array<Insertion | undefined>(busStopTimes[i].length);
	}
	iterateAllInsertions(companies, insertionRanges, (insertionInfo: InsertionInfo) => {
		const events = insertionInfo.events;
		const pickupIdx = insertionInfo.idxInEvents;
		const prevPickup = events[pickupIdx - 1];
		const nextPickup = events[pickupIdx];
		const twoAfterPickup = events[pickupIdx + 1];

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
					const prevDropoff = events[dropoffIdx - 1];
					const nextDropoff = events[dropoffIdx];
					const twoAfterDropoff = events[dropoffIdx + 1];
					const communicatedPickupTime = Math.max(
						pickup.window.endTime - SCHEDULED_TIME_BUFFER,
						pickup.window.startTime
					);
					const communicatedDropoffTime = Math.min(
						dropoff.window.startTime + SCHEDULED_TIME_BUFFER,
						dropoff.window.endTime
					);

					// Verify, that the shift induced to other events by pickup and dropoff are mutually compatible
					if (dropoffIdx < pickupIdx + 3) {
						let availableDistance =
							communicatedDropoffTime -
							communicatedPickupTime -
							dropoff.prevLegDuration -
							pickup.nextLegDuration;
						if (pickupIdx + 2 === dropoffIdx) {
							availableDistance -= prevDropoff.prevLegDuration;
						}
						if (availableDistance - 2 < 0) {
							continue;
						}
					}

					// Determine the scheduled times for pickup and dropoff
					const leewayBetweenPickupDropoff =
						communicatedDropoffTime -
						communicatedPickupTime -
						pickup.nextLegDuration -
						dropoff.prevLegDuration;
					const pickupScheduledShift = Math.min(
						pickup.window.size(),
						SCHEDULED_TIME_BUFFER,
						leewayBetweenPickupDropoff
					);
					const scheduledPickupTime =
						communicatedPickupTime +
						(pickup.case.how === InsertHow.APPEND ? 0 : pickupScheduledShift);
					const scheduledDropoffTime =
						communicatedDropoffTime -
						(dropoff.case.how === InsertHow.PREPEND
							? 0
							: Math.min(
									dropoff.window.size(),
									SCHEDULED_TIME_BUFFER,
									leewayBetweenPickupDropoff - pickupScheduledShift
								));

					// Compute the delta of the taxi's time spend driving for the tour containing the new request
					const window = new Interval(communicatedPickupTime, communicatedDropoffTime);
					let eventOverlap = 0;
					if (pickupIdx !== 0 && window.covers(prevPickup.scheduledTimeEnd)) {
						eventOverlap += window.intersect(prevPickup.time)?.size() ?? 0;
					}
					if (pickupIdx < events.length - 1 && window.covers(twoAfterPickup.scheduledTimeStart)) {
						eventOverlap += window.intersect(twoAfterPickup.time)?.size() ?? 0;
					}
					if (dropoffIdx !== 0 && window.covers(prevDropoff.scheduledTimeEnd)) {
						eventOverlap += window.intersect(prevDropoff.time)?.size() ?? 0;
					}
					if (dropoffIdx < events.length - 1 && window.covers(twoAfterDropoff.scheduledTimeStart)) {
						eventOverlap += window.intersect(twoAfterDropoff.time)?.size() ?? 0;
					}
					const drivingDurationDelta = pickup.taxiDuration + dropoff.taxiDuration;
					const passengerDuration = scheduledDropoffTime! - scheduledPickupTime! + eventOverlap;

					// Compute the delta of the taxi's waiting time
					const newDeparture = events[0].scheduledTimeEnd;
					const newArrival = events[events.length - 1].scheduledTimeStart;
					const oldTourDurationSum =
						events[events.length - 1].scheduledTimeStart - events[0].scheduledTimeEnd;
					const tourDurationDelta = newArrival - newDeparture - oldTourDurationSum;
					const taxiWaitingTime = tourDurationDelta - drivingDurationDelta;

					// Compute the delta of the duration spend by passengers in the taxi
					let prevShiftPickup = 0;
					if (prevPickup!.isPickup) {
						prevShiftPickup = Math.max(
							0,
							getScheduledEventTime(prevPickup!) - communicatedPickupTime + pickup.prevLegDuration
						);
					}
					let nextShiftPickup = 0;
					if (!nextPickup!.isPickup) {
						nextShiftPickup = Math.max(
							0,
							scheduledPickupTime + pickup.nextLegDuration - getScheduledEventTime(nextPickup!)
						);
					}
					let prevShiftDropoff = 0;
					if (prevDropoff!.isPickup) {
						prevShiftDropoff = Math.max(
							0,
							getScheduledEventTime(prevDropoff!) - scheduledDropoffTime + dropoff.prevLegDuration
						);
					}
					let nextShiftDropoff = 0;
					if (!nextDropoff!.isPickup) {
						nextShiftDropoff = Math.max(
							0,
							communicatedDropoffTime +
								dropoff.nextLegDuration -
								getScheduledEventTime(nextDropoff!)
						);
					}

					let weightedPassengerDuration =
						required.passengers * (scheduledDropoffTime - scheduledPickupTime);
					weightedPassengerDuration += getWeightedPassengerDurationDelta(
						pickup.case,
						prevPickup,
						nextPickup,
						prevShiftPickup,
						nextShiftPickup
					);
					weightedPassengerDuration += getWeightedPassengerDurationDelta(
						dropoff.case,
						prevDropoff,
						nextDropoff,
						prevShiftDropoff,
						nextShiftDropoff
					);

					// Compute the cost used to compare to other insertion options
					const cost = computeCost(
						weightedPassengerDuration,
						drivingDurationDelta,
						taxiWaitingTime
					);

					console.log(
						whitelist ? 'WHITELIST' : 'BOOKING API',
						'valid insertion found,',
						'pickup: ',
						printInsertionType(pickup.case),
						'dropoff: ',
						printInsertionType(dropoff.case),
						{ prevPickupId: prevPickup?.eventId },
						{ nextPickupId: nextPickup?.eventId },
						{ prevDropoffId: prevDropoff?.eventId },
						{ nextDropoffId: nextDropoff?.eventId },
						{ cost },
						{ weightedPassengerDuration },
						{ taxiWaitingTime },
						{ drivingDurationDelta }
					);
					bookingLogs.push({
						pickupType: printInsertionType(pickup.case),
						dropoffType: printInsertionType(dropoff.case),
						pickupPrevLegDuration: pickup.prevLegDuration,
						pickupNextLegDuration: pickup.nextLegDuration,
						dropoffPrevLegDuration: dropoff.prevLegDuration,
						dropoffNextLegDuration: dropoff.nextLegDuration,
						cost,
						iter: iteration,
						pickupWaitingTime: pickup.taxiWaitingTime,
						dropoffWaitingTime: dropoff.taxiWaitingTime,
						pickupTaxiDuration: pickup.taxiDuration,
						dropoffTaxiDuration: dropoff.taxiDuration,
						waitingTime: taxiWaitingTime,
						taxiDuration: drivingDurationDelta,
						passengerDuration,
						pickupTime: communicatedPickupTime,
						dropoffTime: scheduledDropoffTime,
						pickupNextId: pickup.nextId,
						dropoffPrevId: dropoff.prevId,
						weightedPassengerDuration
					});
					if (
						bestEvaluations[busStopIdx][timeIdx] == undefined ||
						cost < bestEvaluations[busStopIdx][timeIdx]!.cost
					) {
						const tour = events[pickupIdx].tourId;
						bestEvaluations[busStopIdx][timeIdx] = {
							pickupTime: communicatedPickupTime,
							dropoffTime: communicatedDropoffTime,
							scheduledPickupTime,
							scheduledDropoffTime,
							pickupCase: structuredClone(pickup.case),
							dropoffCase: structuredClone(dropoff.case),
							pickupIdx,
							dropoffIdx,
							taxiWaitingTime,
							taxiDuration: drivingDurationDelta,
							passengerDuration: weightedPassengerDuration,
							cost,
							rideShareTour: tour,
							departure: comesFromCompany(pickup.case)
								? new Date(scheduledPickupTime - pickup.prevLegDuration).getTime()
								: undefined,
							arrival: returnsToCompany(dropoff.case)
								? new Date(scheduledDropoffTime + dropoff.nextLegDuration).getTime()
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
							dropoffIdxInEvents: dropoff.idxInEvents,
							provider: pickup.provider
						};
					}
				}
			}
		}
	});
	return bestEvaluations;
}

export const computeCost = (
	passengerDuration: number,
	taxiDuration: number,
	taxiWaitingTime: number
) => {
	return (
		TAXI_DRIVING_TIME_COST_FACTOR * taxiDuration +
		PASSENGER_TIME_COST_FACTOR * passengerDuration +
		TAXI_WAITING_TIME_COST_FACTOR * taxiWaitingTime
	);
};

const getOldDrivingTime = (
	insertionCase: InsertionType,
	prev: RideShareEvent | undefined,
	next: RideShareEvent | undefined
): number => {
	if (insertionCase.how == InsertHow.NEW_TOUR) {
		return 0;
	}
	if (insertionCase.how == InsertHow.CONNECT) {
		return next!.prevLegDuration + prev!.nextLegDuration;
	}
	console.assert(prev != undefined || next != undefined, 'getOldDrivingTime: no event found');
	if (comesFromCompany(insertionCase)) {
		console.assert(
			insertionCase.how == InsertHow.PREPEND,
			'getOldDrivingTime: no previous but also no prepend'
		);
		return next!.prevLegDuration;
	}
	return prev!.nextLegDuration;
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
	const shift = insertionCase.what === InsertWhat.BOTH ? directDuration : 0;
	const w = arrivalWindow.shift(
		insertionCase.direction == InsertDirection.BUS_STOP_PICKUP ? shift : -shift
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

function getWaitingTimeDelta(
	prev: RideShareEvent | undefined,
	next: RideShareEvent | undefined,
	events: RideShareEvent[],
	prevShift: number,
	nextShift: number,
	taxiDurationDelta: number
) {
	let tourDurationDelta = 0;
	const twoBefore =
		prev === undefined
			? undefined
			: events[events.findIndex((e) => e.eventId === prev.eventId) - 1];
	const twoAfter =
		next === undefined
			? undefined
			: events[events.findIndex((e) => e.eventId === next.eventId) + 1];
	if (prev && prevShift && twoBefore?.tourId !== prev.tourId) {
		tourDurationDelta += prevShift;
	}
	if (next && nextShift && twoAfter?.tourId !== next.tourId) {
		tourDurationDelta += nextShift;
	}
	return tourDurationDelta - taxiDurationDelta;
}

function getWeightedPassengerDurationDelta(
	type: InsertionType,
	prev: RideShareEvent | undefined,
	next: RideShareEvent | undefined,
	prevShift: number,
	nextShift: number
) {
	const passengersEnteringInPrev = !comesFromCompany(type) && prev!.isPickup ? prev!.passengers : 0;
	const passengerExitingAtNext = !returnsToCompany(type) && !next!.isPickup ? next!.passengers : 0;
	return passengersEnteringInPrev * prevShift + passengerExitingAtNext * nextShift;
}
