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
	prevDropoffEvent: undefined | (Event & { time: Interval })
) {
	let communicatedPickup = pickupTime - SCHEDULED_TIME_BUFFER;
	let communicatedDropoff = dropoffTime + SCHEDULED_TIME_BUFFER;
	const dropoffInterval = new Interval(dropoffTime, communicatedDropoff);
	const pickupInterval = new Interval(communicatedPickup, pickupTime);
	const scheduledTimes: ScheduledTimes = {
		newPickupStartTime: communicatedPickup,
		newDropoffEndTime: communicatedDropoff,
		updates: []
	};
	console.log({ prevPickupEvent }, { prevDropoffEvent }, { nextDropoffEvent }, { nextPickupEvent });
	if (prevPickupEvent && prevPickupEvent.time.overlaps(pickupInterval)) {
		communicatedPickup =
			(Math.max(communicatedPickup, prevPickupEvent.scheduledTimeStart) +
				Math.min(pickupTime, prevPickupEvent.scheduledTimeEnd)) /
			2;
		scheduledTimes.newPickupStartTime = Math.ceil(communicatedPickup);
		scheduledTimes.updates.push({
			event_id: prevPickupEvent.id,
			start: false,
			time: Math.floor(communicatedPickup)
		});
	}
	if (nextPickupEvent && nextPickupEvent.time.overlaps(pickupInterval)) {
		scheduledTimes.updates.push({
			event_id: nextPickupEvent.id,
			start: true,
			time: pickupTime
		});
	}
	if (nextDropoffEvent && nextDropoffEvent.time.overlaps(dropoffInterval)) {
		communicatedDropoff =
			(Math.max(dropoffTime, nextDropoffEvent.scheduledTimeStart) +
				Math.min(communicatedDropoff, nextDropoffEvent.scheduledTimeEnd)) /
			2;
		scheduledTimes.newDropoffEndTime = Math.floor(communicatedDropoff);
		scheduledTimes.updates.push({
			event_id: nextDropoffEvent.id,
			start: true,
			time: Math.ceil(communicatedDropoff)
		});
	}
	if (prevDropoffEvent && prevDropoffEvent.time.overlaps(dropoffInterval)) {
		scheduledTimes.updates.push({
			event_id: prevDropoffEvent.id,
			start: false,
			time: dropoffTime
		});
	}
	if (nextPickupEvent && nextPickupEvent.scheduledTimeStart < pickupTime) {
		scheduledTimes.updates.push({
			time: pickupTime,
			start: true,
			event_id: nextPickupEvent.id
		});
	}
	if (prevDropoffEvent && prevDropoffEvent.scheduledTimeEnd > dropoffTime) {
		scheduledTimes.updates.push({
			time: dropoffTime,
			start: false,
			event_id: prevDropoffEvent.id
		});
	}
	return scheduledTimes;
}
