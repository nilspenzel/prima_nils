import type { Event, Vehicle } from '$lib/compositionTypes';
import { BUFFER_TIME, MAX_TRAVEL_MS, PASSENGER_CHANGE_MINUTES } from '$lib/constants';
import { Interval } from '$lib/interval';
import { minutesToMs } from '$lib/time_utils';
import {
	InsertDirection,
	InsertHow,
	InsertWhat,
	type InsertionInfo,
	type InsertionType
} from './insertionTypes';
import type { InsertionRoutingResult, RoutingResults } from './routing';

export const returnsToCompany = (insertionCase: InsertionType): boolean => {
	return (
		insertionCase.how === InsertHow.CONNECT ||
		insertionCase.how === InsertHow.APPEND ||
		insertionCase.how == InsertHow.NEW_TOUR
	);
};

export const comesFromCompany = (insertionCase: InsertionType): boolean => {
	return (
		insertionCase.how === InsertHow.CONNECT ||
		insertionCase.how === InsertHow.PREPEND ||
		insertionCase.how == InsertHow.NEW_TOUR
	);
};

export const getApproachDuration = (
	insertionCase: InsertionType,
	routingResults: RoutingResults,
	insertionInfo: InsertionInfo,
	busStopIdx: number | undefined,
	prev: Event | undefined
): number => {
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
	return (
		(comesFromCompany(insertionCase)
			? relevantRoutingResults.fromCompany[insertionInfo.companyIdx]
			: relevantRoutingResults.fromPrevEvent[insertionInfo.prevEventIdxInRoutingResults]) +
		minutesToMs(BUFFER_TIME)
	);
};

export const getReturnDuration = (
	insertionCase: InsertionType,
	routingResults: RoutingResults,
	insertionInfo: InsertionInfo,
	busStopIdx: number | undefined,
	next: Event | undefined
): number => {
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
	return (
		(returnsToCompany(insertionCase)
			? relevantRoutingResults.toCompany[insertionInfo.companyIdx]
			: relevantRoutingResults.toNextEvent[insertionInfo.nextEventIdxInRoutingResults]) +
		minutesToMs(PASSENGER_CHANGE_MINUTES + BUFFER_TIME)
	);
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
				return vehicle.availabilities.filter((availability) => availability.covers(windowEndTime));
			case InsertHow.PREPEND:
				return vehicle.availabilities.filter((availability) =>
					availability.covers(windowStartTime)
				);
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

export function getTaxiWaitingTime(
	insertionCase: InsertionType,
	taxiDuration: number,
	prev: Event | undefined,
	next: Event | undefined
) {
	/*
	console.assert(
		!(prev == undefined && next == undefined),
		'Insertion neither has previous nor successor event.'
	);
	*/
	console.assert(
		!(
			(InsertHow.CONNECT == insertionCase.how || insertionCase.how == InsertHow.INSERT) &&
			(prev == undefined || next == undefined)
		),
		'Either previous or successor event were undefined, in INSERT or CONNECT case.'
	);
	let fullDuration = 0;
	if (insertionCase.how == InsertHow.CONNECT || insertionCase.how == InsertHow.INSERT) {
		fullDuration =
			insertionCase.how == InsertHow.CONNECT
				? next!.departure.getTime() - prev!.arrival.getTime()
				: next!.communicated.getTime() - prev!.communicated.getTime();
	}
	return insertionCase.how == InsertHow.CONNECT || insertionCase.how == InsertHow.INSERT
		? fullDuration - taxiDuration
		: 0;
}

export function getArrivalWindow(
	insertionCase: InsertionType,
	windows: Interval[],
	travelDuration: number,
	busStopWindow: Interval | undefined,
	approachDuration: number,
	returnDuration: number
): Interval | undefined {
	if (
		approachDuration > MAX_TRAVEL_MS ||
		returnDuration > MAX_TRAVEL_MS ||
		travelDuration > MAX_TRAVEL_MS
	) {
		return undefined;
	}
	console.assert(!(busStopWindow != undefined && InsertWhat.USER_CHOSEN == insertionCase.what));
	let arrivalWindows = windows.map((window) => window.shrink(approachDuration, returnDuration));
	if (insertionCase.what == InsertWhat.BOTH) {
		arrivalWindows = arrivalWindows.map((window) =>
			window?.shrink(
				insertionCase.direction == InsertDirection.TO_BUS_STOP
					? travelDuration + minutesToMs(BUFFER_TIME) + minutesToMs(PASSENGER_CHANGE_MINUTES)
					: 0,
				insertionCase.direction == InsertDirection.FROM_BUS_STOP
					? travelDuration + minutesToMs(BUFFER_TIME) + minutesToMs(PASSENGER_CHANGE_MINUTES)
					: 0
			)
		);
	}
	let arrivalWindows2 = arrivalWindows.filter((window) => window != undefined);
	if (busStopWindow != undefined) {
		arrivalWindows2 = arrivalWindows2
			.map((window) => window.intersect(busStopWindow))
			.filter((window) => window != undefined);
	}
	if (arrivalWindows2.length == 0) {
		return undefined;
	}
	const arrivalWindow =
		insertionCase.direction == InsertDirection.FROM_BUS_STOP
			? arrivalWindows2.reduce((current, best) => (current.endTime > best.endTime ? current : best))
			: arrivalWindows2.reduce((current, best) =>
					current.startTime < best.startTime ? current : best
				);
	return arrivalWindow;
}
