import type { Company, Event } from '$lib/compositionTypes';
import { Interval } from '$lib/interval';
import { iterateAllInsertions } from './utils';
import { type RoutingResults } from './routing';
import { isValid, type Range } from './capacitySimulation';
import { addBuffer, addPassengerChangeTime, minutesToMs } from '$lib/time_utils';
import {
	MIN_PREP_MINUTES,
	PASSENGER_CHANGE_MINUTES,
	PASSENGER_TIME_COST_FACTOR,
	TAXI_DRIVING_TIME_COST_FACTOR,
	TAXI_WAITING_TIME_COST_FACTOR
} from '$lib/constants';
import {
	InsertDirection,
	InsertHow,
	INSERT_HOW_OPTIONS,
	InsertWhat,
	InsertWhere,
	canCaseBeValid,
	type InsertionInfo,
	type InsertionType,
	isCaseValid,
	printInsertionType,
	isEarlierBetter
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
import type { PromisedTimes } from './promisedTimes';
import { oneToMany } from '$lib/api';
import type { Coordinates } from '$lib/location';

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
	pickupIdx: number|undefined;
	dropoffIdx: number|undefined;
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

export type NeighbourIds = {
	prevPickup: number | undefined;
	nextPickup: number | undefined;
	prevDropoff: number | undefined;
	nextDropoff: number | undefined;
};

export function printInsertionEvaluation(e: InsertionEvaluation) {
	return (
		'pickupTime: ' +
		e.pickupTime.toISOString() +
		'\n' +
		'dropoffTime: ' +
		e.dropoffTime.toISOString() +
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
		'company: ' +
		e.company +
		'\n' +
		'vehicle: ' +
		e.vehicle +
		'\n' +
		'tour: ' +
		e.tour +
		'\n' +
		'departure: ' +
		e.departure?.toISOString() +
		'\n' +
		'arrival: ' +
		e.arrival?.toISOString() +
		'\n' +
		'pickupApproachDuration: ' +
		e.pickupApproachDuration +
		'\n' +
		'pickupReturnDuration: ' +
		e.pickupReturnDuration +
		'\n' +
		'dropoffApproachDuration: ' +
		e.dropoffApproachDuration +
		'\n' +
		'dropoffReturnDuration: ' +
		e.dropoffReturnDuration +
		'\n'
	);
}

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
	travelDuration: number | undefined,
	busStopWindow: Interval | undefined,
	routingResults: RoutingResults,
	insertionInfo: InsertionInfo,
	busStopIdx: number | undefined,
	prev: Event | undefined,
	next: Event | undefined,
	promisedTimes?: PromisedTimes
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
	if (approachDuration == undefined || returnDuration == undefined || travelDuration == undefined) {
		return undefined;
	}
	travelDuration = addPassengerChangeTime(addBuffer(travelDuration));
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
	if (
		promisedTimes != undefined &&
		!keepsPromises(insertionCase, arrivalWindow, travelDuration, promisedTimes)
	) {
		return undefined;
	}
	const taxiDurationDelta =
		approachDuration +
		returnDuration +
		travelDuration -
		getOldDrivingTime(insertionCase, prev, next);

	const pickupTime =
		insertionCase.direction == InsertDirection.FROM_BUS_STOP
			? arrivalWindow.startTime
			: new Date(arrivalWindow.endTime.getTime() - travelDuration);
	const dropoffTime =
		insertionCase.direction == InsertDirection.FROM_BUS_STOP
			? new Date(arrivalWindow.startTime.getTime() + travelDuration)
			: arrivalWindow.endTime;
	const departure = comesFromCompany(insertionCase)
		? new Date(pickupTime.getTime() - approachDuration)
		: undefined;
	const arrival = returnsToCompany(insertionCase)
		? new Date(dropoffTime.getTime() + returnDuration)
		: undefined;
	const taxiWaitingDelta = getTaxiWaitingDelta(
		approachDuration + returnDuration + travelDuration,
		insertionCase,
		departure,
		arrival,
		prev,
		next
	);
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
	next: Event | undefined,
	promisedTime: Date | undefined
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
	if (promisedTime != undefined && !arrivalWindow.covers(promisedTime)) {
		return undefined;
	}
	const passengerDuration =
		(insertionCase.what == InsertWhat.BUS_STOP) ==
		(insertionCase.direction == InsertDirection.FROM_BUS_STOP)
			? returnDuration - minutesToMs(PASSENGER_CHANGE_MINUTES)
			: approachDuration;
	const taxiDuration =
		approachDuration + returnDuration - getOldDrivingTime(insertionCase, prev, next);
	console.assert(insertionCase.what != InsertWhat.BOTH);
	const time = isEarlierBetter(insertionCase)
			? arrivalWindow.startTime
			: arrivalWindow.endTime;
	const taxiWaitingTime = getTaxiWaitingDelta(
		approachDuration + returnDuration,
		insertionCase,
		new Date(time.getTime() - approachDuration),
		new Date(time.getTime() + returnDuration),
		prev,
		next
	);
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
	travelDurations: (number | undefined)[],
	promisedTimes?: PromisedTimes
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
						undefined,
						promisedTimes
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
							tour: undefined,
							pickupIdx: undefined,
							dropoffIdx: undefined
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
	travelDurations: (number | undefined)[],
	promisedTimes?: PromisedTimes
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
			INSERT_HOW_OPTIONS.forEach((insertHow) => {
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
							next,
							promisedTimes
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
								tour: insertionCase.how == InsertHow.APPEND ? prev!.tourId : next!.tourId,
								pickupIdx: insertionInfo.idxInEvents,
								dropoffIdx: insertionInfo.idxInEvents
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
							insertionCase.direction == InsertDirection.FROM_BUS_STOP
								? promisedTimes?.pickup
								: promisedTimes?.dropoff
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
					next,
					insertionCase.direction != InsertDirection.FROM_BUS_STOP
						? promisedTimes?.pickup
						: promisedTimes?.dropoff
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

export type CompanyIdx = number;
export type VehicleIdx = number;
export type EventIdx = number;

type RR = {
	cIdx: number;
	vIdx: number;
	eIdx: number;
	coordinates1: Coordinates;
	coordinates2: Coordinates;
};

async function routeTourGaps(companies: Company[]) {
	const ret = new Map<CompanyIdx, Map<VehicleIdx, Map<EventIdx, number | undefined>>>();
	companies.forEach((c, cIdx) => {
		ret.set(cIdx, new Map<VehicleIdx, Map<EventIdx, number>>());
		c.vehicles.forEach((v, vIdx) => {
			ret.get(cIdx)!.set(vIdx, new Map<EventIdx, number>());
			v.events.forEach((_, eIdx) => ret.get(cIdx)!.get(vIdx)!.set(eIdx, 0));
		});
	});
	const routingRequests: RR[] = [];
	for (let cIdx = 0; cIdx != companies.length; ++cIdx) {
		const company = companies[cIdx];
		for (let vIdx = 0; vIdx != companies[vIdx].vehicles.length; ++vIdx) {
			const events = company.vehicles[vIdx].events;
			for (let eIdx = 1; eIdx != events.length; ++eIdx) {
				const e1 = events[eIdx - 1];
				const e2 = events[eIdx];
				if (e1.tourId != e2.tourId) {
					routingRequests.push({
						cIdx,
						vIdx,
						eIdx,
						coordinates1: e1.coordinates,
						coordinates2: e2.coordinates
					});
				}
			}
		}
	}
	const promises = routingRequests.map((rr) =>
		oneToMany(rr.coordinates1, [rr.coordinates2], false)
	);
	const result = await Promise.all(promises);
	for (let i = 0; i != routingRequests.length; ++i) {
		const rr = routingRequests[i];
		ret.get(rr.cIdx)!.get(rr.vIdx)!.set(rr.eIdx, result[0][i]);
	}
	return ret;
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
			const events = insertionInfo.vehicle.events;
			const pickupIdx = insertionInfo.idxInEvents;
			let cumulatedTaxiDrivingDelta = 0;
			let cumulatedTaxiWaitingDelta = 0;
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
							? busStopEvaluations[busStopIdx][timeIdx][pickupIdx]
							: userChosenEvaluations[pickupIdx];
						if (pickup == undefined) {
							pickupInvalid = true;
							break;
						}
						const dropoff = startFixed
							? userChosenEvaluations[dropoffIdx]
							: busStopEvaluations[busStopIdx][timeIdx][dropoffIdx];
						if (dropoff == undefined) {
							continue;
						}
						const passengerDuration = dropoff.time!.getTime() - pickup.time!.getTime();

						const taxiDuration =
							pickup.taxiDuration + dropoff.taxiDuration + cumulatedTaxiDrivingDelta;
						const taxiWaitingTime =
							dropoff.taxiWaitingTime + pickup.taxiWaitingTime + cumulatedTaxiWaitingDelta;
						const cost = computeCost(passengerDuration, taxiDuration, taxiWaitingTime);
						if (
							bestEvaluations[busStopIdx][timeIdx] == undefined ||
							cost < bestEvaluations[busStopIdx][timeIdx]!.cost
						) {
							const tour = events[pickupIdx].tourId;
							bestEvaluations[busStopIdx][timeIdx] = {
								pickupTime: pickup.time,
								dropoffTime: dropoff.time,
								pickupCase: pickup.case,
								dropoffCase: dropoff.case,
								pickupIdx,
								dropoffIdx,
								taxiWaitingTime,
								taxiDuration,
								passengerDuration,
								cost,
								company: insertionInfo.companyIdx,
								vehicle: insertionInfo.vehicle.id,
								tour,
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
				const prevDropoffIdx = dropoffIdx - 1;
				if (
					dropoffIdx != events.length &&
					events[prevDropoffIdx].tourId != events[dropoffIdx].tourId
				) {
					const drivingTime = events[dropoffIdx].direct_driving_duration;
					if (drivingTime == null) {
						return;
					}
					cumulatedTaxiDrivingDelta +=
						drivingTime -
						events[dropoffIdx].returnDuration -
						events[prevDropoffIdx].approachDuration;
					cumulatedTaxiWaitingDelta +=
						events[dropoffIdx].communicated.getTime() -
						events[prevDropoffIdx].communicated.getTime() -
						drivingTime;
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
	const takeBetter = (e1: InsertionEvaluation | undefined, e2: InsertionEvaluation | undefined) => {
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
			result[busStopIdx][timeIdx] = takeBetter(e1, e2);
		}
	}
	return result;
};

function getTaxiWaitingDelta(
	drivingDuration: number,
	insertionCase: InsertionType,
	departure: Date | undefined,
	arrival: Date | undefined,
	prev: Event | undefined,
	next: Event | undefined
): number {
	if (insertionCase.how == InsertHow.NEW_TOUR) {
		return 0;
	}
	const oldWaitingTime =
		insertionCase.how == InsertHow.INSERT
			? next!.communicated.getTime() - prev!.communicated.getTime() - prev!.returnDuration
			: 0;
	const prevTask: number =
		insertionCase.how == InsertHow.PREPEND ? departure!.getTime() : prev!.communicated.getTime();
	const nextTask: number =
		insertionCase.how == InsertHow.APPEND ? arrival!.getTime() : next!.communicated.getTime();
	const newWaitingTime = nextTask - prevTask - drivingDuration;
	console.assert(newWaitingTime >= 0, 'Waiting time is negative.');
	return newWaitingTime - oldWaitingTime;
}

const getOldDrivingTime = (
	insertionCase: InsertionType,
	prev: Event | undefined,
	next: Event | undefined
): number => {
	if (insertionCase.how == InsertHow.NEW_TOUR) {
		return 0;
	}
	if (insertionCase.how == InsertHow.CONNECT) {
		return next!.approachDuration + prev!.returnDuration;
	}
	console.assert(prev != undefined || next != undefined);
	if (prev == undefined) {
		console.assert(insertionCase.how == InsertHow.PREPEND);
		return next!.approachDuration;
	}
	return prev.returnDuration;
};

const keepsPromises = (
	insertionCase: InsertionType,
	arrivalWindow: Interval,
	travelDuration: number,
	promisedTimes: PromisedTimes
): boolean => {
	const w = arrivalWindow.shift(
		insertionCase.direction == InsertDirection.FROM_BUS_STOP ? travelDuration : -travelDuration
	);
	const pickupWindow = insertionCase.direction == InsertDirection.FROM_BUS_STOP ? arrivalWindow : w;
	const dropoffWindow =
		insertionCase.direction != InsertDirection.FROM_BUS_STOP ? arrivalWindow : w;
	let checkPickup = false;
	let checkDropoff = false;
	switch (insertionCase.what) {
		case InsertWhat.BOTH:
			checkPickup = true;
			checkDropoff = true;
			break;
		case InsertWhat.BUS_STOP:
			if (insertionCase.direction == InsertDirection.FROM_BUS_STOP) {
				checkPickup = true;
			} else {
				checkDropoff = true;
			}
			break;
		case InsertWhat.USER_CHOSEN:
			if (insertionCase.direction != InsertDirection.FROM_BUS_STOP) {
				checkPickup = true;
			} else {
				checkDropoff = true;
			}
	}
	if (checkPickup && !pickupWindow.covers(promisedTimes.pickup)) {
		return false;
	}
	if (checkDropoff && !dropoffWindow.covers(promisedTimes.dropoff)) {
		return false;
	}
	return true;
};
