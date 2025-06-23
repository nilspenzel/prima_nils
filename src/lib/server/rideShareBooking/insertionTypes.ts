import type { RideShareTour } from './getBookingAvailability';
import type { Range } from '$lib/util/booking/getPossibleInsertions';
import { InsertWhat } from '$lib/util/booking/insertionTypes';

export enum InsertDirection {
	BUS_STOP_DROPOFF,
	BUS_STOP_PICKUP
}

export type InsertionType = {
	direction: InsertDirection;
	what: InsertWhat;
};

export function printInsertionType(t: InsertionType) {
	let ret = 'what: ';
	switch (t.what) {
		case InsertWhat.BOTH:
			ret += 'BOTH';
			break;
		case InsertWhat.BUS_STOP:
			ret += 'BUS_STOP';
			break;
		case InsertWhat.USER_CHOSEN:
			ret += 'USER_CHOSEN';
			break;
	}
	ret += ', direction: ';
	switch (t.direction) {
		case InsertDirection.BUS_STOP_PICKUP:
			ret += 'FROM_BUS_STOP';
			break;
		case InsertDirection.BUS_STOP_DROPOFF:
			ret += 'TO_BUS_STOP';
			break;
	}
	return ret;
}

export const isEarlierBetter = (insertionCase: InsertionType) => {
	return (
		(insertionCase.direction === InsertDirection.BUS_STOP_PICKUP) !==
		(insertionCase.what === InsertWhat.BUS_STOP)
	);
};

export type InsertionInfo = {
	tourIdx: number;
	tour: RideShareTour;
	idxInTourEvents: number;
	insertionIdx: number;
	currentRange: Range;
};
