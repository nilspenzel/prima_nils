import type { Mode } from '$lib/openapi';
import { oneToManyCarRouting } from '$lib/server/util/oneToManyCarRouting';
import { isSamePlace } from '$lib/util/booking/isSamePlace';

type StreetCheckPlace = {
	name: string;
	lat: number;
	lon: number;
};

type StreetCheckLeg = {
	mode: Mode;
	duration: number;
	from: StreetCheckPlace;
	to: StreetCheckPlace;
};

type StreetCheckItinerary = {
	legs: readonly StreetCheckLeg[];
};

type StreetRouting = (
	one: { lat: number; lng: number },
	many: { lat: number; lng: number }[],
	arriveBy: boolean
) => Promise<(number | undefined)[]>;

export type OdmStreetTolerance = {
	minSavingSeconds: number;
	minSavingPercent: number;
};

export type SuboptimalEdgeOdmConnection = {
	edge: 'start' | 'end';
	comparedLegIndex: number;
	comparedMode: Mode;
	odmDurationSeconds: number;
	streetDurationSeconds: number;
	savingSeconds: number;
	savingPercent: number;
};

export type IndexedSuboptimalEdgeOdmConnection = SuboptimalEdgeOdmConnection & {
	itineraryIndex: number;
};

const coordinates = (place: StreetCheckPlace) => ({ lat: place.lat, lng: place.lon });

function eligibleLegs(legs: readonly StreetCheckLeg[]) {
	return legs
		.map((leg, index) => ({ leg, index }))
		.filter(({ leg }) => leg.mode !== 'WALK' && leg.mode !== 'ODM');
}

function finding(
	edge: 'start' | 'end',
	odmLeg: StreetCheckLeg,
	comparedLeg: StreetCheckLeg,
	comparedLegIndex: number,
	streetDurationMs: number | undefined,
	tolerance: OdmStreetTolerance
): SuboptimalEdgeOdmConnection | undefined {
	if (streetDurationMs === undefined) {
		return undefined;
	}
	const streetDurationSeconds = streetDurationMs / 1000;
	const savingSeconds = odmLeg.duration - streetDurationSeconds;
	const savingPercent = (savingSeconds / odmLeg.duration) * 100;
	if (savingSeconds < tolerance.minSavingSeconds || savingPercent < tolerance.minSavingPercent) {
		return undefined;
	}
	return {
		edge,
		comparedLegIndex,
		comparedMode: comparedLeg.mode,
		odmDurationSeconds: Math.round(odmLeg.duration),
		streetDurationSeconds: Math.round(streetDurationSeconds),
		savingSeconds: Math.round(savingSeconds),
		savingPercent: Math.round(savingPercent)
	};
}

type PendingComparison = {
	itineraryIndex: number;
	edge: 'start' | 'end';
	odmLeg: StreetCheckLeg;
	comparedLeg: StreetCheckLeg;
	comparedLegIndex: number;
	one: { lat: number; lng: number };
	many: { lat: number; lng: number };
	arriveBy: boolean;
};

type RoutingGroup = {
	one: PendingComparison['one'];
	arriveBy: boolean;
	targets: PendingComparison['many'][];
	comparisons: (PendingComparison & { targetIndex: number })[];
};

export async function findSuboptimalEdgeOdmConnectionsInItineraries(
	itineraries: readonly StreetCheckItinerary[],
	tolerance: OdmStreetTolerance,
	streetRouting: StreetRouting = oneToManyCarRouting
): Promise<IndexedSuboptimalEdgeOdmConnection[]> {
	const comparisons: PendingComparison[] = [];
	for (const [itineraryIndex, itinerary] of itineraries.entries()) {
		if (itinerary.legs.length === 0) {
			continue;
		}
		const candidates = eligibleLegs(itinerary.legs);
		const firstLeg = itinerary.legs[0];
		const lastLeg = itinerary.legs[itinerary.legs.length - 1];
		if (firstLeg.mode === 'ODM') {
			comparisons.push(
				...candidates.map(({ leg, index }) => ({
					itineraryIndex,
					edge: 'start' as const,
					odmLeg: firstLeg,
					comparedLeg: leg,
					comparedLegIndex: index,
					one: coordinates(firstLeg.from),
					many: coordinates(leg.to),
					arriveBy: false
				}))
			);
		}
		if (lastLeg.mode === 'ODM') {
			comparisons.push(
				...candidates.map(({ leg, index }) => ({
					itineraryIndex,
					edge: 'end' as const,
					odmLeg: lastLeg,
					comparedLeg: leg,
					comparedLegIndex: index,
					one: coordinates(lastLeg.to),
					many: coordinates(leg.from),
					arriveBy: true
				}))
			);
		}
	}

	const groups: RoutingGroup[] = [];
	for (const comparison of comparisons) {
		let group = groups.find(
			(candidate) =>
				candidate.arriveBy === comparison.arriveBy && isSamePlace(candidate.one, comparison.one)
		);
		if (group === undefined) {
			group = {
				one: comparison.one,
				arriveBy: comparison.arriveBy,
				targets: [],
				comparisons: []
			};
			groups.push(group);
		}
		let targetIndex = group.targets.findIndex((target) => isSamePlace(target, comparison.many));
		if (targetIndex === -1) {
			targetIndex = group.targets.length;
			group.targets.push(comparison.many);
		}
		group.comparisons.push({ ...comparison, targetIndex });
	}

	const results = await Promise.all(
		groups.map(async (group) => {
			const durations = await streetRouting(group.one, group.targets, group.arriveBy);
			return group.comparisons
				.map((comparison) => {
					const result = finding(
						comparison.edge,
						comparison.odmLeg,
						comparison.comparedLeg,
						comparison.comparedLegIndex,
						durations[comparison.targetIndex],
						tolerance
					);
					return result === undefined
						? undefined
						: { ...result, itineraryIndex: comparison.itineraryIndex };
				})
				.filter((result) => result !== undefined);
		})
	);
	return results.flat();
}

export async function findSuboptimalEdgeOdmConnections(
	itinerary: StreetCheckItinerary,
	tolerance: OdmStreetTolerance,
	streetRouting: StreetRouting = oneToManyCarRouting
): Promise<SuboptimalEdgeOdmConnection[]> {
	return (
		await findSuboptimalEdgeOdmConnectionsInItineraries([itinerary], tolerance, streetRouting)
	).map(({ itineraryIndex: _, ...result }) => result);
}
