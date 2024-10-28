import { Direction, oneToMany, type OneToManyResult } from '$lib/api';
import type { BusStop } from '$lib/busStop';
import type { Company } from '$lib/compositionTypes';
import { Coordinates } from '$lib/location';
import type { Range } from './capacitySimulation';
import { iterateAllInsertions } from './utils';

export type InsertionRoutingResult = {
	fromCompany: OneToManyResult[];
	toCompany: OneToManyResult[];
	fromPrevEvent: OneToManyResult[];
	toNextEvent: OneToManyResult[];
};

export type RoutingResults = {
	busStops: InsertionRoutingResult[];
	userChosen: InsertionRoutingResult;
};

type RoutingCoordinates = {
	busStopForwardMany: Coordinates[][];
	busStopBackwardMany: Coordinates[][];
	userChosenForwardMany: Coordinates[];
	userChosenBackwardMany: Coordinates[];
};

export function gatherRoutingCoordinates(
	companies: Company[],
	insertionsByVehicle: Map<number, Range[]>
): RoutingCoordinates {
	if (companies.length == 0) {
		return {
			busStopBackwardMany: [],
			busStopForwardMany: [],
			userChosenBackwardMany: [],
			userChosenForwardMany: []
		};
	}
	const userChosenForwardMany = new Array<Coordinates>();
	const userChosenBackwardMany = new Array<Coordinates>();
	const busStopForwardMany = new Array<Coordinates[]>(companies[0].busStopFilter.length);
	const busStopBackwardMany = new Array<Coordinates[]>(companies[0].busStopFilter.length);
	for (let busStopIdx = 0; busStopIdx != companies[0].busStopFilter.length; ++busStopIdx) {
		busStopForwardMany[busStopIdx] = new Array<Coordinates>();
		busStopBackwardMany[busStopIdx] = new Array<Coordinates>();
	}
	companies.forEach((company) => {
		for (let busStopIdx = 0; busStopIdx != companies[0].busStopFilter.length; ++busStopIdx) {
			if (!company.busStopFilter[busStopIdx]) {
				continue;
			}
			busStopForwardMany[busStopIdx].push(company.coordinates);
			busStopBackwardMany[busStopIdx].push(company.coordinates);
		}
		userChosenForwardMany.push(company.coordinates);
		userChosenBackwardMany.push(company.coordinates);
	});
	iterateAllInsertions(
		companies,
		insertionsByVehicle,
		(insertionInfo, _insertionCounter, busStopFilter) => {
			const backwardCoordinates = (
				insertionInfo.insertionIdx != 0
					? insertionInfo.vehicle.events[insertionInfo.insertionIdx - 1]
					: insertionInfo.vehicle.lastEventBefore
			)?.coordinates;
			const forwardCoordinates = (
				insertionInfo.insertionIdx != insertionInfo.vehicle.events.length
					? insertionInfo.vehicle.events[insertionInfo.insertionIdx]
					: insertionInfo.vehicle.firstEventAfter
			)?.coordinates;
			if (backwardCoordinates != undefined) {
				userChosenBackwardMany.push(backwardCoordinates);
			}
			if (forwardCoordinates != undefined) {
				userChosenForwardMany.push(forwardCoordinates);
			}
			for (let busStopIdx = 0; busStopIdx != busStopFilter.length; ++busStopIdx) {
				if (!busStopFilter[busStopIdx]) {
					continue;
				}
				if (backwardCoordinates != undefined) {
					busStopBackwardMany[busStopIdx].push(backwardCoordinates);
				}
				if (forwardCoordinates != undefined) {
					busStopForwardMany[busStopIdx].push(forwardCoordinates);
				}
			}
		}
	);
	return {
		busStopForwardMany,
		busStopBackwardMany,
		userChosenForwardMany,
		userChosenBackwardMany
	};
}

export async function routing(
	companies: Company[],
	coordinates: RoutingCoordinates,
	userChosen: Coordinates,
	busStops: BusStop[]
): Promise<RoutingResults> {
	const from = await oneToMany(userChosen, coordinates.userChosenBackwardMany, Direction.Backward);
	const to = await oneToMany(userChosen, coordinates.userChosenForwardMany, Direction.Forward);
	const ret = {
		userChosen: {
			fromCompany: from.slice(0, busStops.length),
			fromPrevEvent: from.slice(busStops.length),
			toCompany: to.slice(0, busStops.length),
			toNextEvent: to.slice(busStops.length)
		},
		busStops: new Array<InsertionRoutingResult>(busStops.length)
	};
	for (let busStopIdx = 0; busStopIdx != busStops.length; ++busStopIdx) {
		const busStop = busStops[busStopIdx];
		const relevantCompanyCount = companies.filter(
			(company) => company.busStopFilter[busStopIdx]
		).length;
		const from = await oneToMany(
			busStop.coordinates,
			coordinates.busStopBackwardMany[busStopIdx],
			Direction.Backward
		);
		const to = await oneToMany(
			busStop.coordinates,
			coordinates.busStopForwardMany[busStopIdx],
			Direction.Forward
		);
		ret.busStops[busStopIdx] = {
			fromCompany: from.slice(0, relevantCompanyCount),
			fromPrevEvent: from.slice(relevantCompanyCount),
			toCompany: to.slice(0, relevantCompanyCount),
			toNextEvent: to.slice(relevantCompanyCount)
		};
	}
	return ret;
}