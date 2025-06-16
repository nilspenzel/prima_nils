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
			console.log('errortype1');
			throw new Error();
		}
		console.log('critical1', { prevPickupLeeway: new Date(prevPickupLeeway).toISOString() });
		if (prevPickupLeeway < prevPickupEvent.time.size()) {
			scheduledTimes.updates.push({
				event_id: prevPickupEvent.id,
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
			console.log('errortype2');
			throw new Error();
		}
		console.log('critical2', { nextPickupLeeway: new Date(nextPickupLeeway).toISOString() });
		if (nextPickupLeeway < nextPickupEvent.time.size()) {
			scheduledTimes.updates.push({
				event_id: nextPickupEvent.id,
				start: true,
				time: nextPickupEvent.scheduledTimeEnd - nextPickupLeeway
			});
		}
	}
	if (nextDropoffEvent) {
		const nextDropoffLeeway =
			nextDropoffEvent.scheduledTimeEnd - dropoffTime - dropoffNextLegDuration;
		if (nextDropoffLeeway < 0) {
			console.log('errortype3');
			throw new Error();
		}
		console.log('critical3', { nextDropoffLeeway: new Date(nextDropoffLeeway).toISOString() });
		if (nextDropoffLeeway < nextDropoffEvent.time.size()) {
			scheduledTimes.updates.push({
				event_id: nextDropoffEvent.id,
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
			console.log('errortype4');
			throw new Error();
		}
		console.log('critical4', { prevDropoffLeeway: new Date(prevDropoffLeeway).toISOString() });
		if (prevDropoffLeeway < prevDropoffEvent.time.size()) {
			scheduledTimes.updates.push({
				event_id: prevDropoffEvent.id,
				start: false,
				time: prevDropoffEvent.scheduledTimeStart + prevDropoffLeeway
			});
		}
	}
	return scheduledTimes;
}
