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
import type { PromisedTimes } from './promisedTimes';

export async function evaluateRequest(
	companies: Company[],
	expandedSearchInterval: Interval,
	userChosen: Coordinates,
	busStops: BusStop[],
	required: Capacities,
	startFixed: boolean,
	promisedTimes?: PromisedTimes
) {
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
		promisedTimes
	);
	const { busStopEvaluations, bothEvaluations, userChosenEvaluations } = evaluateSingleInsertions(
		companies,
		startFixed,
		expandedSearchInterval,
		insertionRanges,
		busStopTimes,
		routingResults,
		travelDurations,
		promisedTimes
	);
	//console.log(busStopEvaluations.map((m) => m.map((r) => r.map((k)=>k==undefined ? "undef":printInsertionType(k.case)))));
	//console.log("userc: ", userChosenEvaluations.map((m) => m==undefined ? "undef":printInsertionType(m.case)));
	const pairEvaluations = evaluatePairInsertions(
		companies,
		startFixed,
		insertionRanges,
		busStopTimes,
		busStopEvaluations,
		userChosenEvaluations
	);
	//console.log("Single");
	//console.log(bothEvaluations.map((c) => c.map((o)=>o==undefined?"undef":printInsertionType(o.pickupCase))));
	//console.log("Pair");
	//console.log(pairEvaluations.map((c) => c.map((o)=>o==undefined?"undef":""+printInsertionType(o.pickupCase)+"    "+printInsertionType(o.dropoffCase))));
	const best = takeBest(takeBest(bothEvaluations, newTourEvaluations), pairEvaluations);
	if (best[0][0]) {
		//console.log("BESTp: ", printInsertionType(best[0][0].pickupCase));
		//console.log("BESTd: ", printInsertionType(best[0][0].dropoffCase));
	}
	return best;
}
