import type { Transaction } from 'kysely';
import type { Capacities } from '$lib/util/booking/Capacities';
import type { Database } from '$lib/server/db';
import { Interval } from '$lib/util/interval';
import type { UnixtimeMs } from '$lib/util/UnixtimeMs';
import { MAX_TRAVEL, PASSENGER_CHANGE_DURATION, SCHEDULED_TIME_BUFFER } from '$lib/constants';
import { getBookingAvailability } from '$lib/server/booking/getBookingAvailability';
import type { Coordinates } from '$lib/util/Coordinates';
import { evaluateRequest } from '$lib/server/booking/evaluateRequest';
import { getEventGroupInfo, type EventGroupUpdate } from '$lib/server/booking/getEventGroupInfo';
import { getDirectDurations, type DirectDrivingDurations } from './getDirectDrivingDurations';
import { getMergeTourList } from './getMergeToorList';
import type { DebugInfo } from '../util/debugInfo';
import { InsertHow, InsertWhat } from '$lib/util/booking/insertionTypes';
import { printInsertionType } from './insertionTypes';
import { bookingLogs, increment } from '$lib/testHelpers';
import type { Insertion } from './insertion';
import { comesFromCompany, returnsToCompany } from './durations';
import { groupBy } from '$lib/util/groupBy';
import type { Event } from '$lib/server/booking/getBookingAvailability';
import { oneToManyCarRouting } from '../util/oneToManyCarRouting';
import { getScheduledTimes, type ScheduledTimes } from './getScheduledTimes';

export type ExpectedConnection = {
	start: Coordinates;
	target: Coordinates;
	startTime: UnixtimeMs;
	targetTime: UnixtimeMs;
	signature: string;
	startFixed: boolean;
};

export type ExpectedConnectionWithISoStrings = {
	start: Coordinates;
	target: Coordinates;
	startTime: string;
	targetTime: string;
};

export function toExpectedConnectionWithISOStrings(
	c: ExpectedConnection | null
): ExpectedConnectionWithISoStrings | null {
	return c == null
		? null
		: {
				...c,
				startTime: new Date(c.startTime).toISOString(),
				targetTime: new Date(c.targetTime).toISOString()
			};
}

export async function bookRide(
	c: ExpectedConnection,
	required: Capacities,
	trx?: Transaction<Database>,
	skipPromiseCheck?: boolean,
	blockedVehicleId?: number,
	debugInfo?: DebugInfo
): Promise<undefined | BookRideResponse> {
	bookingLogs.push({ iter: -1 });
	console.log('BS');
	const searchInterval = new Interval(c.startTime, c.targetTime);
	const expandedSearchInterval = searchInterval.expand(MAX_TRAVEL * 6, MAX_TRAVEL * 6);
	const userChosen = !c.startFixed ? c.start : c.target;
	const busStop = c.startFixed ? c.start : c.target;
	const { companies, filteredBusStops } = await getBookingAvailability(
		userChosen,
		required,
		searchInterval,
		[busStop],
		trx
	);
	if (companies.length == 0 || filteredBusStops[0] == undefined) {
		if (debugInfo) {
			console.log(
				'BOOK RIDE DEBUG INFO: there were no vehicles with corrcet zone, capacity and availability or tour for concatenation.',
				{ filteredBusStops }
			);
		}
		return undefined;
	}
	if (blockedVehicleId != undefined && blockedVehicleId != null) {
		const blockedVehicleCompanyIdx = companies.findIndex((c) =>
			c.vehicles.some((v) => v.id == blockedVehicleId)
		);
		if (blockedVehicleCompanyIdx != -1) {
			companies[blockedVehicleCompanyIdx].vehicles = companies[
				blockedVehicleCompanyIdx
			].vehicles.filter((v) => v.id != blockedVehicleId);
		}
	}
	const busTime = c.startFixed ? c.startTime : c.targetTime;
	const best = (
		await evaluateRequest(
			companies,
			expandedSearchInterval,
			userChosen,
			[{ ...busStop, times: [busTime] }],
			required,
			c.startFixed,
			skipPromiseCheck
				? undefined
				: {
						pickup: c.startTime,
						dropoff: c.targetTime
					},
			debugInfo
		)
	)[0][0];
	if (best == undefined) {
		console.log('surprisingly no possible connection found: ', userChosen, busStop, busTime, best);
		return undefined;
	}
	console.log({ best }, printInsertionType(best.pickupCase), printInsertionType(best.dropoffCase));
	if (debugInfo) {
		console.log(
			'BOOK RIDE DEBUG INFO: ',
			'pickup: ',
			printInsertionType(best.pickupCase),
			' dropoff: ',
			printInsertionType(best.dropoffCase)
		);
		return undefined;
	}
	const vehicle = companies[best.company].vehicles.find((v) => v.id === best.vehicle)!;
	const events = vehicle.events;
	let prevPickupEventIdx = best.pickupIdx == undefined ? undefined : best.pickupIdx - 1;
	if (best.pickupCase.how == InsertHow.NEW_TOUR) {
		prevPickupEventIdx = events.findLastIndex((e) => e.communicatedTime <= best.pickupTime);
	}
	const pickupEventGroupInfo = getEventGroupInfo(
		events,
		c.start,
		prevPickupEventIdx,
		best.pickupIdx,
		best.pickupCase.how
	);
	const prevDropoffEventIdx = best.dropoffIdx == undefined ? undefined : best.dropoffIdx - 1;
	const dropoffEventGroupInfo = getEventGroupInfo(
		events,
		c.target,
		prevDropoffEventIdx,
		best.dropoffIdx,
		best.dropoffCase.how
	);
	console.log('BE');
	const prevPickupEvent = comesFromCompany(best.pickupCase)
		? best.pickupIdx == undefined
			? undefined
			: events[best.pickupIdx - 1]
		: events.find((e) => e.id === best.prevPickupId);
	const nextPickupEvent =
		InsertWhat.BOTH === best.pickupCase.what
			? undefined
			: returnsToCompany(best.pickupCase)
				? best.pickupIdx == undefined
					? undefined
					: events[best.pickupIdx]
				: events.find((e) => e.id === best.nextPickupId);
	const prevDropoffEvent =
		InsertWhat.BOTH === best.pickupCase.what
			? undefined
			: comesFromCompany(best.dropoffCase)
				? best.dropoffIdx == undefined
					? undefined
					: events[best.dropoffIdx - 1]
				: events.find((e) => e.id === best.prevDropoffId);
	const nextDropoffEvent = returnsToCompany(best.dropoffCase)
		? best.dropoffIdx == undefined
			? undefined
			: events[best.dropoffIdx]
		: events.find((e) => e.id === best.nextDropoffId);
	increment();
	const mergeTourList = getMergeTourList(
		events,
		best.pickupCase.how,
		best.dropoffCase.how,
		best.pickupIdx,
		best.dropoffIdx
	);
	let departure = Number.MAX_SAFE_INTEGER;
	let arrival = -1;
	if (mergeTourList.length !== 0) {
		for (const tour of mergeTourList) {
			if (departure > tour.departure) {
				departure = tour.departure;
			}
			if (arrival < tour.arrival) {
				arrival = tour.arrival;
			}
			if (best.pickupCase.how !== InsertHow.PREPEND) {
				best.departure = departure;
			}
			if (best.dropoffCase.how !== InsertHow.APPEND) {
				best.arrival = arrival;
			}
		}
	}
	const filteredEvents = groupBy(
		events.filter((e) => mergeTourList.some((t) => t.tourId === e.tourId)),
		(e) => e.tourId,
		(e) => e
	);
	const firstEvents: Event[] = [];
	const lastEvents: Event[] = [];
	for (const [_, tour] of filteredEvents) {
		tour.sort((e1, e2) =>
			e1.scheduledTimeStart === e2.scheduledTimeStart
				? e1.scheduledTimeEnd - e2.scheduledTimeEnd
				: e1.scheduledTimeStart - e2.scheduledTimeStart
		);
		const firstEvent = tour[0];
		const lastEvent = tour[tour.length - 1];
		if (
			firstEvent.departure !== departure &&
			firstEvent.id !== best.nextPickupId &&
			firstEvent.id !== best.nextDropoffId
		) {
			firstEvents.push(firstEvent);
		}
		if (
			lastEvent.arrival !== arrival &&
			lastEvent.id !== best.prevPickupId &&
			lastEvent.id !== best.prevDropoffId
		) {
			lastEvents.push(lastEvent);
		}
	}
	if (firstEvents.length !== lastEvents.length) {
		throw new Error();
	}

	const prevLegRouting = firstEvents.map((e, i) => oneToManyCarRouting(lastEvents[i], [e], false));
	const prevLegRoutingResults = await Promise.all(prevLegRouting);
	const prevLegDurations: { event: number; duration: number | null }[] = [];
	prevLegRoutingResults.forEach((rr, i) =>
		prevLegDurations.push({
			event: firstEvents[i].id,
			duration: rr[0] ? rr[0] + PASSENGER_CHANGE_DURATION : null
		})
	);

	const nextLegRouting = lastEvents.map((e, i) => oneToManyCarRouting(e, [lastEvents[i]], false));
	const nextLegRoutingResults = await Promise.all(nextLegRouting);
	const nextLegDurations: { event: number; duration: number | null }[] = [];
	nextLegRoutingResults.forEach((rr, i) =>
		nextLegDurations.push({
			event: lastEvents[i].id,
			duration: rr[0] ? rr[0] + PASSENGER_CHANGE_DURATION : null
		})
	);

	let prevEventInOtherTour =
		best.pickupCase.how == InsertHow.NEW_TOUR
			? events.findLast((e) => e.scheduledTimeStart <= best.pickupTime)
			: events.find((e) => e.id === best.prevPickupId);
	if (prevEventInOtherTour === undefined) {
		prevEventInOtherTour = vehicle.lastEventBefore;
	}
	let nextEventInOtherTour =
		best.pickupCase.how == InsertHow.NEW_TOUR
			? events.find((e) => e.scheduledTimeEnd >= best.dropoffTime)
			: events.find((e) => best.nextDropoffId === e.id);
	if (nextEventInOtherTour === undefined) {
		nextEventInOtherTour = vehicle.firstEventAfter;
	}
	const directDurations = await getDirectDurations(
		best,
		prevEventInOtherTour,
		nextEventInOtherTour,
		c,
		events[best.pickupIdx ?? -1]?.tourId,
		mergeTourList.length !== 0,
		departure,
		arrival,
		vehicle
	);
	return {
		best,
		tour: (() => {
			switch (best.pickupCase.how) {
				case InsertHow.NEW_TOUR:
					return undefined;
				case InsertHow.PREPEND:
					return best.pickupCase.what === InsertWhat.BOTH
						? nextDropoffEvent!.tourId
						: nextPickupEvent!.tourId;
				default:
					return prevPickupEvent!.tourId;
			}
		})(),
		mergeTourList: Array.from(mergeTourList).map((t) => t.tourId),
		eventGroupUpdateList: pickupEventGroupInfo.updateList.concat(dropoffEventGroupInfo.updateList),
		pickupEventGroup: pickupEventGroupInfo.newEventGroup,
		dropoffEventGroup: dropoffEventGroupInfo.newEventGroup,
		neighbourIds: {
			prevPickup: best.pickupCase.how == InsertHow.PREPEND ? undefined : prevPickupEvent?.id,
			nextPickup: best.pickupCase.how == InsertHow.APPEND ? undefined : nextPickupEvent?.id,
			prevDropoff: best.dropoffCase.how == InsertHow.PREPEND ? undefined : prevDropoffEvent?.id,
			nextDropoff: best.dropoffCase.how == InsertHow.APPEND ? undefined : nextDropoffEvent?.id
		},
		directDurations,
		prevLegDurations,
		nextLegDurations,
		scheduledTimes: getScheduledTimes(
			best.pickupTime,
			best.dropoffTime,
			prevPickupEvent,
			nextPickupEvent,
			nextDropoffEvent,
			prevDropoffEvent
		)
	};
}

export type BookRideResponse = {
	best: Insertion;
	tour: undefined | number;
	mergeTourList: number[];
	eventGroupUpdateList: EventGroupUpdate[];
	pickupEventGroup: string;
	dropoffEventGroup: string;
	neighbourIds: {
		prevPickup: undefined | number;
		nextPickup: undefined | number;
		prevDropoff: undefined | number;
		nextDropoff: undefined | number;
	};
	directDurations: DirectDrivingDurations;
	prevLegDurations: { event: number; duration: number | null }[];
	nextLegDurations: { event: number; duration: number | null }[];
	scheduledTimes: ScheduledTimes;
};
