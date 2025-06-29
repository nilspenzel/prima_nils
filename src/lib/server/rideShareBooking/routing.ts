import type { Coordinates } from '$lib/util/Coordinates';
import type { BusStop } from './BusStop';
import type { RideShareTour } from './getBookingAvailability';
import { isSamePlace } from './isSamePlace';
import { batchOneToManyCarRouting } from '$lib/server/util/batchOneToManyCarRouting';
import type { Range } from '$lib/util/booking/getPossibleInsertions';
import { iterateAllInsertions } from './iterateAllInsertions';
import { PASSENGER_CHANGE_DURATION } from '$lib/constants';

export type InsertionRoutingResult = {
	company: (number | undefined)[];
	event: (number | undefined)[];
};

export type RoutingResults = {
	busStops: { fromBusStop: InsertionRoutingResult[]; toBusStop: InsertionRoutingResult[] };
	userChosen: { fromUserChosen: InsertionRoutingResult; toUserChosen: InsertionRoutingResult };
};

export async function routing(
	tours: RideShareTour[],
	userChosen: Coordinates,
	busStops: BusStop[],
	insertionRanges: Map<number, Range[]>
): Promise<RoutingResults> {
	const setZeroDistanceForMatchingPlaces = (
		coordinatesOne: Coordinates,
		coordinatesMany: (Coordinates | undefined)[],
		routingResult: (number | undefined)[]
	) => {
		const result = new Array<number | undefined>(routingResult.length);
		for (let i = 0; i != coordinatesMany.length; ++i) {
			if (coordinatesMany[i] === undefined) {
				continue;
			}
			if (isSamePlace(coordinatesOne, coordinatesMany[i]!)) {
				result[i] = 0;
			} else {
				result[i] = routingResult[i]! + PASSENGER_CHANGE_DURATION;
			}
		}
		return result;
	};

	const forward: ((Coordinates & { eventId: number }) | undefined)[] = [];

	const backward: ((Coordinates & { eventId: number }) | undefined)[] = [];
	iterateAllInsertions(tours, insertionRanges, (info) => {
		forward.push(
			info.idxInTourEvents === info.tour.events.length
				? undefined
				: info.tour.events[info.idxInTourEvents]
		);
		backward.push(
			info.idxInTourEvents === 0 ? undefined : info.tour.events[info.idxInTourEvents - 1]
		);
	});
	let fromUserChosen = await batchOneToManyCarRouting(userChosen, forward, false);
	const toUserChosen = await batchOneToManyCarRouting(userChosen, backward, true);
	fromUserChosen = setZeroDistanceForMatchingPlaces(userChosen, forward, fromUserChosen);
	let companyToUserChosen = toUserChosen.slice(0, tours.length);
	let eventToUserChosen = toUserChosen.slice(tours.length);
	companyToUserChosen = setZeroDistanceForMatchingPlaces(
		userChosen,
		backward.slice(0, tours.length),
		companyToUserChosen
	);
	eventToUserChosen = setZeroDistanceForMatchingPlaces(
		userChosen,
		backward.slice(tours.length),
		eventToUserChosen
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
				company: fromUserChosen.slice(0, tours.length),
				event: fromUserChosen.slice(tours.length)
			},
			toUserChosen: {
				company: companyToUserChosen,
				event: eventToUserChosen
			}
		},
		busStops: {
			fromBusStop: fromBusStop.map((b, busStopIdx) => {
				const updatedB = setZeroDistanceForMatchingPlaces(busStops[busStopIdx], forward, b);
				return {
					company: updatedB.slice(0, tours.length),
					event: updatedB.slice(tours.length)
				};
			}),
			toBusStop: toBusStop.map((b, busStopIdx) => {
				const values = {
					company: b.slice(0, tours.length),
					event: b.slice(tours.length)
				};
				values.company = setZeroDistanceForMatchingPlaces(
					busStops[busStopIdx],
					backward.slice(0, tours.length),
					values.company
				);
				values.event = setZeroDistanceForMatchingPlaces(
					busStops[busStopIdx],
					backward.slice(tours.length),
					values.event
				);
				return values;
			})
		}
	};
}
