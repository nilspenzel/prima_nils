import { batchOneToManyCarRouting } from '$lib/server/util/batchOneToManyCarRouting';
import { Interval } from '$lib/util/interval';
import type { Coordinates } from '$lib/util/Coordinates';
import type { BusStop } from './BusStop';
import type { Capacities } from '$lib/util/booking/Capacities';
import { getPossibleInsertions } from '$lib/util/booking/getPossibleInsertions';
import type { Company } from './getBookingAvailability';
import type { PromisedTimes } from './PromisedTimes';
import type { Range } from '$lib/util/booking/getPossibleInsertions';
import {
	BUFFER_TIME,
	EARLIEST_SHIFT_START,
	LATEST_SHIFT_END,
	MAX_PASSENGER_WAITING_TIME_DROPOFF,
	MAX_PASSENGER_WAITING_TIME_PICKUP,
	PASSENGER_CHANGE_DURATION,
	SCHEDULED_TIME_BUFFER
} from '$lib/constants';
import {
	evaluateNewTours,
	evaluatePairInsertions,
	evaluateSingleInsertions,
	takeBest,
	type Insertion
} from './insertion';
import { getAllowedTimes } from '$lib/util/getAllowedTimes';
import { DAY } from '$lib/util/time';
import type { DebugInfo } from '../util/debugInfo';
import { routing } from './routing';

export type Times = {
	communicatedPickupTime: number;
	scheduledPickupTimeStart: number;
	scheduledPickupTimeEnd: number;
	communicatedDropoffTime: number;
	scheduledDropoffTimeStart: number;
	scheduledDropoffTimeEnd: number;
};

export async function evaluateRequest(
	companies: Company[],
	expandedSearchInterval: Interval,
	userChosen: Coordinates,
	busStops: BusStop[],
	required: Capacities,
	startFixed: boolean,
	promisedTimes?: PromisedTimes,
	debugInfo?: DebugInfo
): Promise<((Insertion & Times) | undefined)[][]> {
	if (companies.length == 0) {
		return busStops.map((bs) => bs.times.map((_) => undefined));
	}
	const directDurations = (await batchOneToManyCarRouting(userChosen, busStops, startFixed)).map(
		(duration) =>
			duration === undefined ? undefined : duration + PASSENGER_CHANGE_DURATION + BUFFER_TIME
	);
	const insertionRanges = new Map<number, Range[]>();
	companies.forEach((company) =>
		company.vehicles.forEach((vehicle) => {
			insertionRanges.set(vehicle.id, getPossibleInsertions(vehicle, required, vehicle.events));
		})
	);
	const routingResults = await routing(
		companies,
		userChosen,
		busStops,
		insertionRanges
	);
	const busStopTimes = busStops.map((bs) =>
		bs.times.map(
			(t) =>
				new Interval(
					startFixed ? t : t - MAX_PASSENGER_WAITING_TIME_PICKUP,
					startFixed ? t + MAX_PASSENGER_WAITING_TIME_DROPOFF : t
				)
		)
	);
	// Find the smallest Interval containing all availabilities and tours of the companies received as a parameter.
	let earliest = Number.MAX_VALUE;
	let latest = 0;
	companies.forEach((c) =>
		c.vehicles.forEach((v) => {
			v.availabilities.forEach((a) => {
				if (a.startTime < earliest) {
					earliest = a.startTime;
				}
				if (a.endTime > latest) {
					latest = a.endTime;
				}
			});
			v.tours.forEach((t) => {
				if (t.departure < earliest) {
					earliest = t.departure;
				}
				if (t.arrival > latest) {
					latest = t.arrival;
				}
			});
		})
	);
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
	const newTourEvaluations = evaluateNewTours(
		companies,
		required,
		startFixed,
		expandedSearchInterval,
		busStopTimes,
		routingResults,
		directDurations,
		allowedTimes,
		promisedTimes,
		debugInfo
	);
	const { busStopEvaluations, bothEvaluations, userChosenEvaluations } = evaluateSingleInsertions(
		companies,
		startFixed,
		expandedSearchInterval,
		insertionRanges,
		busStopTimes,
		routingResults,
		directDurations,
		allowedTimes,
		promisedTimes,
		debugInfo
	);
	const pairEvaluations = evaluatePairInsertions(
		companies,
		startFixed,
		insertionRanges,
		busStopTimes,
		busStopEvaluations,
		userChosenEvaluations
	);
	const best = takeBest(takeBest(bothEvaluations, newTourEvaluations), pairEvaluations);
	return best.map((b) =>
		b.map((b2) => {
			return b2
				? {
						...b2,
						communicatedPickupTime: b2.pickupTime - SCHEDULED_TIME_BUFFER,
						scheduledPickupTimeStart: b2.pickupTime - SCHEDULED_TIME_BUFFER,
						scheduledPickupTimeEnd: b2.pickupTime,
						communicatedDropoffTime: b2.dropoffTime + SCHEDULED_TIME_BUFFER,
						scheduledDropoffTimeStart: b2.dropoffTime,
						scheduledDropoffTimeEnd: b2.dropoffTime + SCHEDULED_TIME_BUFFER
					}
				: undefined;
		})
	);
}
