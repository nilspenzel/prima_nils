import type { Itinerary } from '$lib/openapi';
import type { Location } from '$lib/map/Location';
import type { SignedPlanResponse } from '$lib/planAndSign';

export const updateStartDest = (from: Location, to: Location) => {
	return (r: { data: SignedPlanResponse | undefined }) => {
		if (!r.data) {
			return r.data;
		}

		r.data.itineraries.forEach((it: Itinerary) => {
			if (it.legs[0].from.name === 'START') {
				it.legs[0].from.name = from.label!;
			}
			if (it.legs[it.legs.length - 1].to.name === 'END') {
				it.legs[it.legs.length - 1].to.name = to.label!;
			}
		});

		return r.data;
	};
};
