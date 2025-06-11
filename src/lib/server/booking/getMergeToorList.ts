import type { Event } from '$lib/server/booking/getBookingAvailability';
import { InsertHow } from '$lib/util/booking/insertionTypes';

export const getMergeTourList = (
	events: Event[],
	pickupHow: InsertHow,
	dropoffHow: InsertHow,
	pickupIdx: number | undefined,
	dropoffIdx: number | undefined
): Set<{ tourId: number; departure: number; arrival: number }> => {
	if (events.length == 0) {
		return new Set<{ tourId: number; departure: number; arrival: number }>();
	}
	const tours = new Set<{ tourId: number; departure: number; arrival: number }>();
	if (pickupHow == InsertHow.CONNECT) {
		tours.add(events[pickupIdx! - 1]);
	}
	if (dropoffHow == InsertHow.CONNECT) {
		tours.add(events[dropoffIdx!]); // TODO testcase
	}
	events.slice(pickupIdx ?? 0, dropoffIdx ?? events.length - 1).forEach((ev) => {
		tours.add(ev);
	});
	if (tours.size == 1) {
		return new Set<{ tourId: number; departure: number; arrival: number }>();
	}
	return tours;
};
