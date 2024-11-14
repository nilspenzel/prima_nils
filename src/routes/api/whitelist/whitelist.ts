import type { Capacities } from '$lib/capacities';
import {
	MAX_PASSENGER_WAITING_TIME_DROPOFF,
	MAX_PASSENGER_WAITING_TIME_PICKUP,
	MAX_TRAVEL_MS
} from '$lib/constants';
import { Interval } from '$lib/interval';
import type { Coordinates } from '$lib/location';
import { capacitySimulation } from './capacitySimulation';
import { type Range } from './capacitySimulation';
import {
	evaluateNewTours,
	evaluatePairInsertions,
	evaluateSingleInsertions,
	takeBest
} from './insertions';
import { gatherRoutingCoordinates, routing } from './routing';
import { bookingApiQuery } from './query';
import { oneToMany } from '$lib/api';
import type { BusStop } from '$lib/busStop';
import type { Transaction } from 'kysely';
import type { Database } from '$lib/types';

export async function white(
	userChosen: Coordinates,
	busStops: BusStop[],
	required: Capacities,
	startFixed: boolean,
	trx: Transaction<Database> | null
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
	const busStopCoordinates = busStops.map((busStop) => busStop.coordinates);
	const companies = await bookingApiQuery(
		userChosen,
		required,
		searchInterval,
		busStopCoordinates,
		trx
	);

	const travelDurations = await oneToMany(userChosen, busStopCoordinates, startFixed);

	const insertionRanges = new Map<number, Range[]>();
	companies.forEach((company) =>
		company.vehicles.forEach((vehicle) => {
			insertionRanges.set(
				vehicle.id,
				capacitySimulation(vehicle.capacities, required, vehicle.events)
			);
		})
	);

	const routingResults = await routing(
		companies,
		gatherRoutingCoordinates(companies, insertionRanges),
		userChosen,
		busStops
	);

	const busStopTimes = busStops.map((bs) =>
		bs.times.map(
			(t) =>
				new Interval(
					startFixed ? t : new Date(t.getTime() - MAX_PASSENGER_WAITING_TIME_PICKUP),
					startFixed ? new Date(t.getTime() + MAX_PASSENGER_WAITING_TIME_DROPOFF) : t
				)
		)
	);
	const { busStopEvaluations, bothEvaluations, userChosenEvaluations } = evaluateSingleInsertions(
		companies,
		startFixed,
		expandedSearchInterval,
		insertionRanges,
		busStopTimes,
		routingResults,
		travelDurations
	);
	const newTourEvaluations = evaluateNewTours(
		companies,
		required,
		startFixed,
		expandedSearchInterval,
		busStopTimes,
		routingResults,
		travelDurations
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
	for(let i=0;i!=best.length;++i){
		for(let j=0;j!=best[i].length;++j){
			const ett = new Set<number>();
			companies.find((c) => c.id==best[i][j]?.company)!.vehicles.find((v) => v.id==best[i][j]?.vehicle)!.events.filter((e) => e.communicated<best[i][j]?.dropoffTime!&&e.communicated>best[i][j]?.pickupTime!)
			.forEach((e) => ett.add(e.tourId));
			best[i][j]!.mergeTourList=[...ett];
		}
	}
	return best;
}
