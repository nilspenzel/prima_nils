import { oneToMany } from '$lib/api';
import type { BusStop } from '$lib/busStop';
import type { Company } from '$lib/compositionTypes';
import { COORDINATE_ROUNDING_ERROR_THRESHOLD } from '$lib/constants';
import { Coordinates } from '$lib/location';
import { minutesToMs } from '$lib/time_utils';
import type { Range } from './capacitySimulation';
import { iterateAllInsertions } from './utils';

export type InsertionRoutingResult = {
	company: (number|undefined)[];
	event: (number|undefined)[];
};

export type RoutingResults = {
	busStops: InsertionRoutingResult[];
	userChosen: InsertionRoutingResult;
};

export function gatherRoutingCoordinates(
	companies: Company[],
	insertionsByVehicle: Map<number, Range[]>
) {
	if (companies.length == 0) {
		return { forward: [], backward: [] };
	}
	const backward = new Array<Coordinates>();
	const forward = new Array<Coordinates>();
	companies.forEach((company) => {
		forward.push(company.coordinates);
		backward.push(company.coordinates);
	});
	iterateAllInsertions(companies, insertionsByVehicle, (insertionInfo, _insertionCounter) => {
		const vehicle = insertionInfo.vehicle;
		const idxInEvents = insertionInfo.idxInEvents;
		if (idxInEvents != 0) {
			backward.push(vehicle.events[idxInEvents - 1].coordinates);
		} else if (vehicle.lastEventBefore != undefined) {
			backward.push(vehicle.lastEventBefore.coordinates);
		}
		if (idxInEvents != vehicle.events.length) {
			forward.push(vehicle.events[idxInEvents].coordinates);
		} else if (vehicle.firstEventAfter != undefined) {
			forward.push(vehicle.firstEventAfter.coordinates);
		}
	});
	return { forward, backward };
}

export async function routing(
	companies: Company[],
	many: { forward: Coordinates[]; backward: Coordinates[] },
	userChosen: Coordinates,
	busStops: BusStop[],
	startFixed: boolean
): Promise<RoutingResults> {
	const findMatchingPlaces = (coordinates: Coordinates, many: Coordinates[], routingResult: (number|undefined)[]) => {
		console.assert(many.length == routingResult.length);
		for(let i=0;i!=many.length;++i){
			if(Math.abs(coordinates.lat - many[i].lng)<COORDINATE_ROUNDING_ERROR_THRESHOLD||Math.abs(coordinates.lng - many[i].lng)){
				routingResult[i] = 0;
			}
		}
	}

	const userChosenResult = await oneToMany(
		userChosen,
		startFixed ? many.backward : many.forward,
		!startFixed
	);
	const ret = {
		userChosen: {
			company: userChosenResult.slice(0, companies.length),
			event: userChosenResult.slice(companies.length)
		},
		busStops: new Array<InsertionRoutingResult>(busStops.length)
	};
	for (let busStopIdx = 0; busStopIdx != busStops.length; ++busStopIdx) {
		const busStopResult = await oneToMany(
			busStops[busStopIdx].coordinates,
			!startFixed ? many.backward : many.forward,
			startFixed
		);
		findMatchingPlaces(busStops[busStopIdx].coordinates, !startFixed ? many.backward : many.forward, busStopResult);
		ret.busStops[busStopIdx] = {
			company: busStopResult.slice(0, companies.length),
			event: busStopResult.slice(companies.length)
		};
	}
	return ret;
}
