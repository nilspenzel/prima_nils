import { InsertHow } from '$lib/util/booking/insertionTypes';
import type { RideShareEvent } from './getRideShareTours';

export const getMergeTourList = (
	events: RideShareEvent[],
	pickupHow: InsertHow,
	dropoffHow: InsertHow,
	pickupIdx: number | undefined,
	dropoffIdx: number | undefined
): RideShareEvent[] => {
	if (events.length == 0 || pickupHow === InsertHow.NEW_TOUR) {
		return [];
	}
	const tours = new Set<number>();
	if (pickupHow == InsertHow.CONNECT) {
		tours.add(events[pickupIdx! - 1].tourId);
	}
	if (dropoffHow == InsertHow.CONNECT) {
		tours.add(events[dropoffIdx!].tourId); // TODO testcase
	}
	events.slice(pickupIdx ?? 0, dropoffIdx ?? events.length - 1).forEach((ev) => {
		tours.add(ev.tourId);
	});
	return [...tours].map((t) => events.find((e) => t === e.tourId)).filter((e) => e !== undefined);
};
