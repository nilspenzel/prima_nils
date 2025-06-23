import { SCHEDULED_TIME_BUFFER } from '$lib/constants';
import { Interval } from '$lib/util/interval';
import type { RideShareEvent } from './getBookingAvailability';

export type ScheduledTimes = {
	updates: {
		event_id: number;
		time: number;
		start: boolean;
	}[];
	newPickupStartTime: number;
	newDropoffEndTime: number;
};

export function getScheduledTimes(
	pickupTime: number,
	dropoffTime: number,
	prevPickupEvent: undefined | (RideShareEvent & { time: Interval }),
	nextPickupEvent: undefined | (RideShareEvent & { time: Interval }),
	nextDropoffEvent: undefined | (RideShareEvent & { time: Interval }),
	prevDropoffEvent: undefined | (RideShareEvent & { time: Interval }),
	pickupPrevLegDuration: number,
	pickupNextLegDuration: number,
	dropoffPrevLegDuration: number,
	dropoffNextLegDuration: number
) {
	const communicatedPickup = pickupTime - SCHEDULED_TIME_BUFFER;
	const communicatedDropoff = dropoffTime + SCHEDULED_TIME_BUFFER;
	const scheduledTimes: ScheduledTimes = {
		newPickupStartTime: communicatedPickup,
		newDropoffEndTime: communicatedDropoff,
		updates: []
	};
	if (prevPickupEvent) {
		const prevPickupLeeway =
			pickupTime - prevPickupEvent.scheduledTimeStart - pickupPrevLegDuration;
		if (prevPickupLeeway < 0) {
			console.log('Error in getScheduledTimes 1');
			throw new Error();
		}
		if (prevPickupLeeway < prevPickupEvent.time.size()) {
			scheduledTimes.updates.push({
				event_id: prevPickupEvent.eventId,
				start: false,
				time: prevPickupEvent.scheduledTimeStart + prevPickupLeeway
			});
			scheduledTimes.newPickupStartTime = pickupTime;
		} else {
			scheduledTimes.newPickupStartTime = Math.max(
				communicatedPickup,
				pickupTime - prevPickupLeeway + prevPickupEvent.time.size()
			);
		}
	}
	if (nextPickupEvent) {
		const nextPickupLeeway = nextPickupEvent.scheduledTimeEnd - pickupTime - pickupNextLegDuration;
		if (nextPickupLeeway < 0) {
			console.log('Error in getScheduledTimes 2');
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
			nextDropoffEvent.scheduledTimeEnd - dropoffTime - dropoffNextLegDuration;
		if (nextDropoffLeeway < 0) {
			console.log('Error in getScheduledTimes 3');
			throw new Error();
		}
		if (nextDropoffLeeway < nextDropoffEvent.time.size()) {
			scheduledTimes.updates.push({
				event_id: nextDropoffEvent.eventId,
				start: true,
				time: nextDropoffEvent.scheduledTimeEnd - nextDropoffLeeway
			});
			scheduledTimes.newDropoffEndTime = dropoffTime;
		} else {
			scheduledTimes.newDropoffEndTime = Math.min(
				communicatedDropoff,
				dropoffTime + nextDropoffLeeway - nextDropoffEvent.time.size()
			);
		}
	}
	if (prevDropoffEvent) {
		const prevDropoffLeeway =
			dropoffTime - prevDropoffEvent.scheduledTimeStart - dropoffPrevLegDuration;
		if (prevDropoffLeeway < 0) {
			console.log('Error in getScheduledTimes 4');
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
