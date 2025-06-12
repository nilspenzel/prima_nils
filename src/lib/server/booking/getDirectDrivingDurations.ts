import type { ExpectedConnection } from './bookRide';
import { oneToManyCarRouting } from '../util/oneToManyCarRouting';
import type { Insertion } from './insertion';
import { type Event, type VehicleWithInterval } from './getBookingAvailability';
import { InsertHow } from '$lib/util/booking/insertionTypes';
import { printInsertionType } from './insertionTypes';

export type DirectDrivingDurations = {
	thisTour?: {
		directDrivingDuration: number | null;
		tourId: number | null;
	};
	nextTour?: {
		directDrivingDuration: number | null;
		tourId: number | null;
	};
};

export const getDirectDurations = async (
	best: Insertion,
	pickupPredEvent: Event | undefined,
	dropOffSuccEvent: Event | undefined,
	c: ExpectedConnection,
	tourIdPickup: number | undefined,
	doesConnectTours: boolean,
	departure: number,
	arrival: number,
	vehicle: VehicleWithInterval
): Promise<DirectDrivingDurations> => {
	const direct: DirectDrivingDurations = {};
	if (
		(best.pickupCase.how == InsertHow.PREPEND || best.pickupCase.how == InsertHow.NEW_TOUR) &&
		pickupPredEvent != undefined
	) {
		direct.thisTour = {
			directDrivingDuration:
				(await oneToManyCarRouting(pickupPredEvent, [c.start], false))[0] ?? null,
			tourId: tourIdPickup ?? null
		};
	}

	if (
		(best.dropoffCase.how == InsertHow.APPEND || best.dropoffCase.how == InsertHow.NEW_TOUR) &&
		dropOffSuccEvent != undefined
	) {
		direct.nextTour = {
			directDrivingDuration:
				(await oneToManyCarRouting(c.target, [dropOffSuccEvent], false))[0] ?? null,
			tourId: dropOffSuccEvent.tourId
		};
	}
	if (doesConnectTours) {
		const lastEventBeforeDeparture =
			vehicle.events.findLast((e) => e.scheduledTimeStart <= departure) ?? vehicle.lastEventBefore;
		const firstEventAfterDeparture = vehicle.events.find((e) => e.scheduledTimeStart > departure);
		const firstEventAfterArrival =
			vehicle.events.find((e) => e.scheduledTimeEnd >= arrival) ?? vehicle.firstEventAfter;
		const lastEventBeforeArrival = vehicle.events.findLast((e) => e.scheduledTimeEnd < arrival);
		if (best.pickupCase.how !== InsertHow.PREPEND && lastEventBeforeDeparture !== undefined) {
			direct.thisTour = {
				directDrivingDuration:
					(
						await oneToManyCarRouting(lastEventBeforeDeparture, [firstEventAfterDeparture!], false)
					)[0] ?? null,
				tourId: tourIdPickup ?? null
			};
		}
		if (best.dropoffCase.how !== InsertHow.APPEND && firstEventAfterArrival !== undefined) {
			direct.nextTour = {
				directDrivingDuration:
					(
						await oneToManyCarRouting(lastEventBeforeArrival!, [firstEventAfterArrival], false)
					)[0] ?? null,
				tourId: firstEventAfterArrival.tourId ?? null
			};
		}
	}
	return direct;
};
