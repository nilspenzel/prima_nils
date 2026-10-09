import type { ExpectedConnection } from '$lib/server/booking/expectedConnection';
import type { Insertion } from '../insertion';
import { type Event, type VehicleWithInterval } from '../getBookingAvailability';
import { InsertHow } from '$lib/util/booking/insertionTypes';
import { getTaxiConnectionDuration } from '../getTaxiConnectionDuration';
import {
	getFirstEventOfEarliestTourStartingAfter,
	getFirstEventOfTours,
	getLastEventOfLatestTourEndingBefore,
	getLastEventOfTours
} from './tourBoundaryEvents';

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
	mergeTourIds: number[],
	departure: number,
	arrival: number,
	vehicle: VehicleWithInterval
): Promise<DirectDrivingDurations> => {
	const direct: DirectDrivingDurations = {};
	if (
		(best.pickupCase.how == InsertHow.PREPEND || best.pickupCase.how == InsertHow.NEW_TOUR) &&
		pickupPredEvent != undefined
	) {
		const routing = await getTaxiConnectionDuration(pickupPredEvent, c.start, false, {
			addPassengerChange: true
		});
		direct.thisTour = {
			directDrivingDuration: routing ?? null,
			tourId: tourIdPickup ?? null
		};
	}

	if (
		(best.dropoffCase.how == InsertHow.APPEND || best.dropoffCase.how == InsertHow.NEW_TOUR) &&
		dropOffSuccEvent != undefined
	) {
		const routing = await getTaxiConnectionDuration(c.target, dropOffSuccEvent, false, {
			addPassengerChange: true
		});
		direct.nextTour = {
			directDrivingDuration: routing ?? null,
			tourId: dropOffSuccEvent.tourId
		};
	}
	if (mergeTourIds.length !== 0) {
		const mergedTourIds = new Set(mergeTourIds);
		const firstEventInMergedTours = getFirstEventOfTours(vehicle.events, mergedTourIds);
		const lastEventInMergedTours = getLastEventOfTours(vehicle.events, mergedTourIds);
		const lastEventBeforeDeparture =
			getLastEventOfLatestTourEndingBefore(vehicle.events, departure, mergedTourIds) ??
			vehicle.lastEventBefore;
		const firstEventAfterArrival =
			getFirstEventOfEarliestTourStartingAfter(vehicle.events, arrival, mergedTourIds) ??
			vehicle.firstEventAfter;
		if (
			best.pickupCase.how !== InsertHow.PREPEND &&
			lastEventBeforeDeparture !== undefined &&
			firstEventInMergedTours !== undefined
		) {
			const routing = await getTaxiConnectionDuration(
				lastEventBeforeDeparture,
				firstEventInMergedTours,
				false,
				{ addPassengerChange: true }
			);
			direct.thisTour = {
				directDrivingDuration: routing ?? null,
				tourId: tourIdPickup ?? null
			};
		}
		if (
			best.dropoffCase.how !== InsertHow.APPEND &&
			lastEventInMergedTours !== undefined &&
			firstEventAfterArrival !== undefined
		) {
			const routing = await getTaxiConnectionDuration(
				lastEventInMergedTours,
				firstEventAfterArrival,
				false,
				{ addPassengerChange: true }
			);
			direct.nextTour = {
				directDrivingDuration: routing ?? null,
				tourId: firstEventAfterArrival.tourId ?? null
			};
		}
	}
	return direct;
};
