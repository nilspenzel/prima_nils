import { InsertWhat } from '$lib/util/booking/insertionTypes';
import { Interval } from '$lib/util/interval';
import type { UnixtimeMs } from '$lib/util/UnixtimeMs';
import type { RideShareEvent } from './getBookingAvailability';
import { InsertDirection, type InsertionInfo, type InsertionType } from './insertionTypes';
import type { InsertionRoutingResult, RoutingResults } from './routing';

export const getPrevLegDuration = (
	insertionCase: InsertionType,
	routingResults: RoutingResults,
	insertionInfo: InsertionInfo,
	busStopIdx: number | undefined
): number | undefined => {
	let relevantRoutingResults: InsertionRoutingResult | undefined = undefined;
	switch (insertionCase.what) {
		case InsertWhat.USER_CHOSEN:
			relevantRoutingResults = routingResults.userChosen.toUserChosen;
			break;

		case InsertWhat.BOTH:
			console.assert(busStopIdx != undefined);
			relevantRoutingResults =
				insertionCase.direction == InsertDirection.BUS_STOP_PICKUP
					? routingResults.busStops.toBusStop[busStopIdx!]
					: routingResults.userChosen.toUserChosen;
			break;

		case InsertWhat.BUS_STOP:
			console.assert(busStopIdx != undefined);
			relevantRoutingResults = routingResults.busStops.toBusStop[busStopIdx!];
			break;
	}
	return relevantRoutingResults.event[insertionInfo.insertionIdx];
};

export const getNextLegDuration = (
	insertionCase: InsertionType,
	routingResults: RoutingResults,
	insertionInfo: InsertionInfo,
	busStopIdx: number | undefined
): number | undefined => {
	let relevantRoutingResults: InsertionRoutingResult | undefined = undefined;
	switch (insertionCase.what) {
		case InsertWhat.USER_CHOSEN:
			relevantRoutingResults = routingResults.userChosen.fromUserChosen;
			break;

		case InsertWhat.BOTH:
			console.assert(busStopIdx != undefined);
			relevantRoutingResults =
				insertionCase.direction == InsertDirection.BUS_STOP_PICKUP
					? routingResults.userChosen.fromUserChosen
					: routingResults.busStops.fromBusStop[busStopIdx!];
			break;

		case InsertWhat.BUS_STOP:
			console.assert(busStopIdx != undefined);
			relevantRoutingResults = routingResults.busStops.fromBusStop[busStopIdx!];
			break;
	}
	return relevantRoutingResults.event[insertionInfo.insertionIdx];
};

export function getAllowedOperationTimes(
	prev: RideShareEvent | undefined,
	next: RideShareEvent | undefined,
	expandedSearchInterval: Interval,
	prepTime: UnixtimeMs
): Interval | undefined {
	const windowEndTime = next == undefined ? expandedSearchInterval.endTime : next.scheduledTimeEnd;
	if (windowEndTime < prepTime) {
		return undefined;
	}

	let windowStartTime =
		prev == undefined ? expandedSearchInterval.startTime : prev.scheduledTimeStart;
	windowStartTime = Math.max(windowStartTime, prepTime);
	const window = new Interval(windowStartTime, windowEndTime);
	return window;
}

export function getArrivalWindow(
	insertionCase: InsertionType,
	window: Interval,
	directDuration: number,
	busStopWindow: Interval | undefined,
	prevLegDuration: number,
	nextLegDuration: number,
	allowedTimes: Interval[]
): Interval | undefined {
	const directWindows = Interval.intersect(
		allowedTimes,
		[window]
			.map((w) => w.shrink(prevLegDuration + 1, 1 + nextLegDuration))
			.filter((w) => w != undefined)
	);

	let arrivalWindows = directWindows
		.map((window) =>
			window.shrink(
				insertionCase.direction == InsertDirection.BUS_STOP_DROPOFF ? directDuration : 0,
				insertionCase.direction == InsertDirection.BUS_STOP_PICKUP ? directDuration : 0
			)
		)
		.filter((window) => window != undefined);
	if (busStopWindow != undefined) {
		arrivalWindows = arrivalWindows
			.map((window) => busStopWindow.intersect(window))
			.filter((window) => window != undefined);
	}
	if (arrivalWindows.length == 0) {
		return undefined;
	}
	const best =
		insertionCase.direction == InsertDirection.BUS_STOP_PICKUP
			? arrivalWindows.reduce((current, best) => (current.endTime < best.endTime ? current : best))
			: arrivalWindows.reduce((current, best) => (current.endTime > best.endTime ? current : best));
	return best;
}
