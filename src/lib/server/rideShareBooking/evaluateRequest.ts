import { batchOneToManyCarRouting } from '$lib/server/util/batchOneToManyCarRouting';
import { Interval } from '$lib/util/interval';
import type { Coordinates } from '$lib/util/Coordinates';
import type { Capacities } from '$lib/util/booking/Capacities';
import { getPossibleInsertions } from '$lib/util/booking/getPossibleInsertions';
import type { PromisedTimes } from './PromisedTimes';
import type { Range } from '$lib/util/booking/getPossibleInsertions';
import {
	EARLIEST_SHIFT_START,
	LATEST_SHIFT_END,
	MAX_PASSENGER_WAITING_TIME_DROPOFF,
	MAX_PASSENGER_WAITING_TIME_PICKUP,
	PASSENGER_CHANGE_DURATION
} from '$lib/constants';
import {
	evaluatePairInsertions,
	evaluateSingleInsertions,
	takeBest,
	type Insertion
} from './insertion';
import { getAllowedTimes } from '$lib/util/getAllowedTimes';
import { DAY, HOUR } from '$lib/util/time';
import { routing } from './routing';
import type { RideShareTour } from './getBookingAvailability';
import type { BusStop } from '../booking/BusStop';

export async function evaluateRequest(
	rideShareTours: RideShareTour[],
	expandedSearchInterval: Interval,
	userChosen: Coordinates,
	busStops: BusStop[],
	required: Capacities,
	startFixed: boolean,
	promisedTimes?: PromisedTimes
): Promise<(Insertion | undefined)[][]> {
	console.log(
		'EVALUATE REQUEST PARAMS: ',
		{ companies: JSON.stringify(rideShareTours, null, 2) },
		{ expandedSearchInterval: expandedSearchInterval.toString() },
		{ userChosen },
		{ busStops: JSON.stringify(busStops, null, 2) },
		{ required },
		{ startFixed },
		{ promisedTimes }
	);
	if (rideShareTours.length == 0) {
		return busStops.map((bs) => bs.times.map((_) => undefined));
	}
	const directDurations = (await batchOneToManyCarRouting(userChosen, busStops, startFixed)).map(
		(duration) => (duration === undefined ? undefined : duration + PASSENGER_CHANGE_DURATION)
	);
	const insertionRanges = new Map<number, Range[]>();
	rideShareTours.forEach((tour) =>
		insertionRanges.set(tour.rideShareTour, getPossibleInsertions(tour, required, tour.events))
	);

	const routingResults = await routing(rideShareTours, userChosen, busStops, insertionRanges);

	const t1 = promisedTimes === undefined ? MAX_PASSENGER_WAITING_TIME_PICKUP + HOUR : HOUR;
	const t2 = promisedTimes === undefined ? MAX_PASSENGER_WAITING_TIME_DROPOFF + HOUR : HOUR;
	const busStopTimes = busStops.map((bs) =>
		bs.times.map((t) => new Interval(startFixed ? t : t - t1, startFixed ? t + t2 : t))
	);
	// Find the smallest Interval containing all availabilities and tours of the companies received as a parameter.
	let earliest = Number.MAX_VALUE;
	let latest = 0;
	rideShareTours.forEach((t) => {
		if (t.events[0].scheduledTimeStart < earliest) {
			earliest = t.events[0].scheduledTimeStart;
		}
		if (t.events[t.events.length - 1].scheduledTimeEnd > latest) {
			latest = t.events[t.events.length - 1].scheduledTimeStart;
		}
	});
	if (earliest >= latest) {
		return busStops.map((bs) => bs.times.map((_) => undefined));
	}
	earliest = Math.max(earliest, Date.now() - 2 * DAY);
	latest = Math.min(latest, Date.now() + 15 * DAY);
	const allowedTimes = getAllowedTimes(earliest, latest, EARLIEST_SHIFT_START, LATEST_SHIFT_END);
	console.log(
		'WHITELIST REQUEST: ALLOWED TIMES (RESTRICTION FROM 4 TO 23):\n',
		allowedTimes.map((i) => i.toString())
	);
	const { busStopEvaluations, bothEvaluations, userChosenEvaluations } = evaluateSingleInsertions(
		rideShareTours,
		required,
		startFixed,
		insertionRanges,
		busStopTimes,
		routingResults,
		directDurations,
		allowedTimes,
		promisedTimes
	);
	const pairEvaluations = evaluatePairInsertions(
		rideShareTours,
		startFixed,
		insertionRanges,
		busStopTimes,
		busStopEvaluations,
		userChosenEvaluations,
		required,
		promisedTimes === undefined
	);
	const best = takeBest(bothEvaluations, pairEvaluations);
	return best;
}
