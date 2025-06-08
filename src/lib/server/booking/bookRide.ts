import type { Transaction } from 'kysely';
import type { Capacities } from '$lib/util/booking/Capacities';
import type { Database } from '$lib/server/db';
import { Interval } from '$lib/util/interval';
import type { UnixtimeMs } from '$lib/util/UnixtimeMs';
import { MAX_TRAVEL, SCHEDULED_TIME_BUFFER } from '$lib/constants';
import { getBookingAvailability } from '$lib/server/booking/getBookingAvailability';
import type { Coordinates } from '$lib/util/Coordinates';
import { evaluateRequest } from '$lib/server/booking/evaluateRequest';
import { getEventGroupInfo, type EventGroupUpdate } from '$lib/server/booking/getEventGroupInfo';
import { getDirectDurations, type DirectDrivingDurations } from './getDirectDrivingDurations';
import { getMergeTourList } from './getMergeToorList';
import type { DebugInfo } from '../util/debugInfo';
import { InsertHow } from '$lib/util/booking/insertionTypes';
import { printInsertionType } from './insertionTypes';
import { bookingLogs, increment } from '$lib/testHelpers';
import type { Insertion } from './insertion';
import { comesFromCompany, returnsToCompany } from './durations';

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
	const events = companies[best.company].vehicles.find((v) => v.id == best.vehicle)!.events;
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
	const prevEventInOtherTour =
		best.pickupCase.how == InsertHow.NEW_TOUR
			? events.findLast((e) => e.communicatedTime <= best.pickupTime)
			: events.find((e) => e.id === best.prevPickupId);
	const nextEventInOtherTour =
		best.pickupCase.how == InsertHow.NEW_TOUR
			? events.find((e) => e.communicatedTime >= best.dropoffTime)
			: events.find((e)=> best.nextDropoffId === e.id);
	const directDurations = await getDirectDurations(
		best,
		prevEventInOtherTour,
		nextEventInOtherTour,
		c,
		events[best.pickupIdx ?? -1]?.tourId
	);
	console.log('BE');
	const prevPickupEvent = comesFromCompany(best.pickupCase)
		? best.pickupIdx == undefined
			? undefined
			: events[best.pickupIdx - 1]
		: events.find((e) => e.id === best.prevPickupId);
	const nextPickupEvent = returnsToCompany(best.pickupCase)
		? best.pickupIdx == undefined
			? undefined
			: events[best.pickupIdx]
		: events.find((e) => e.id === best.nextPickupId);
	const prevDropoffEvent = comesFromCompany(best.dropoffCase)
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
	const communicatedPickup = Math.max(prevDropoffEvent?.scheduledTimeEnd ?? 0, best.pickupTime - SCHEDULED_TIME_BUFFER);
	const communicatedDropoff = Math.min(nextDropoffEvent?.scheduledTimeStart ?? Number.MAX_VALUE, best.dropoffTime + SCHEDULED_TIME_BUFFER);
	const scheduledTimes: ScheduledTimes = {
		newPickupStartTime: communicatedPickup,
		newDropoffEndTime: communicatedDropoff,
		updates: []
	};
	if (nextPickupEvent && nextPickupEvent.scheduledTimeStart < best.pickupTime) {
		scheduledTimes.updates.push({
			time: best.pickupTime,
			start: true,
			event_id: nextPickupEvent.id
		});
	}
	if (prevDropoffEvent && prevDropoffEvent.scheduledTimeEnd > best.dropoffTime) {
		scheduledTimes.updates.push({
			time: best.dropoffTime,
			start: false,
			event_id: prevDropoffEvent.id
		});
	}
	return {
		best,
		tour: (() => {
			switch (best.pickupCase.how) {
				case InsertHow.NEW_TOUR:
					return undefined;
				case InsertHow.PREPEND:
					return nextPickupEvent!.tourId;
				default:
					return prevPickupEvent!.tourId;
			}
		})(),
		mergeTourList: getMergeTourList(
			events,
			best.pickupCase.how,
			best.dropoffCase.how,
			best.pickupIdx,
			best.dropoffIdx
		),
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
		scheduledTimes
	};
}

export type ScheduledTimes = {
	updates: {
		event_id: number;
		time: number;
		start: boolean;
	}[];
	newPickupStartTime: number;
	newDropoffEndTime: number;
};

export type BookRideResponse = {
	best: Insertion;
	tour: undefined | number;
	mergeTourList: Set<number>;
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
	scheduledTimes: ScheduledTimes;
};
