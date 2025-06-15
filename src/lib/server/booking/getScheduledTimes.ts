import { SCHEDULED_TIME_BUFFER } from '$lib/constants';
import { Interval } from '$lib/util/interval';
import type { Event } from '$lib/server/booking/getBookingAvailability';

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
	prevPickupEvent: undefined | (Event & { time: Interval }),
	nextPickupEvent: undefined | (Event & { time: Interval }),
	nextDropoffEvent: undefined | (Event & { time: Interval }),
	prevDropoffEvent: undefined | (Event & { time: Interval }),
	pickupPrevLegDuration: number,
	pickupNextLegDuration: number,
	dropoffPrevLegDuration: number,
	dropoffNextLegDuration: number
) {
	let communicatedPickup = pickupTime - SCHEDULED_TIME_BUFFER;
	let communicatedDropoff = dropoffTime + SCHEDULED_TIME_BUFFER;
	const dropoffInterval = new Interval(dropoffTime, communicatedDropoff);
	const pickupCommunicatedInterval = new Interval(communicatedPickup, pickupTime);
	const pickupPrevInterval = new Interval(pickupTime - pickupPrevLegDuration, pickupTime);
	const pickupNextInterval = new Interval(pickupTime, pickupTime + pickupNextLegDuration);
	const dropoffPrevInterval = new Interval(dropoffTime - dropoffPrevLegDuration, dropoffTime);
	const dropoffNextInterval = new Interval(dropoffTime, dropoffTime + dropoffNextLegDuration);
	const scheduledTimes: ScheduledTimes = {
		newPickupStartTime: communicatedPickup,
		newDropoffEndTime: communicatedDropoff,
		updates: []
	};
	if (
		prevPickupEvent &&
		(prevPickupEvent.time.overlaps(pickupCommunicatedInterval) ||
			prevPickupEvent.time.overlaps(pickupPrevInterval))
	) {
		communicatedPickup = Math.min(
			pickupTime - pickupPrevLegDuration,
			(Math.max(communicatedPickup, prevPickupEvent.scheduledTimeStart) +
				Math.min(pickupTime, prevPickupEvent.scheduledTimeEnd)) /
				2
		);
		scheduledTimes.newPickupStartTime = Math.ceil(communicatedPickup);
		scheduledTimes.updates.push({
			event_id: prevPickupEvent.id,
			start: false,
			time: Math.floor(communicatedPickup)
		});
	}
	if (
		nextPickupEvent &&
		(nextPickupEvent.time.overlaps(pickupCommunicatedInterval) ||
			nextPickupEvent.time.overlaps(pickupNextInterval))
	) {
		scheduledTimes.updates.push({
			event_id: nextPickupEvent.id,
			start: true,
			time: pickupTime + pickupNextLegDuration
		});
	}
	if (
		nextDropoffEvent &&
		(nextDropoffEvent.time.overlaps(dropoffInterval) ||
			nextDropoffEvent.time.overlaps(dropoffNextInterval))
	) {
		communicatedDropoff = Math.max(
			dropoffTime + dropoffNextLegDuration,
			(Math.max(dropoffTime, nextDropoffEvent.scheduledTimeStart) +
				Math.min(communicatedDropoff, nextDropoffEvent.scheduledTimeEnd)) /
				2
		);
		scheduledTimes.newDropoffEndTime = Math.floor(communicatedDropoff);
		scheduledTimes.updates.push({
			event_id: nextDropoffEvent.id,
			start: true,
			time: Math.ceil(communicatedDropoff)
		});
	}
	if (
		prevDropoffEvent &&
		(prevDropoffEvent.time.overlaps(dropoffInterval) ||
			prevDropoffEvent?.time.overlaps(dropoffPrevInterval))
	) {
		scheduledTimes.updates.push({
			event_id: prevDropoffEvent.id,
			start: false,
			time: dropoffTime - dropoffPrevLegDuration
		});
	}
	return scheduledTimes;
}
