import type { Company } from '$lib/compositionTypes';
import { COORDINATE_ROUNDING_ERROR_THRESHOLD } from '$lib/constants';
import type { Coordinates } from '$lib/location';
import type { Range } from './capacitySimulation';
import type { InsertionInfo } from './insertionTypes';

export function iterateAllInsertions(
	companies: Company[],
	insertions: Map<number, Range[]>,
	insertionFn: (info: InsertionInfo, insertionCounter: number) => void
) {
	let prevEventIdxInRoutingResults = 0;
	let nextEventIdxInRoutingResults = 0;
	let insertionIdx = 0;
	companies.forEach((company, companyIdx) => {
		company.vehicles.forEach((vehicle) => {
			insertions.get(vehicle.id)!.forEach((insertion) => {
				for (
					let idxInEvents = insertion.earliestPickup;
					idxInEvents != insertion.latestDropoff + 1;
					++idxInEvents
				) {
					const info = {
						idxInEvents,
						companyIdx,
						vehicle,
						prevEventIdxInRoutingResults,
						nextEventIdxInRoutingResults,
						currentRange: insertion
					};
					insertionFn(info, insertionIdx);
					if (idxInEvents != 0 || vehicle.lastEventBefore != undefined) {
						prevEventIdxInRoutingResults++;
					}
					if (idxInEvents != vehicle.events.length || vehicle.firstEventAfter != undefined) {
						nextEventIdxInRoutingResults++;
					}
					insertionIdx++;
				}
			});
		});
	});
}

export const samePlace = (c1: Coordinates, c2: Coordinates) => {
	return Math.abs(c1.lat - c2.lat)<COORDINATE_ROUNDING_ERROR_THRESHOLD&&Math.abs(c1.lng - c2.lng)<COORDINATE_ROUNDING_ERROR_THRESHOLD;
}