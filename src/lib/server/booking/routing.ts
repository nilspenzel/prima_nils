import type { Coordinates } from '$lib/util/Coordinates';
import type { BusStop } from './BusStop';
import type { Company } from './getBookingAvailability';
import { isSamePlace } from './isSamePlace';
import { batchOneToManyCarRouting } from '$lib/server/util/batchOneToManyCarRouting';
import type { VehicleId } from './VehicleId';
import type { Range } from '$lib/util/booking/getPossibleInsertions';
import { iterateAllInsertions } from './iterateAllInsertions';

export type InsertionRoutingResult = {
	company: (number | undefined)[];
	event: (number | undefined)[];
};

export type RoutingResults = {
	busStops: { from: InsertionRoutingResult[]; to: InsertionRoutingResult[] };
	userChosen: { from: InsertionRoutingResult; to: InsertionRoutingResult };
};

export async function routing(
	companies: Company[],
	userChosen: Coordinates,
	busStops: BusStop[],
	insertionRanges: Map<VehicleId, Range[]>
): Promise<RoutingResults> {
	const coords: Coordinates[] = companies.map((c) => {
		return { lat: c.lat, lng: c.lng };
	});
	iterateAllInsertions(companies, insertionRanges, (info, _) => {
		if (info.idxInEvents !== info.vehicle.events.length) {
			coords.push(info.vehicle.events[info.idxInEvents]);
		}
	});
	const setZeroDistanceForMatchingPlaces = (
		coordinates: Coordinates,
		routingResult: (number | undefined)[]
	) => {
		console.assert(coords.length == routingResult.length);
		for (let i = 0; i != coords.length; ++i) {
			if (isSamePlace(coordinates, coords[i])) {
				routingResult[i] = 0;
			}
		}
	};
	const fromUserChosen = await batchOneToManyCarRouting(userChosen, coords, false);
	const toUserChosen = await batchOneToManyCarRouting(userChosen, coords, true);
	setZeroDistanceForMatchingPlaces(userChosen, fromUserChosen);
	setZeroDistanceForMatchingPlaces(userChosen, toUserChosen);

	const fromBusStop = await Promise.all(
		busStops.map((b) => batchOneToManyCarRouting(b, coords, false))
	);
	const toBusStop = await Promise.all(
		busStops.map((b) => batchOneToManyCarRouting(b, coords, true))
	);

	return {
		userChosen: {
			from: {
				company: fromUserChosen.slice(0, companies.length),
				event: fromUserChosen.slice(companies.length)
			},
			to: {
				company: toUserChosen.slice(0, companies.length),
				event: toUserChosen.slice(companies.length)
			}
		},
		busStops: {
			from: fromBusStop.map((b, busStopIdx) => {
				setZeroDistanceForMatchingPlaces(busStops[busStopIdx], b);
				return {
					company: b.slice(0, companies.length),
					event: b.slice(companies.length)
				};
			}),
			to: toBusStop.map((b, busStopIdx) => {
				setZeroDistanceForMatchingPlaces(busStops[busStopIdx], b);
				return {
					company: b.slice(0, companies.length),
					event: b.slice(companies.length)
				};
			})
		}
	};
}
