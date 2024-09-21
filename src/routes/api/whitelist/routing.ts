import { Direction, oneToMany, type OneToManyResult } from '$lib/api';
import type { BusStop } from '$lib/busStop';
import type { Company, Event } from '$lib/compositionTypes';
import { Coordinates } from '$lib/location';
import type { Vehicle } from '$lib/compositionTypes';
import type { Range } from './capacitySimulation';

export type InsertionRoutingResult = {
	fromPrev: OneToManyResult[];
	toNext: OneToManyResult[];
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

export function iterateAllInsertions(
	companies: Company[],
	insertions: Map<number, Range[]>,
	insertionFn: (
		events: Event[],
		insertionIdx: number,
		companyPos: number,
		prevEventPos: number | undefined,
		nextEventPos: number | undefined,
		vehicle: Vehicle
	) => void
) {
	let companyPos = 0;
	let prevEventPos = companies.length;
	let nextEventPos = companies.length;
	companies.forEach((company) => {
		company.vehicles.forEach((vehicle) => {
			const events = vehicle.tours.flatMap((t) => t.events);
			insertions.get(vehicle.id)!.forEach((insertion) => {
				for (
					let insertionIdx = insertion.earliestPickup;
					insertionIdx != insertion.latestDropoff + 1;
					++insertionIdx
				) {
					insertionFn(
						events,
						insertionIdx,
						companyPos,
						insertionIdx != 0 ? prevEventPos++ : undefined,
						insertionIdx != events.length ? nextEventPos++ : undefined,
						vehicle
					);
				}
			});
		});
		companyPos++;
	});
}

type InsertionCounts = {
	prev: number;
	next: number;
};

function getInsertionCounts(
	companies: Company[],
	insertionsByVehicle: Map<number, Range[]>
): InsertionCounts {
	let onlyPrevCount = 0;
	let onlyNextCount = 0;
	let insertionCount = 0;
	for (let companyIdx = 0; companyIdx != companies.length; ++companyIdx) {
		const company = companies[companyIdx];
		for (let vehicleIdx = 0; vehicleIdx != company.vehicles.length; ++vehicleIdx) {
			const vehicle = company.vehicles[vehicleIdx];
			const events = vehicle.tours.flatMap((t) => t.events);
			const insertions = insertionsByVehicle.get(vehicle.id)!;
			for (let i = 0; i != insertions.length; ++i) {
				const insertionRange = insertions[i];
				insertionCount += 1 + insertionRange.latestDropoff - insertionRange.earliestPickup;
				onlyNextCount += insertionRange.earliestPickup == 0 ? 1 : 0;
				onlyPrevCount += insertionRange.latestDropoff == events.length ? 1 : 0;
			}
		}
	}
	return {
		next: companies.length + insertionCount - onlyPrevCount,
		prev: companies.length + insertionCount - onlyNextCount
	};
}

export function gatherRoutingCoordinates(
	companies: Company[],
	busStops: BusStop[],
	insertionsByVehicle: Map<number, Range[]>
): RoutingCoordinates {
	const insertionCounts = getInsertionCounts(companies, insertionsByVehicle);
	const busStopForwardMany = new Array<Coordinates[]>(busStops.length);
	const busStopBackwardMany = new Array<Coordinates[]>(busStops.length);
	for (let i = 0; i != busStops.length; ++i) {
		busStopForwardMany[i] = new Array<Coordinates>(insertionCounts.next);
		busStopBackwardMany[i] = new Array<Coordinates>(insertionCounts.prev);
	}
	const userChosenForwardMany = new Array<Coordinates>(insertionCounts.next);
	const userChosenBackwardMany = new Array<Coordinates>(insertionCounts.prev);
	companies.forEach((company, companyPos) => {
		for (let busStopIdx = 0; busStopIdx != busStops.length; ++busStopIdx) {
			busStopForwardMany[busStopIdx][companyPos] = company.coordinates;
			busStopBackwardMany[busStopIdx][companyPos] = company.coordinates;
		}
		userChosenForwardMany[companyPos] = company.coordinates;
		userChosenBackwardMany[companyPos] = company.coordinates;
	});
	iterateAllInsertions(
		companies,
		insertionsByVehicle,
		(events, insertionIdx, companyPos_, prevEventPos, nextEventPos, vehicle_) => {
			if (prevEventPos != undefined) {
				const prevEventCoordinates = events[insertionIdx - 1].coordinates;
				for (let busStopIdx = 0; busStopIdx != busStops.length; ++busStopIdx) {
					busStopBackwardMany[busStopIdx][prevEventPos] = prevEventCoordinates;
				}
				userChosenBackwardMany[prevEventPos] = prevEventCoordinates;
			}
			if (nextEventPos != undefined) {
				const nextEventCoordinates = events[insertionIdx].coordinates;
				for (let busStopIdx = 0; busStopIdx != busStops.length; ++busStopIdx) {
					busStopForwardMany[busStopIdx][nextEventPos] = nextEventCoordinates;
				}
				userChosenForwardMany[nextEventPos] = nextEventCoordinates;
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
	coordinates: RoutingCoordinates,
	userChosen: Coordinates,
	busStops: BusStop[]
): Promise<RoutingResults> {
	const ret = {
		userChosen: {
			fromPrev: await oneToMany(userChosen, coordinates.userChosenBackwardMany, Direction.Backward),
			toNext: await oneToMany(userChosen, coordinates.userChosenForwardMany, Direction.Forward)
		},
		busStops: new Array<InsertionRoutingResult>(busStops.length)
	};
	for (let busStopIdx = 0; busStopIdx != busStops.length; ++busStopIdx) {
		const busStop = busStops[busStopIdx];
		ret.busStops[busStopIdx] = {
			fromPrev: await oneToMany(
				busStop.coordinates,
				coordinates.busStopBackwardMany[busStopIdx],
				Direction.Backward
			),
			toNext: await oneToMany(
				busStop.coordinates,
				coordinates.busStopForwardMany[busStopIdx],
				Direction.Forward
			)
		};
	}
	return ret;
}
