import { Interval } from '$lib/util/interval';
import type { RideShareEvent } from './getBookingAvailability';

export type ScheduledTimes = {
	updates: {
		event_id: number;
		time: number;
		start: boolean;
	}[];
};

export function getScheduledTimes(
	pickupTimeStart: number,
	pickupTimeEnd: number,
	dropoffTimeStart: number,
	dropoffTimeEnd: number,
	prevPickupEvent: undefined | (RideShareEvent & { time: Interval }),
	nextPickupEvent: undefined | (RideShareEvent & { time: Interval }),
	nextDropoffEvent: undefined | (RideShareEvent & { time: Interval }),
	prevDropoffEvent: undefined | (RideShareEvent & { time: Interval }),
	pickupPrevLegDuration: number,
	pickupNextLegDuration: number,
	dropoffPrevLegDuration: number,
	dropoffNextLegDuration: number
) {
	const scheduledTimes: ScheduledTimes = {
		updates: []
	};
	if (prevPickupEvent) {
		const prevPickupLeeway =
			pickupTimeStart - prevPickupEvent.scheduledTimeStart - pickupPrevLegDuration;
		if (prevPickupLeeway < 0) {
			throw new Error();
		}
		if (prevPickupLeeway < prevPickupEvent.time.size()) {
			scheduledTimes.updates.push({
				event_id: prevPickupEvent.eventId,
				start: false,
				time: prevPickupEvent.scheduledTimeStart + prevPickupLeeway
			});
		}
	}
	if (nextPickupEvent) {
		const nextPickupLeeway =
			nextPickupEvent.scheduledTimeEnd - pickupTimeEnd - pickupNextLegDuration;
		if (nextPickupLeeway < 0) {
			throw new Error();
		}
		if (nextPickupLeeway < nextPickupEvent.time.size()) {
			scheduledTimes.updates.push({
				event_id: nextPickupEvent.eventId,
				start: true,
				time: nextPickupEvent.scheduledTimeEnd - nextPickupLeeway
			});
		}
	}
	if (nextDropoffEvent) {
		const nextDropoffLeeway =
			nextDropoffEvent.scheduledTimeEnd - dropoffTimeEnd - dropoffNextLegDuration;
		if (nextDropoffLeeway < 0) {
			throw new Error();
		}
		if (nextDropoffLeeway < nextDropoffEvent.time.size()) {
			scheduledTimes.updates.push({
				event_id: nextDropoffEvent.eventId,
				start: true,
				time: nextDropoffEvent.scheduledTimeEnd - nextDropoffLeeway
			});
		}
	}
	if (prevDropoffEvent) {
		const prevDropoffLeeway =
			dropoffTimeStart - prevDropoffEvent.scheduledTimeStart - dropoffPrevLegDuration;
		if (prevDropoffLeeway < 0) {
			throw new Error();
		}
		if (prevDropoffLeeway < prevDropoffEvent.time.size()) {
			scheduledTimes.updates.push({
				event_id: prevDropoffEvent.eventId,
				start: false,
				time: prevDropoffEvent.scheduledTimeStart + prevDropoffLeeway
			});
		}
	}
	return scheduledTimes;
}
