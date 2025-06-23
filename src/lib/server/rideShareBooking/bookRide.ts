import type { Transaction } from 'kysely';
import type { Capacities } from '$lib/util/booking/Capacities';
import type { Database } from '$lib/server/db';
import { Interval } from '$lib/util/interval';
import type { UnixtimeMs } from '$lib/util/UnixtimeMs';
import { getBookingAvailability } from '$lib/server/rideShareBooking/getBookingAvailability';
import type { Coordinates } from '$lib/util/Coordinates';
import { evaluateRequest } from '$lib/server/rideShareBooking/evaluateRequest';
import type { DebugInfo } from '../util/debugInfo';
import { InsertWhat } from '$lib/util/booking/insertionTypes';
import { printInsertionType } from './insertionTypes';
import { bookingLogs, increment } from '$lib/testHelpers';
import type { Insertion } from './insertion';
import { getScheduledTimes, type ScheduledTimes } from './getScheduledTimes';
import { DAY } from '$lib/util/time';

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
	debugInfo?: DebugInfo
): Promise<undefined | BookRideResponse> {
	bookingLogs.push({ iter: -1 });
	console.log('BS');
	const searchInterval = new Interval(c.startTime, c.targetTime);
	const expandedSearchInterval = searchInterval.expand(DAY, DAY);
	const userChosen = !c.startFixed ? c.start : c.target;
	const busStop = c.startFixed ? c.start : c.target;
	const tours = await getBookingAvailability(userChosen, required, searchInterval, [busStop], trx);
	if (tours.length == 0) {
		if (debugInfo) {
			console.log(
				'BOOK RIDE DEBUG INFO: there were no vehicles with corrcet zone, capacity and availability or tour for concatenation.'
			);
		}
		return undefined;
	}
	// blocked vehicle required to avoid first and last mile together issues??
	const busTime = c.startFixed ? c.startTime : c.targetTime;
	const best = (
		await evaluateRequest(
			tours,
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
	const tour = tours[best.tour];
	const events = tour.events;
	console.log('BE');
	const prevPickupEvent = events.find((e) => e.eventId === best.prevPickupId);
	const nextPickupEvent =
		InsertWhat.BOTH === best.pickupCase.what
			? undefined
			: events.find((e) => e.eventId === best.nextPickupId);
	const prevDropoffEvent =
		InsertWhat.BOTH === best.pickupCase.what
			? undefined
			: events.find((e) => e.eventId === best.prevDropoffId);
	const nextDropoffEvent = events.find((e) => e.eventId === best.nextDropoffId);
	increment();
	const scheduledTimes = getScheduledTimes(
		best.pickupTime,
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
		tour: tour!.rideShareTour,
		neighbourIds: {
			prevPickup: prevPickupEvent?.eventId,
			nextPickup: nextPickupEvent?.eventId,
			prevDropoff: prevDropoffEvent?.eventId,
			nextDropoff: nextDropoffEvent?.eventId
		},
		scheduledTimes
	};
}

export type BookRideResponse = {
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
