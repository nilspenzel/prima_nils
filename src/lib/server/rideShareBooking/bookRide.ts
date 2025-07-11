import type { Transaction } from 'kysely';
import type { Capacities } from '$lib/util/booking/Capacities';
import type { Database } from '$lib/server/db';
import { Interval } from '$lib/util/interval';
import type { UnixtimeMs } from '$lib/util/UnixtimeMs';
import {
	getBookingAvailability,
	type RideShareTour
} from '$lib/server/rideShareBooking/getBookingAvailability';
import type { Coordinates } from '$lib/util/Coordinates';
import { evaluateRequest } from '$lib/server/rideShareBooking/evaluateRequest';
import { getMergeTourList } from './getMergeTourList';
import { InsertHow, InsertWhat } from '$lib/util/booking/insertionTypes';
import { bookingLogs, increment } from '$lib/testHelpers';
import type { Insertion } from './insertion';
import { comesFromCompany, returnsToCompany } from './durations';
import { getScheduledTimes, type ScheduledTimes } from './getScheduledTimes';
import { DAY } from '$lib/util/time';
import { printInsertionType } from '../booking/insertionTypes';

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

export async function bookSharedRide(
	c: ExpectedConnection,
	required: Capacities,
	trx?: Transaction<Database>,
	skipPromiseCheck?: boolean,
	blockedProviderId?: number
): Promise<undefined | BookRideShareResponse> {
	bookingLogs.push({ iter: -1 });
	console.log('BS');
	const searchInterval = new Interval(c.startTime, c.targetTime);
	const expandedSearchInterval = searchInterval.expand(DAY, DAY);
	const userChosen = !c.startFixed ? c.start : c.target;
	const busStop = c.startFixed ? c.start : c.target;
	const rideShareTours = await getBookingAvailability(
		userChosen,
		required,
		searchInterval,
		[busStop],
		trx
	);
	if (rideShareTours.length == 0) {
		console.log('there were no ride shares tours which could be concatenated with this request.');
		return undefined;
	}
	let allowedRideShareTours: RideShareTour[] = [];
	if (blockedProviderId != undefined && blockedProviderId != null) {
		allowedRideShareTours = rideShareTours.filter((t) => t.provider !== blockedProviderId);
	}
	const busTime = c.startFixed ? c.startTime : c.targetTime;
	const best = (
		await evaluateRequest(
			allowedRideShareTours,
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
					}
		)
	)[0][0];
	if (best == undefined) {
		console.log('surprisingly no possible connection found: ', userChosen, busStop, busTime, best);
		return undefined;
	}
	console.log({ best }, printInsertionType(best.pickupCase), printInsertionType(best.dropoffCase));
	const rideShareTour = allowedRideShareTours[best.rideShareTour];
	const events = rideShareTour.events;
	console.log('BE');
	const prevPickupEvent = comesFromCompany(best.pickupCase)
		? best.pickupIdx == undefined
			? undefined
			: events[best.pickupIdx - 1]
		: events.find((e) => e.eventId === best.prevPickupId);
	const nextPickupEvent =
		InsertWhat.BOTH === best.pickupCase.what
			? undefined
			: returnsToCompany(best.pickupCase)
				? best.pickupIdx == undefined
					? undefined
					: events[best.pickupIdx]
				: events.find((e) => e.eventId === best.nextPickupId);
	const prevDropoffEvent =
		InsertWhat.BOTH === best.pickupCase.what
			? undefined
			: comesFromCompany(best.dropoffCase)
				? best.dropoffIdx == undefined
					? undefined
					: events[best.dropoffIdx - 1]
				: events.find((e) => e.eventId === best.prevDropoffId);
	const nextDropoffEvent = returnsToCompany(best.dropoffCase)
		? best.dropoffIdx == undefined
			? undefined
			: events[best.dropoffIdx]
		: events.find((e) => e.eventId === best.nextDropoffId);
	increment();
	let mergeTourList = getMergeTourList(
		events,
		best.pickupCase.how,
		best.dropoffCase.how,
		best.pickupIdx,
		best.dropoffIdx
	);
	// If it is necessary to merge tours, find the first/last events of each such tour..
	if (mergeTourList.length == 1) {
		mergeTourList = [];
	}

	const scheduledTimes = getScheduledTimes(
		best.pickupTime,
		best.scheduledPickupTime,
		best.scheduledDropoffTime,
		best.dropoffTime,
		prevPickupEvent,
		nextPickupEvent,
		nextDropoffEvent,
		prevDropoffEvent,
		best.pickupPrevLegDuration,
		best.pickupNextLegDuration,
		best.dropoffPrevLegDuration,
		best.dropoffNextLegDuration
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
		neighbourIds: {
			prevPickup: best.pickupCase.how == InsertHow.PREPEND ? undefined : prevPickupEvent?.eventId,
			nextPickup: best.pickupCase.how == InsertHow.APPEND ? undefined : nextPickupEvent?.eventId,
			prevDropoff:
				best.dropoffCase.how == InsertHow.PREPEND ? undefined : prevDropoffEvent?.eventId,
			nextDropoff: best.dropoffCase.how == InsertHow.APPEND ? undefined : nextDropoffEvent?.eventId
		},
		scheduledTimes
	};
}

export type BookRideShareResponse = {
	best: Insertion;
	tour: undefined | number;
	neighbourIds: {
		prevPickup: undefined | number;
		nextPickup: undefined | number;
		prevDropoff: undefined | number;
		nextDropoff: undefined | number;
	};
	scheduledTimes: ScheduledTimes;
};
