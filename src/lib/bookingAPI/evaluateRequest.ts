import type { Capacities } from '$lib/capacities';
import {
	MAX_PASSENGER_WAITING_TIME_DROPOFF,
	MAX_PASSENGER_WAITING_TIME_PICKUP
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
import { oneToMany } from '$lib/api';
import type { BusStop } from '$lib/busStop';
import type { Company } from '$lib/compositionTypes';

export async function evaluateRequest(
	companies: Company[],
	expandedSearchInterval: Interval,
	userChosen: Coordinates,
	busStops: BusStop[],
	required: Capacities,
	startFixed: boolean
) {
	if(companies.length==0){
		return busStops.map((bs)=> bs.times.map((t)=>undefined));
	}
	const travelDurations = await oneToMany(
		userChosen,
		busStops.map((busStop) => busStop.coordinates),
		startFixed
	);

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
					startFixed ? new Date(t) : new Date(new Date(t).getTime() - MAX_PASSENGER_WAITING_TIME_PICKUP),
					startFixed ? new Date(new Date(t).getTime() + MAX_PASSENGER_WAITING_TIME_DROPOFF) : t
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
	return best;
}
