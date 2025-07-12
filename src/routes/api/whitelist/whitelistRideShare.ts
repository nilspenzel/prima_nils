import type { Capacities } from '$lib/util/booking/Capacities';
import { getBookingAvailability } from '$lib/server/rideShareBooking/getBookingAvailability';
import { MAX_TRAVEL } from '$lib/constants';
import { Interval } from '$lib/util/interval';
import type { Coordinates } from '$lib/util/Coordinates';
import { evaluateRequest } from '$lib/server/rideShareBooking/evaluateRequest';
import { toBusStopWithISOStrings, type BusStop } from '$lib/server/booking/BusStop';
import { toInsertionWithISOStrings, type Insertion } from '$lib/server/rideShareBooking/insertion';

export async function whitelistRideShare(
	userChosen: Coordinates,
	busStops: BusStop[],
	required: Capacities,
	startFixed: boolean
): Promise<Array<(Insertion | undefined)[]>> {
	console.log(
		'Whitelist Request: ',
		JSON.stringify(
			{
				required,
				startFixed,
				userChosen,
				busStops: busStops.map((b) => toBusStopWithISOStrings(b))
			},
			null,
			'\t'
		)
	);

	if (!busStops.some((b) => b.times.length !== 0)) {
		return new Array<(Insertion | undefined)[]>(busStops.length);
	}

	let lastTime = 0;
	let firstTime = Number.MAX_VALUE;
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

	console.log('BUS STOPS', JSON.stringify(busStops));
	console.log(
		'INTERVAL',
		JSON.stringify({
			firstTime: new Date(firstTime).toISOString(),
			lastTime: new Date(lastTime).toISOString()
		})
	);

	const searchInterval = new Interval(firstTime, lastTime);
	const expandedSearchInterval = searchInterval.expand(MAX_TRAVEL * 6, MAX_TRAVEL * 6);

	const rideShareTours = await getBookingAvailability(
		userChosen,
		required,
		searchInterval,
		busStops
	);
	console.log(
		'Whitelist Request: getBookingAvailability results\n',
		JSON.stringify(
			{
				searchInterval: searchInterval.toString(),
				expandedSearchInterval: expandedSearchInterval.toString(),
				rideShareTours
			},
			null,
			'\t'
		)
	);
	const bestEvals = await evaluateRequest(
		rideShareTours,
		expandedSearchInterval,
		userChosen,
		busStops,
		required,
		startFixed
	);
	console.log(
		'WHITELIST RESULT: ',
		JSON.stringify(
			bestEvals.map((arr) => arr.map((i) => toInsertionWithISOStrings(i))),
			null,
			2
		)
	);
	console.log('WLE');
	return bestEvals;
}
