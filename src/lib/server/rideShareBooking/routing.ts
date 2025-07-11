import type { Coordinates } from '$lib/util/Coordinates';
import { isSamePlace } from './isSamePlace';
import { batchOneToManyCarRouting } from '$lib/server/util/batchOneToManyCarRouting';
import type { Range } from '$lib/util/booking/getPossibleInsertions';
import { iterateAllInsertions } from './iterateAllInsertions';
import { PASSENGER_CHANGE_DURATION } from '$lib/constants';
import type { VehicleId } from '../booking/VehicleId';
import type { RideShareTour } from './getBookingAvailability';
import type { BusStop } from '../booking/BusStop';

export type InsertionRoutingResult = {
	company: (number | undefined)[];
	event: (number | undefined)[];
};

export type RoutingResults = {
	busStops: { fromBusStop: InsertionRoutingResult[]; toBusStop: InsertionRoutingResult[] };
	userChosen: { fromUserChosen: InsertionRoutingResult; toUserChosen: InsertionRoutingResult };
};

export async function routing(
	rideShareTours: RideShareTour[],
	userChosen: Coordinates,
	busStops: BusStop[],
	insertionRanges: Map<VehicleId, Range[]>
): Promise<RoutingResults> {
	const setZeroDistanceForMatchingPlaces = (
		coordinatesOne: Coordinates,
		coordinatesMany: (Coordinates | undefined)[],
		routingResult: (number | undefined)[],
		comesFromCompany: boolean
	) => {
		const result = new Array<number | undefined>(routingResult.length);
		for (let i = 0; i != coordinatesMany.length; ++i) {
			if (coordinatesMany[i] === undefined) {
				continue;
			}
			if (isSamePlace(coordinatesOne, coordinatesMany[i]!)) {
				result[i] = 0;
			} else if (!comesFromCompany && routingResult[i] !== undefined) {
				result[i] = routingResult[i]! + PASSENGER_CHANGE_DURATION;
			} else {
				result[i] = routingResult[i];
			}
		}
		return result;
	};

	const forward: ((Coordinates & { eventId: number }) | undefined)[] = [];

	const backward: ((Coordinates & { eventId: number }) | undefined)[] = [];
	iterateAllInsertions(rideShareTours, insertionRanges, (info) => {
		forward.push(
			info.idxInEvents === info.events.length ? undefined : info.events[info.idxInEvents]
		);
		backward.push(info.idxInEvents === 0 ? undefined : info.events[info.idxInEvents - 1]);
	});
	let fromUserChosen = await batchOneToManyCarRouting(userChosen, forward, false);
	const toUserChosen = await batchOneToManyCarRouting(userChosen, backward, true);
	fromUserChosen = setZeroDistanceForMatchingPlaces(userChosen, forward, fromUserChosen, false);
	let companyToUserChosen = toUserChosen.slice(0, rideShareTours.length);
	let eventToUserChosen = toUserChosen.slice(rideShareTours.length);
	companyToUserChosen = setZeroDistanceForMatchingPlaces(
		userChosen,
		backward.slice(0, rideShareTours.length),
		companyToUserChosen,
		true
	);
	eventToUserChosen = setZeroDistanceForMatchingPlaces(
		userChosen,
		backward.slice(rideShareTours.length),
		eventToUserChosen,
		false
	);

	const fromBusStop = await Promise.all(
		busStops.map((b) => batchOneToManyCarRouting(b, forward, false))
	);
	const toBusStop = await Promise.all(
		busStops.map((b) => batchOneToManyCarRouting(b, backward, true))
	);
	return {
		userChosen: {
			fromUserChosen: {
				company: fromUserChosen.slice(0, rideShareTours.length),
				event: fromUserChosen.slice(rideShareTours.length)
			},
			toUserChosen: {
				company: companyToUserChosen,
				event: eventToUserChosen
			}
		},
		busStops: {
			fromBusStop: fromBusStop.map((b, busStopIdx) => {
				const updatedB = setZeroDistanceForMatchingPlaces(busStops[busStopIdx], forward, b, false);
				return {
					company: updatedB.slice(0, rideShareTours.length),
					event: updatedB.slice(rideShareTours.length)
				};
			}),
			toBusStop: toBusStop.map((b, busStopIdx) => {
				const values = {
					company: b.slice(0, rideShareTours.length),
					event: b.slice(rideShareTours.length)
				};
				values.company = setZeroDistanceForMatchingPlaces(
					busStops[busStopIdx],
					backward.slice(0, rideShareTours.length),
					values.company,
					true
				);
				values.event = setZeroDistanceForMatchingPlaces(
					busStops[busStopIdx],
					backward.slice(rideShareTours.length),
					values.event,
					false
				);
				return values;
			})
		}
	};
}
