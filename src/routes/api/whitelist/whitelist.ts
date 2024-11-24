import type { Capacities } from '$lib/capacities';
import { MAX_TRAVEL_MS } from '$lib/constants';
import { Interval } from '$lib/interval';
import type { Coordinates } from '$lib/location';
import { bookingApiQuery } from '$lib/bookingAPI/query';
import type { BusStop } from '$lib/busStop';
import { evaluateRequest } from '$lib/bookingAPI/evaluateRequest';

export async function whitelist(
	userChosen: Coordinates,
	busStops: BusStop[],
	required: Capacities,
	startFixed: boolean
) {
	if (busStops.length == 0) {
		return [];
	}
	let lastTime = new Date(0);
	let firstTime = new Date('5000-01-01T00:00:00.0Z');
	for (let busStopIdx = 0; busStopIdx != busStops.length; ++busStopIdx) {
		for (let timeIdx = 0; timeIdx != busStops[busStopIdx].times.length; ++timeIdx) {
			const time = busStops[busStopIdx].times[timeIdx];
			if (time < firstTime) {
				firstTime = time;
			}
			if (time > lastTime) {
				lastTime = time;
			}
		}
	}
	const searchInterval = new Interval(firstTime, lastTime);
	const expandedSearchInterval = searchInterval.expand(MAX_TRAVEL_MS * 6, MAX_TRAVEL_MS * 6);
	console.log("busstops",busStops);

	return await evaluateRequest(
		await bookingApiQuery(
			userChosen,
			required,
			searchInterval,
			busStops.map((busStop) => busStop.coordinates),
			null
		),
		expandedSearchInterval,
		userChosen,
		busStops,
		required,
		startFixed
	);
}
