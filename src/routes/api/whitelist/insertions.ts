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
	isCaseValid,
	type InsertionInfo,
	type InsertionType
} from './insertionTypes';
import type { Capacities } from '$lib/capacities';
import {
	comesFromCompany,
	getAllowedOperationTimes,
	getApproachDuration,
	getArrivalWindow,
	getReturnDuration,
	getTaxiWaitingTime,
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
	travelDuration: number,
	busStopWindow: Interval | undefined,
	routingResults: RoutingResults,
	insertionInfo: InsertionInfo,
	busStopIdx: number | undefined,
	prev: Event | undefined,
	next: Event | undefined
) {
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
		approachDuration > MAX_TRAVEL_MS + minutesToMs(BUFFER_TIME) ||
		returnDuration > MAX_TRAVEL_MS + minutesToMs(BUFFER_TIME + PASSENGER_CHANGE_MINUTES) ||
		travelDuration > MAX_TRAVEL_MS
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
	const taxiDuration =
		approachDuration +
		returnDuration +
		travelDuration +
		minutesToMs(BUFFER_TIME + PASSENGER_CHANGE_MINUTES) -
		(prev == undefined
			? next == undefined
				? 0
				: next.approachDuration
			: next == undefined || next.tourId == prev.tourId
				? prev.returnDuration
				: prev.returnDuration + next.approachDuration);
	const taxiWaitingTime = getTaxiWaitingTime(insertionCase, approachDuration, prev, next);
	const pickupTime = 
	insertionCase.direction == InsertDirection.FROM_BUS_STOP
		? arrivalWindow.endTime
		: new Date(
				arrivalWindow.startTime.getTime() -
					travelDuration -
					minutesToMs(BUFFER_TIME + PASSENGER_CHANGE_MINUTES)
			);
	const dropoffTime = 
	insertionCase.direction == InsertDirection.FROM_BUS_STOP
		? new Date(
				arrivalWindow.endTime.getTime() +
					travelDuration +
					minutesToMs(BUFFER_TIME + PASSENGER_CHANGE_MINUTES)
			)
		: arrivalWindow.startTime;
	return {
		pickupTime,
		dropoffTime,
		pickupCase: insertionCase,
		dropoffCase: insertionCase,
		passengerDuration: travelDuration,
		taxiDuration,
		taxiWaitingTime,
		cost: computeCost(travelDuration, taxiDuration, taxiWaitingTime),
		departure: comesFromCompany(insertionCase) ? new Date(pickupTime.getTime() - approachDuration) : undefined,
		arrival: returnsToCompany(insertionCase) ? new Date(dropoffTime.getTime() + returnDuration) : undefined
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
	if (approachDuration > MAX_TRAVEL_MS || returnDuration > MAX_TRAVEL_MS) {
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
	const taxiWaitingTime = getTaxiWaitingTime(insertionCase, approachDuration, prev, next);
	const sie: SingleInsertionEvaluation = {
		time:
			insertionCase.direction == InsertDirection.FROM_BUS_STOP
				? arrivalWindow.endTime
				: arrivalWindow.startTime,
		window: arrivalWindow,
		approachDuration: approachDuration,
		returnDuration: returnDuration,
		case: insertionCase,
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
	travelDurations: number[]
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
				insertionIdx: 1,
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
				if (!company.busStopFilter[busStopIdx]) {
					continue;
				}
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
	travelDurations: number[]
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
		bothEvaluations[i] = new Array<InsertionEvaluation | undefined>(busStopTimes[i].length);
	}
	const prepTime = new Date(Date.now() + minutesToMs(MIN_PREP_MINUTES));

	iterateAllInsertions(
		companies,
		insertionRanges,
		(insertionInfo: InsertionInfo, insertionCounter: number, busStopFilter: boolean[]) => {
			const prev: Event | undefined =
				insertionInfo.insertionIdx == 0
					? insertionInfo.vehicle.lastEventBefore
					: insertionInfo.vehicle.events[insertionInfo.insertionIdx - 1];
			const next: Event | undefined =
				insertionInfo.insertionIdx == insertionInfo.vehicle.events.length
					? insertionInfo.vehicle.firstEventAfter
					: insertionInfo.vehicle.events[insertionInfo.insertionIdx];
			INSERTION_TYPES.forEach((insertHow) => {
				const insertionCase = {
					how: insertHow,
					where:
						insertionCounter == 0
							? InsertWhere.BEFORE_FIRST_EVENT
							: insertionCounter == insertionInfo.vehicle.events.length
								? InsertWhere.AFTER_LAST_EVENT
								: prev!.tourId != next!.tourId
									? InsertWhere.BETWEEN_TOURS
									: InsertWhere.BETWEEN_EVENTS,
					what: InsertWhat.BUS_STOP,
					direction: startFixed ? InsertDirection.FROM_BUS_STOP : InsertDirection.TO_BUS_STOP
				};
				if (!isCaseValid(insertionCase)) {
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
					if (!busStopFilter[busStopIdx]) {
						continue;
					}
					for (let busTimeIdx = 0; busTimeIdx != busStopTimes[busStopIdx].length; ++busTimeIdx) {
						insertionCase.what = InsertWhat.BUS_STOP;
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
							(busStopEvaluations[busStopIdx][busTimeIdx][insertionCounter] == undefined ||
								resultBus.cost < busStopEvaluations[busStopIdx][busTimeIdx][insertionCounter]!.cost)
						) {
							busStopEvaluations[busStopIdx][busTimeIdx].push(resultBus);
						}

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
						) {
							bothEvaluations[busStopIdx][busTimeIdx] = {
								...resultBoth,
								company: insertionInfo.companyIdx,
								vehicle: insertionInfo.vehicle.id,
								tour: insertionCase.how == InsertHow.APPEND ? prev?.tourId : next?.tourId
							};
						}
					}
				}
				insertionCase.what = InsertWhat.USER_CHOSEN;
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
		(insertionInfo: InsertionInfo, insertionCounter: number, busStopFilter: boolean[]) => {
			const pickupIdx = insertionCounter;
			for (let busStopIdx = 0; busStopIdx != busStopFilter.length; ++busStopIdx) {
				if (!busStopFilter[busStopIdx]) {
					continue;
				}
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
								departure: comesFromCompany(pickup.case) ? new Date(pickup.time.getTime() - pickup.approachDuration) : undefined,
								arrival: returnsToCompany(dropoff.case) ? new Date(dropoff.time.getTime() + dropoff.returnDuration) : undefined
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
				e1 == undefined ? e2 : e2 == undefined ? e1 : e1.cost < e2.cost ? e1 : e2;
		}
	}
	return result;
};
