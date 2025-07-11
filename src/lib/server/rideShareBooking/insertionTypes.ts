import type { Range } from '$lib/util/booking/getPossibleInsertions';
import type { RideShareEvent } from './getBookingAvailability';

export type InsertionInfo = {
	rideShareTourIdx: number;
	events: RideShareEvent[];
	idxInEvents: number;
	insertionIdx: number;
	currentRange: Range;
	provider: number;
};
