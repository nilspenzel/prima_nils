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
	printInsertionEvaluation,
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
	startFixed: boolean,
	userChosenTime?: Date
) {
	//console.log("expandedSearchInterval",expandedSearchInterval);
	//console.log("userChosen",userChosen);
	//console.log("busStops",busStops);
	//console.log("userChosenTime",userChosenTime);
	if (companies.length == 0) {
		return busStops.map((bs) => bs.times.map((_) => undefined));
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
		busStops,
		startFixed
	);
	const busStopTimes = busStops.map((bs) =>
		bs.times.map(
			(t) =>
				new Interval(
					startFixed
						? new Date(t)
						: new Date(new Date(t).getTime() - MAX_PASSENGER_WAITING_TIME_PICKUP),
					startFixed
						? new Date(new Date(t).getTime() + MAX_PASSENGER_WAITING_TIME_DROPOFF)
						: new Date(t)
				)
		)
	);
	const newTourEvaluations = evaluateNewTours(
		companies,
		required,
		startFixed,
		expandedSearchInterval,
		busStopTimes,
		routingResults,
		travelDurations,
		userChosenTime
	);
	const { busStopEvaluations, bothEvaluations, userChosenEvaluations } = evaluateSingleInsertions(
		companies,
		startFixed,
		expandedSearchInterval,
		insertionRanges,
		busStopTimes,
		routingResults,
		travelDurations,
		userChosenTime
	);
	//console.log("busStopEvaluations",busStopEvaluations[0][0]);
	//console.log("userChosenEvaluations",userChosenEvaluations);
	const pairEvaluations = evaluatePairInsertions(
		companies,
		startFixed,
		insertionRanges,
		busStopTimes,
		busStopEvaluations,
		userChosenEvaluations
	);
	//console.log("NEWTOUR: ", newTourEvaluations.map((t) => t.map((e) => e == undefined ? "undefined" : printInsertionEvaluation(e!)))[0][0]);
	//console.log("SINGLE: ", bothEvaluations.map((t) => t.map((e) => e == undefined ? "undefined" : printInsertionEvaluation(e!)))[0][0]);
	//console.log("PAIR: ", pairEvaluations.map((t) => t.map((e) => e == undefined ? "undefined" : printInsertionEvaluation(e!)))[0][0]);
	const best = takeBest(takeBest(bothEvaluations, newTourEvaluations), pairEvaluations);
	return best;
}
