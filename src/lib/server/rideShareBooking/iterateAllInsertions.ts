import type { RideShareTour } from './getBookingAvailability';
import type { InsertionInfo } from './insertionTypes';
import type { Range } from '$lib/util/booking/getPossibleInsertions';

export async function iterateAllInsertions(
	companies: RideShareTour[],
	insertions: Map<number, Range[]>,
	insertionFn: (info: InsertionInfo) => void
) {
	let insertionIdx = 0;
	companies.forEach((tour, tourIdx) => {
		insertions.get(tour.rideShareTour)!.forEach((insertion) => {
			for (
				let idxInEvents = insertion.earliestPickup;
				idxInEvents != insertion.latestDropoff + 1;
				++idxInEvents
			) {
				insertionFn({
					idxInTourEvents: idxInEvents,
					tourIdx: tourIdx,
					tour,
					currentRange: insertion,
					insertionIdx
				});
				insertionIdx++;
			}
		});
	});
}
