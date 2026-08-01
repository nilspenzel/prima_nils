import { isSamePlace } from '$lib/util/booking/isSamePlace';

type LegTarget = {
	mode: string;
	to: {
		name: string;
		lat: number;
		lon: number;
	};
};

type ItineraryWithLegs = {
	legs: readonly LegTarget[];
};

export type RepeatedLegTarget = {
	firstLegIndex: number;
	repeatedLegIndex: number;
};

export type ItineraryCycle = RepeatedLegTarget & {
	itineraryIndex: number;
};

function isSameTarget(first: LegTarget['to'], second: LegTarget['to']) {
	return isSamePlace({ lat: first.lat, lng: first.lon }, { lat: second.lat, lng: second.lon });
}

export function findRepeatedLegTarget(legs: readonly LegTarget[]): RepeatedLegTarget | undefined {
	for (let repeatedLegIndex = 1; repeatedLegIndex < legs.length; repeatedLegIndex++) {
		if (legs[repeatedLegIndex].mode === 'WALK') {
			continue;
		}
		for (let firstLegIndex = 0; firstLegIndex < repeatedLegIndex; firstLegIndex++) {
			if (
				legs[firstLegIndex].mode !== 'WALK' &&
				isSameTarget(legs[firstLegIndex].to, legs[repeatedLegIndex].to)
			) {
				return { firstLegIndex, repeatedLegIndex };
			}
		}
	}
	return undefined;
}

export function findItineraryCycles(itineraries: readonly ItineraryWithLegs[]): ItineraryCycle[] {
	const cycles: ItineraryCycle[] = [];
	for (const [itineraryIndex, itinerary] of itineraries.entries()) {
		const repeatedTarget = findRepeatedLegTarget(itinerary.legs);
		if (repeatedTarget !== undefined) {
			cycles.push({ itineraryIndex, ...repeatedTarget });
		}
	}
	return cycles;
}

export function formatItineraryCycle(
	label: string,
	legs: readonly LegTarget[],
	cycle: RepeatedLegTarget
) {
	const firstLeg = legs[cycle.firstLegIndex];
	const repeatedLeg = legs[cycle.repeatedLegIndex];
	const target = repeatedLeg.to;
	return `Cycle detected in ${label}: leg #${cycle.firstLegIndex} (${firstLeg.mode}) and leg #${cycle.repeatedLegIndex} (${repeatedLeg.mode}) target ${target.name} (${target.lat}, ${target.lon}).`;
}
