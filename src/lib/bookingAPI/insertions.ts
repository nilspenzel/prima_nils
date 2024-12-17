import type { Company, Event } from '$lib/compositionTypes';
import { Interval } from '$lib/interval';
import { iterateAllInsertions } from './utils';
import { type RoutingResults } from './routing';
import { isValid, type Range } from './capacitySimulation';
import { minutesToMs } from '$lib/time_utils';
import {
	BUFFER_TIME,
	MAX_TRAVEL_MS,
	MIN_PREP_MINUTES,
	PASSENGER_CHANGE_MINUTES,
	PASSENGER_TIME_COST_FACTOR,
	TAXI_DRIVING_TIME_COST_FACTOR,
	TAXI_WAITING_TIME_COST_FACTOR
} from '$lib/constants';
import {
	InsertDirection,
	InsertHow,
	INSERTION_TYPES,
	InsertWhat,
	InsertWhere,
	canCaseBeValid,
	type InsertionInfo,
	type InsertionType,
	isCaseValid
} from './insertionTypes';
import type { Capacities } from '$lib/capacities';
import {
	comesFromCompany,
	getAllowedOperationTimes,
	getApproachDuration,
	getArrivalWindow,
	getReturnDuration,
	returnsToCompany
} from './durations';

type Evaluations = {
	busStopEvaluations: (SingleInsertionEvaluation | undefined)[][][];
	userChosenEvaluations: (SingleInsertionEvaluation | undefined)[];
	bothEvaluations: (InsertionEvaluation | undefined)[][];
};

export type InsertionEvaluation = {
	pickupTime: Date;
	dropoffTime: Date;
	pickupCase: InsertionType;
	dropoffCase: InsertionType;
	taxiWaitingTime: number;
	taxiDuration: number;
	passengerDuration: number;
	cost: number;
	company: number;
	vehicle: number;
	tour: number | undefined;
	departure: Date | undefined;
	arrival: Date | undefined;
	pickupApproachDuration: number;
	pickupReturnDuration: number;
	dropoffApproachDuration: number;
	dropoffReturnDuration: number;
};

type SingleInsertionEvaluation = {
	time: Date;
	window: Interval;
	approachDuration: number;
	returnDuration: number;
	case: InsertionType;
	taxiWaitingTime: number;
	taxiDuration: number;
	passengerDuration: number;
	cost: number;
};

export function evaluateBothInsertion(
	insertionCase: InsertionType,
	windows: Interval[],
	travelDuration: number|undefined,
	busStopWindow: Interval | undefined,
	routingResults: RoutingResults,
	insertionInfo: InsertionInfo,
	busStopIdx: number | undefined,
	prev: Event | undefined,
	next: Event | undefined
) {
	const getOldDrivingTime = (insertionCase: InsertionType, prev: Event|undefined, next: Event|undefined): number => {
		if(insertionCase.how == InsertHow.NEW_TOUR) {
			return 0;
		}
		console.assert(prev!=undefined||next!=undefined);
		if(prev == undefined) {
			console.assert(insertionCase.how == InsertHow.PREPEND);
			return next!.approachDuration;
		}
		return prev.returnDuration;
	}

	console.assert(
		insertionCase.what == InsertWhat.BOTH,
		'Not inserting both in evaluateBothInsertion.'
	);
	const approachDuration = getApproachDuration(
		insertionCase,
		routingResults,
		insertionInfo,
		busStopIdx,
		prev
	);
	const returnDuration = getReturnDuration(
		insertionCase,
		routingResults,
		insertionInfo,
		busStopIdx,
		next
	);
	if (
		approachDuration == undefined ||
		returnDuration == undefined ||
		travelDuration == undefined
	) {
		return undefined;
	}
	const arrivalWindow = getArrivalWindow(
		insertionCase,
		windows,
		travelDuration,
		busStopWindow,
		approachDuration,
		returnDuration
	);
	if (arrivalWindow == undefined) {
		return undefined;
	}
	const taxiDurationDelta =
		approachDuration +
		returnDuration +
		travelDuration +
		minutesToMs(BUFFER_TIME + PASSENGER_CHANGE_MINUTES) -
		getOldDrivingTime(insertionCase, prev, next);
	const pickupTime =
		insertionCase.direction == InsertDirection.FROM_BUS_STOP
			? arrivalWindow.startTime
			: new Date(
					arrivalWindow.endTime.getTime() -
						travelDuration -
						minutesToMs(BUFFER_TIME + PASSENGER_CHANGE_MINUTES)
				);
	const dropoffTime =
		insertionCase.direction == InsertDirection.FROM_BUS_STOP
			? new Date(
					arrivalWindow.startTime.getTime() +
						travelDuration +
						minutesToMs(BUFFER_TIME + PASSENGER_CHANGE_MINUTES)
				)
			: arrivalWindow.endTime;
	const departure = comesFromCompany(insertionCase)
			? new Date(pickupTime.getTime() - approachDuration)
			: undefined;
	const arrival = returnsToCompany(insertionCase)
			? new Date(dropoffTime.getTime() + returnDuration)
			: undefined;
	let taxiWaitingDelta = getTaxiWaitingDelta(insertionCase, approachDuration, returnDuration, travelDuration, departure, arrival, prev, next);
	
	return {
		pickupTime,
		dropoffTime,
		pickupCase: structuredClone(insertionCase),
		dropoffCase: structuredClone(insertionCase),
		passengerDuration: travelDuration,
		taxiDuration: taxiDurationDelta,
		taxiWaitingTime: taxiWaitingDelta,
		cost: computeCost(travelDuration, taxiDurationDelta, taxiWaitingDelta),
		departure,
		arrival,
		pickupApproachDuration: approachDuration,
		pickupReturnDuration: travelDuration,
		dropoffApproachDuration: travelDuration,
		dropoffReturnDuration: returnDuration
	};
}

export function evaluateSingleInsertion(
	insertionCase: InsertionType,
	windows: Interval[],
	busStopWindow: Interval | undefined,
	routingResults: RoutingResults,
	insertionInfo: InsertionInfo,
	busStopIdx: number | undefined,
	prev: Event | undefined,
	next: Event | undefined
): SingleInsertionEvaluation | undefined {
	console.assert(insertionCase.what != InsertWhat.BOTH);
	const approachDuration = getApproachDuration(
		insertionCase,
		routingResults,
		insertionInfo,
		busStopIdx,
		prev
	);
	const returnDuration = getReturnDuration(
		insertionCase,
		routingResults,
		insertionInfo,
		busStopIdx,
		next
	);
	if (approachDuration == undefined || returnDuration == undefined) {
		return undefined;
	}
	const arrivalWindow = getArrivalWindow(
		insertionCase,
		windows,
		0,
		busStopWindow,
		approachDuration,
		returnDuration
	);
	if (arrivalWindow == undefined) {
		return undefined;
	}
	const passengerDuration =
		(insertionCase.what == InsertWhat.BUS_STOP) ==
		(insertionCase.direction == InsertDirection.FROM_BUS_STOP)
			? returnDuration - minutesToMs(PASSENGER_CHANGE_MINUTES)
			: approachDuration;
	const taxiDuration = approachDuration + returnDuration;
	const time = insertionCase.direction == InsertDirection.FROM_BUS_STOP
	? arrivalWindow.endTime
	: arrivalWindow.startTime;
	const taxiWaitingTime = getTaxiWaitingDelta(insertionCase, approachDuration, returnDuration, 0, new Date(time.getTime() - approachDuration), new Date(time.getTime() + returnDuration), prev, next);
	const sie: SingleInsertionEvaluation = {
		time,
		window: arrivalWindow,
		approachDuration: approachDuration,
		returnDuration: returnDuration,
		case: structuredClone(insertionCase),
		passengerDuration,
		taxiDuration,
		taxiWaitingTime,
		cost: computeCost(passengerDuration, taxiDuration, taxiWaitingTime)
	};
	return sie;
}

export function evaluateNewTours(
	companies: Company[],
	required: Capacities,
	startFixed: boolean,
	expandedSearchInterval: Interval,
	busStopTimes: Interval[][],
	routingResults: RoutingResults,
	travelDurations: (number|undefined)[]
): (InsertionEvaluation | undefined)[][] {
	const bestEvaluations: (InsertionEvaluation | undefined)[][] = new Array<
		(InsertionEvaluation | undefined)[]
	>(busStopTimes.length);
	for (let i = 0; i != busStopTimes.length; ++i) {
		bestEvaluations[i] = new Array<InsertionEvaluation | undefined>(busStopTimes[i].length);
	}
	const insertionCase = {
		how: InsertHow.NEW_TOUR,
		what: InsertWhat.BOTH,
		where: InsertWhere.BEFORE_FIRST_EVENT,
		direction: startFixed ? InsertDirection.FROM_BUS_STOP : InsertDirection.TO_BUS_STOP
	};
	const prepTime = new Date(Date.now() + minutesToMs(MIN_PREP_MINUTES));

	companies.forEach((company, companyIdx) => {
		company.vehicles.forEach((vehicle) => {
			const insertionInfo: InsertionInfo = {
				companyIdx,
				prevEventIdxInRoutingResults: 1,
				nextEventIdxInRoutingResults: 1,
				vehicle,
				idxInEvents: 1,
				currentRange: { earliestPickup: 0, latestDropoff: 0 }
			};
			if (!isValid(vehicle.capacities, required)) {
				return;
			}
			const windows = getAllowedOperationTimes(
				insertionCase,
				undefined,
				undefined,
				expandedSearchInterval,
				prepTime,
				vehicle
			);
			for (let busStopIdx = 0; busStopIdx != busStopTimes.length; ++busStopIdx) {
				for (let busTimeIdx = 0; busTimeIdx != busStopTimes[busStopIdx].length; ++busTimeIdx) {
					const resultNewTour = evaluateBothInsertion(
						insertionCase,
						windows,
						travelDurations[busStopIdx],
						busStopTimes[busStopIdx][busTimeIdx],
						routingResults,
						insertionInfo,
						busStopIdx,
						undefined,
						undefined
					);
					if (
						resultNewTour != undefined &&
						(bestEvaluations[busStopIdx][busTimeIdx] == undefined ||
							resultNewTour.cost < bestEvaluations[busStopIdx][busTimeIdx]!.cost)
					) {
						bestEvaluations[busStopIdx][busTimeIdx] = {
							...resultNewTour,
							company: companyIdx,
							vehicle: vehicle.id,
							tour: undefined
						};
					}
				}
			}
		});
	});
	return bestEvaluations;
}

export function evaluateSingleInsertions(
	companies: Company[],
	startFixed: boolean,
	expandedSearchInterval: Interval,
	insertionRanges: Map<number, Range[]>,
	busStopTimes: Interval[][],
	routingResults: RoutingResults,
	travelDurations: (number|undefined)[]
): Evaluations {
	const bothEvaluations: (InsertionEvaluation | undefined)[][] = [];
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
		bothEvaluations[i] = new Array<InsertionEvaluation | undefined>(busStopTimes[i].length);
	}
	const prepTime = new Date(Date.now() + minutesToMs(MIN_PREP_MINUTES));
	const direction = startFixed ? InsertDirection.FROM_BUS_STOP : InsertDirection.TO_BUS_STOP;

	iterateAllInsertions(
		companies,
		insertionRanges,
		(insertionInfo: InsertionInfo, insertionCounter: number) => {
			const prev: Event | undefined =
				insertionInfo.idxInEvents == 0
					? insertionInfo.vehicle.lastEventBefore
					: insertionInfo.vehicle.events[insertionInfo.idxInEvents - 1];
			const next: Event | undefined =
				insertionInfo.idxInEvents == insertionInfo.vehicle.events.length
					? insertionInfo.vehicle.firstEventAfter
					: insertionInfo.vehicle.events[insertionInfo.idxInEvents];
			INSERTION_TYPES.forEach((insertHow) => {
				const insertionCase = {
					how: insertHow,
					where:
						insertionInfo.idxInEvents == 0
							? InsertWhere.BEFORE_FIRST_EVENT
							: insertionInfo.idxInEvents == insertionInfo.vehicle.events.length
								? InsertWhere.AFTER_LAST_EVENT
								: prev!.tourId != next!.tourId
									? InsertWhere.BETWEEN_TOURS
									: InsertWhere.BETWEEN_EVENTS,
					what: InsertWhat.BUS_STOP,
					direction
				};
				if (!canCaseBeValid(insertionCase)) {
					return undefined;
				}
				const windows = getAllowedOperationTimes(
					insertionCase,
					prev,
					next,
					expandedSearchInterval,
					prepTime,
					insertionInfo.vehicle
				);
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
							next
						);
						if (
							resultBoth != undefined &&
							(bothEvaluations[busStopIdx][busTimeIdx] == undefined ||
								resultBoth.cost < bothEvaluations[busStopIdx][busTimeIdx]!.cost)
						) {bothEvaluations[busStopIdx][busTimeIdx] = {
								...resultBoth,
								company: insertionInfo.companyIdx,
								vehicle: insertionInfo.vehicle.id,
								tour: insertionCase.how == InsertHow.APPEND ? prev?.tourId : next?.tourId
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
							next
						);
						if (
							resultBus != undefined &&
							(busStopEvaluations[busStopIdx][busTimeIdx] == undefined ||
								busStopEvaluations[busStopIdx][busTimeIdx][insertionCounter] == undefined ||
								resultBus.cost < busStopEvaluations[busStopIdx][busTimeIdx][insertionCounter]!.cost)
						) {
							busStopEvaluations[busStopIdx][busTimeIdx][insertionCounter] = resultBus;
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
					next
				);
				if (
					resultUserChosen != undefined &&
					(userChosenEvaluations[insertionCounter] == undefined ||
						resultUserChosen.cost < userChosenEvaluations[insertionCounter].cost)
				) {
					userChosenEvaluations[insertionCounter] = resultUserChosen;
				}
			});
		}
	);
	return { busStopEvaluations, userChosenEvaluations, bothEvaluations };
}

export function evaluatePairInsertions(
	companies: Company[],
	startFixed: boolean,
	insertionRanges: Map<number, Range[]>,
	busStopTimes: Interval[][],
	busStopEvaluations: (SingleInsertionEvaluation | undefined)[][][],
	userChosenEvaluations: (SingleInsertionEvaluation | undefined)[]
): (InsertionEvaluation | undefined)[][] {
	const bestEvaluations: (InsertionEvaluation | undefined)[][] = new Array<
		(InsertionEvaluation | undefined)[]
	>(busStopTimes.length);
	for (let i = 0; i != busStopTimes.length; ++i) {
		bestEvaluations[i] = new Array<InsertionEvaluation | undefined>(busStopTimes[i].length);
	}
	iterateAllInsertions(
		companies,
		insertionRanges,
		(insertionInfo: InsertionInfo, insertionCounter: number) => {
			const pickupIdx = insertionCounter;
			for (let busStopIdx = 0; busStopIdx != busStopTimes.length; ++busStopIdx) {
				for (let timeIdx = 0; timeIdx != busStopTimes[busStopIdx].length; ++timeIdx) {
					const pickup = startFixed
						? busStopEvaluations[busStopIdx][timeIdx][pickupIdx]
						: userChosenEvaluations[pickupIdx];
					if (pickup == undefined) {
						continue;
					}
					for (
						let dropoffIdx = pickupIdx + 1;
						dropoffIdx <= insertionInfo.currentRange.latestDropoff;
						++dropoffIdx
					) {
						const dropoff = startFixed
							? userChosenEvaluations[dropoffIdx]
							: busStopEvaluations[busStopIdx][timeIdx][dropoffIdx];
						if (dropoff == undefined) {
							continue;
						}
						const passengerDuration = dropoff.time!.getTime() - pickup.time!.getTime();

						const taxiDuration =
							passengerDuration +
							pickup.approachDuration +
							dropoff.returnDuration +
							2 * minutesToMs(PASSENGER_CHANGE_MINUTES);
						const taxiWaitingTime = dropoff.taxiWaitingTime + pickup.taxiWaitingTime;
						const cost = computeCost(passengerDuration, taxiDuration, taxiWaitingTime);
						if (
							bestEvaluations[busStopIdx][timeIdx] == undefined ||
							cost < bestEvaluations[busStopIdx][timeIdx]!.cost
						) {
							bestEvaluations[busStopIdx][timeIdx] = {
								pickupTime: pickup.time,
								dropoffTime: dropoff.time,
								pickupCase: pickup.case,
								dropoffCase: dropoff.case,
								taxiWaitingTime,
								taxiDuration,
								passengerDuration,
								cost,
								company: insertionInfo.companyIdx,
								vehicle: insertionInfo.vehicle.id,
								tour: 1, // TODO,
								departure: comesFromCompany(pickup.case)
									? new Date(pickup.time.getTime() - pickup.approachDuration)
									: undefined,
								arrival: returnsToCompany(dropoff.case)
									? new Date(dropoff.time.getTime() + dropoff.returnDuration)
									: undefined,
								pickupApproachDuration: pickup.approachDuration,
								pickupReturnDuration: pickup.returnDuration,
								dropoffApproachDuration: dropoff.approachDuration,
								dropoffReturnDuration: dropoff.returnDuration
							};
						}
					}
				}
			}
		}
	);
	return bestEvaluations;
}

const computeCost = (passengerDuration: number, taxiDuration: number, taxiWaitingTime: number) => {
	return (
		TAXI_DRIVING_TIME_COST_FACTOR * taxiDuration +
		PASSENGER_TIME_COST_FACTOR * passengerDuration +
		TAXI_WAITING_TIME_COST_FACTOR * taxiWaitingTime
	);
};

export const takeBest = (
	evals1: (InsertionEvaluation | undefined)[][],
	evals2: (InsertionEvaluation | undefined)[][]
): (InsertionEvaluation | undefined)[][] => {
	const takeBetter = (e1: InsertionEvaluation|undefined, e2: InsertionEvaluation|undefined) => {
		if(e1==undefined){
			return e2;
		}
		if(e2==undefined){
			return e1;
		}
		return e1.cost<e2.cost?e1:e2;
	}
	console.assert(
		evals1.length == evals2.length,
		'in takeBest, evaluations do not have matching length.'
	);
	const result = new Array<(InsertionEvaluation | undefined)[]>(evals1.length);
	for (let busStopIdx = 0; busStopIdx != evals1.length; ++busStopIdx) {
		console.assert(
			evals1[busStopIdx].length == evals2[busStopIdx].length,
			"in takeBest, evaluations' inner arrays do not have matching length."
		);
		result[busStopIdx] = new Array<InsertionEvaluation | undefined>(evals1[busStopIdx].length);
		for (let timeIdx = 0; timeIdx != evals1[busStopIdx].length; ++timeIdx) {
			const e1 = evals1[busStopIdx][timeIdx];
			const e2 = evals2[busStopIdx][timeIdx];
			result[busStopIdx][timeIdx] =
				takeBetter(e1,e2);
		}
	}
	return result;
};

function getTaxiWaitingDelta(
	insertionCase: InsertionType,
	approachDuration: number,
	returnDuration: number,
	travelDuration: number,
	departure: Date|undefined,
	arrival: Date|undefined,
	prev: Event | undefined,
	next: Event | undefined
): number {
	if(insertionCase.how == InsertHow.NEW_TOUR){
		return 0;
	}
	let oldWaitingTime;
	if(insertionCase.how == InsertHow.APPEND || insertionCase.how == InsertHow.PREPEND){
		oldWaitingTime = 0;
	}else{
		console.assert(prev!=undefined&&next!=undefined);
		oldWaitingTime = next!.communicated.getTime() - prev!.communicated.getTime() - prev!.returnDuration;
	}
	const prevTask: number = insertionCase.how == InsertHow.PREPEND ? departure!.getTime() : prev!.communicated.getTime()
	const nextTask: number = insertionCase.how == InsertHow.APPEND ? arrival!.getTime() : next!.communicated.getTime();
	const newWaitingTime = nextTask - prevTask - approachDuration - travelDuration - returnDuration;
	console.assert(newWaitingTime>=0, "Waiting time is negative.");
	return newWaitingTime -  oldWaitingTime;
}
