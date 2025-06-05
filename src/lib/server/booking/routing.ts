import type { Coordinates } from '$lib/util/Coordinates';
import type { BusStop } from './BusStop';
import type { Company } from './getBookingAvailability';
import { isSamePlace } from './isSamePlace';
import { batchOneToManyCarRouting } from '$lib/server/util/batchOneToManyCarRouting';
import type { VehicleId } from './VehicleId';
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
	companies: Company[],
	userChosen: Coordinates,
	busStops: BusStop[],
	insertionRanges: Map<VehicleId, Range[]>
): Promise<RoutingResults> {
	const setZeroDistanceForMatchingPlaces = (
		coordinatesOne: Coordinates,
		coordinatesMany: Coordinates[],
		routingResult: (number | undefined)[],
		isApproach: boolean
	) => {
		console.assert(
			coordinatesMany.length == routingResult.length,
			{ coordinatesMany },
			{ routingResult }
		);
		for (let i = 0; i != coordinatesMany.length; ++i) {
			if (isSamePlace(coordinatesOne, coordinatesMany[i])) {
				routingResult[i] = 0;
			} else if (!isApproach && routingResult[i] !== undefined) {
				routingResult[i]! += PASSENGER_CHANGE_DURATION;
			}
		}
	};

	const coords: Coordinates[] = companies.map((c) => {
		return { lat: c.lat, lng: c.lng };
	});
	iterateAllInsertions(companies, insertionRanges, (info, _) => {
		if (info.idxInEvents !== info.vehicle.events.length) {
			coords.push(info.vehicle.events[info.idxInEvents]);
		}
	});
	const fromUserChosen = await batchOneToManyCarRouting(userChosen, coords, false);
	const toUserChosen = await batchOneToManyCarRouting(userChosen, coords, true);
	setZeroDistanceForMatchingPlaces(userChosen, coords, fromUserChosen, false);
	const companyToUserChosen = toUserChosen.slice(0, companies.length);
	const eventToUserChosen = toUserChosen.slice(companies.length);
	setZeroDistanceForMatchingPlaces(
		userChosen,
		coords.slice(0, companies.length),
		companyToUserChosen,
		true
	);
	setZeroDistanceForMatchingPlaces(
		userChosen,
		coords.slice(companies.length),
		eventToUserChosen,
		false
	);

	const fromBusStop = await Promise.all(
		busStops.map((b) => batchOneToManyCarRouting(b, coords, false))
	);
	const toBusStop = await Promise.all(
		busStops.map((b) => batchOneToManyCarRouting(b, coords, true))
	);
	return {
		userChosen: {
			fromUserChosen: {
				company: fromUserChosen.slice(0, companies.length),
				event: fromUserChosen.slice(companies.length)
			},
			toUserChosen: {
				company: toUserChosen.slice(0, companies.length),
				event: toUserChosen.slice(companies.length)
			}
		},
		busStops: {
			fromBusStop: fromBusStop.map((b, busStopIdx) => {
				setZeroDistanceForMatchingPlaces(busStops[busStopIdx], coords, b, false);
				return {
					company: b.slice(0, companies.length),
					event: b.slice(companies.length)
				};
			}),
			toBusStop: toBusStop.map((b, busStopIdx) => {
				const values = {
					company: b.slice(0, companies.length),
					event: b.slice(companies.length)
				};
				setZeroDistanceForMatchingPlaces(
					busStops[busStopIdx],
					coords.slice(0, companies.length),
					values.company,
					true
				);
				setZeroDistanceForMatchingPlaces(
					busStops[busStopIdx],
					coords.slice(companies.length),
					values.event,
					false
				);
				return values;
			})
		}
	};
}
