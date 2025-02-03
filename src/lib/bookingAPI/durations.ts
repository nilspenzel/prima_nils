import type { Event, Vehicle } from '$lib/compositionTypes';
import { MAX_TRAVEL_MS } from '$lib/constants';
import { Interval } from '$lib/interval';
import { addBuffer, addPassengerChangeTime } from '$lib/time_utils';
import {
	InsertDirection,
	InsertHow,
	InsertWhat,
	type InsertionInfo,
	type InsertionType
} from './insertionTypes';
import type { InsertionRoutingResult, RoutingResults } from './routing';

export const returnsToCompany = (insertionCase: InsertionType): boolean => {
	return insertionCase.how == InsertHow.APPEND || insertionCase.how == InsertHow.NEW_TOUR;
};

export const comesFromCompany = (insertionCase: InsertionType): boolean => {
	return insertionCase.how == InsertHow.PREPEND || insertionCase.how == InsertHow.NEW_TOUR;
};

export const getApproachDuration = (
	insertionCase: InsertionType,
	routingResults: RoutingResults,
	insertionInfo: InsertionInfo,
	busStopIdx: number | undefined,
	prev: Event | undefined
): number | undefined => {
	if (prev == undefined) {
		//	return MAX_TRAVEL_MS;
	}
	let relevantRoutingResults: InsertionRoutingResult | undefined = undefined;
	switch (insertionCase.what) {
		case InsertWhat.USER_CHOSEN:
			relevantRoutingResults = routingResults.userChosen;
			break;
		case InsertWhat.BOTH:
			console.assert(busStopIdx != undefined);
			relevantRoutingResults =
				insertionCase.direction == InsertDirection.FROM_BUS_STOP
					? routingResults.busStops[busStopIdx!]
					: routingResults.userChosen;
			break;
		case InsertWhat.BUS_STOP:
			console.assert(busStopIdx != undefined);
			relevantRoutingResults = routingResults.busStops[busStopIdx!];
			break;
	}
	console.assert(relevantRoutingResults != undefined);
	const drivingTime = comesFromCompany(insertionCase)
		? relevantRoutingResults.company[insertionInfo.companyIdx]
		: relevantRoutingResults.event[insertionInfo.prevEventIdxInRoutingResults];
	if (drivingTime == undefined || drivingTime > MAX_TRAVEL_MS) {
		return undefined;
	}
	return addBuffer(drivingTime);
};

export const getReturnDuration = (
	insertionCase: InsertionType,
	routingResults: RoutingResults,
	insertionInfo: InsertionInfo,
	busStopIdx: number | undefined,
	next: Event | undefined
): number | undefined => {
	if (next == undefined) {
		//return MAX_TRAVEL_MS;
	}
	let relevantRoutingResults: InsertionRoutingResult | undefined = undefined;
	switch (insertionCase.what) {
		case InsertWhat.USER_CHOSEN:
			relevantRoutingResults = routingResults.userChosen;
			break;
		case InsertWhat.BOTH:
			console.assert(busStopIdx != undefined);
			relevantRoutingResults =
				insertionCase.direction == InsertDirection.FROM_BUS_STOP
					? routingResults.userChosen
					: routingResults.busStops[busStopIdx!];
			break;
		case InsertWhat.BUS_STOP:
			console.assert(busStopIdx != undefined);
			relevantRoutingResults = routingResults.busStops[busStopIdx!];
			break;
	}
	const drivingTime = returnsToCompany(insertionCase)
		? relevantRoutingResults.company[insertionInfo.companyIdx]
		: relevantRoutingResults.event[insertionInfo.nextEventIdxInRoutingResults];
	if (drivingTime == undefined || drivingTime > MAX_TRAVEL_MS) {
		return undefined;
	}
	return addPassengerChangeTime(addBuffer(drivingTime));
};

export function getAllowedOperationTimes(
	insertionCase: InsertionType,
	prev: Event | undefined,
	next: Event | undefined,
	expandedSearchInterval: Interval,
	prepTime: Date,
	vehicle: Vehicle
): Interval[] {
	const windowEndTime =
		next == undefined
			? expandedSearchInterval.endTime
			: returnsToCompany(insertionCase)
				? next.departure
				: next.communicated;
	if (windowEndTime < prepTime) {
		return [];
	}
	let windowStartTime =
		prev == undefined
			? expandedSearchInterval.startTime
			: comesFromCompany(insertionCase)
				? prev.arrival
				: prev.communicated;
	windowStartTime = new Date(Math.max(windowStartTime.getTime(), prepTime.getTime()));
	const window = new Interval(windowStartTime, windowEndTime);
	if (insertionCase.how == InsertHow.INSERT) {
		return [window];
	}
	const relevantAvailabilities = (() => {
		switch (insertionCase.how) {
			case InsertHow.APPEND:
				return vehicle.availabilities.filter((availability) =>
					availability.covers(windowStartTime)
				);
			case InsertHow.PREPEND:
				return vehicle.availabilities.filter((availability) => availability.covers(windowEndTime));
			case InsertHow.CONNECT:
				return vehicle.availabilities.filter((availability) =>
					availability.contains(new Interval(windowStartTime, windowEndTime))
				);
			case InsertHow.NEW_TOUR:
				return Interval.subtract(
					vehicle.availabilities,
					vehicle.tours.map((tour) => new Interval(tour.departure, tour.arrival))
				);
		}
	})();
	console.assert(
		!(insertionCase.how != InsertHow.NEW_TOUR && relevantAvailabilities.length > 1),
		'Found 2 intervals, which are supposed to be disjoint, containing the same timestamp.'
	);
	return relevantAvailabilities
		.map((availability) => availability.intersect(window))
		.filter((availability) => availability != undefined);
}

export function getArrivalWindow(
	insertionCase: InsertionType,
	windows: Interval[],
	travelDuration: number,
	busStopWindow: Interval | undefined,
	approachDuration: number,
	returnDuration: number
): Interval | undefined {
	const fullApproachDuration =
		approachDuration +
		(insertionCase.direction == InsertDirection.TO_BUS_STOP ? travelDuration : 0);
	const fullReturnDuration =
		returnDuration +
		(insertionCase.direction == InsertDirection.FROM_BUS_STOP ? travelDuration : 0);
	let arrivalWindows = windows
		.map((window) => window.shrink(fullApproachDuration, fullReturnDuration))
		.filter((window) => window != undefined);
	if (busStopWindow != undefined) {
		arrivalWindows = arrivalWindows
			.map((window) => busStopWindow.intersect(window))
			.filter((window) => window != undefined);
	}
	if (arrivalWindows.length == 0) {
		return undefined;
	}
	const arrivalWindow =
		insertionCase.direction == InsertDirection.FROM_BUS_STOP
			? arrivalWindows.reduce((current, best) => (current.endTime > best.endTime ? current : best))
			: arrivalWindows.reduce((current, best) => (current.endTime < best.endTime ? current : best));
	return arrivalWindow;
}
