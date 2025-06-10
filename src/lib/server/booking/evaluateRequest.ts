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
	EARLIEST_SHIFT_START,
	LATEST_SHIFT_END,
	MAX_PASSENGER_WAITING_TIME_DROPOFF,
	MAX_PASSENGER_WAITING_TIME_PICKUP,
	PASSENGER_CHANGE_DURATION
} from '$lib/constants';
import {
	evaluateNewTours,
	evaluatePairInsertions,
	evaluateSingleInsertions,
	takeBest,
	type Insertion
} from './insertion';
import { getAllowedTimes } from '$lib/util/getAllowedTimes';
import { DAY, MINUTE } from '$lib/util/time';
import type { DebugInfo } from '../util/debugInfo';
import { routing } from './routing';
import { oneToManyCarRouting } from '../util/oneToManyCarRouting';

export async function evaluateRequest(
	companies: Company[],
	expandedSearchInterval: Interval,
	userChosen: Coordinates,
	busStops: BusStop[],
	required: Capacities,
	startFixed: boolean,
	promisedTimes?: PromisedTimes,
	debugInfo?: DebugInfo
): Promise<(Insertion | undefined)[][]> {
	if (companies.length == 0) {
		return busStops.map((bs) => bs.times.map((_) => undefined));
	}
	const directDurations = (await batchOneToManyCarRouting(userChosen, busStops, startFixed)).map(
		(duration) => (duration === undefined ? undefined : duration + PASSENGER_CHANGE_DURATION)
	);
	const insertionRanges = new Map<number, Range[]>();
	companies.forEach((company) =>
		company.vehicles.forEach((vehicle) => {
			insertionRanges.set(vehicle.id, getPossibleInsertions(vehicle, required, vehicle.events));
		})
	);

	const routingResults = await routing(companies, userChosen, busStops, insertionRanges);

	let insertionIdx = 0;
	//console.log(JSON.stringify(routingResults,null,2))
	console.log('stuffy1');
	for (const [companyIdx, company] of companies.entries()) {
		for (const [vIdx, vehicle] of company.vehicles.entries()) {
			for (const insertion of insertionRanges.get(vehicle.id)!) {
				for (
					let idxInEvents = insertion.earliestPickup;
					idxInEvents != insertion.latestDropoff + 1;
					++idxInEvents
				) {
					const info = {
						idxInVehicleEvents: idxInEvents,
						companyIdx,
						vIdx,
						vehicle,
						currentRange: insertion,
						insertionIdx
					};
					console.log(
						{ info: info.insertionIdx },
						info.idxInVehicleEvents,
						info.vIdx,
						info.companyIdx,
						info.idxInVehicleEvents,
						' eventId: ',
						vehicle.events[info.idxInVehicleEvents]?.lat,
						' prev: ',
						vehicle.events[info.idxInVehicleEvents - 1]?.lat
					);
					if (info.vehicle.events[info.idxInVehicleEvents]) {
						//const rr1= await oneToManyCarRouting(userChosen, [info.vehicle.events[info.idxInVehicleEvents]], false);
						//const rr2= await oneToManyCarRouting(info.vehicle.events[info.idxInVehicleEvents], [userChosen], true);
						//console.log("error in rrFrom: ", info.insertionIdx, {rr1: (rr1[0]??-MINUTE*2)+MINUTE}, {rr2: (rr2[0]??-MINUTE*2)+MINUTE}, {routingResult: routingResults.userChosen.fromUserChosen.event[info.insertionIdx]});
					}
					if (info.vehicle.events[info.idxInVehicleEvents - 1]) {
						//const rr1 = await oneToManyCarRouting(info.vehicle.events[info.idxInVehicleEvents-1], [userChosen], false);
						//const rr2 = await oneToManyCarRouting(userChosen, [info.vehicle.events[info.idxInVehicleEvents-1]], true);
						//console.log("error in rrTo: ", info.insertionIdx, {rr: (rr1[0]??-MINUTE*2)+MINUTE}, {rr: (rr2[0]??-MINUTE*2)+MINUTE}, {routingResult: routingResults.userChosen.toUserChosen.event[info.insertionIdx-1]});
					}
					insertionIdx++;
				}
			}
		}
	}
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
	//console.log('stuf0: ', JSON.stringify(routingResults, null, '\t'));
	//iterateAllInsertions(companies, insertionRanges, (insertionInfo, idx) => {
	//	for(let i=0;i!=busStops.length;++i) {
	//	console.log("idxInEvents: ", insertionInfo.idxInEvents, " companyFrombusStop: ", routingResults.busStops.fromBusStop[i].event[insertionInfo.idxInEvents], insertionInfo.vehicle.events[insertionInfo.idxInEvents]);
	//	console.log("companyFrombusStop: ", routingResults.busStops.fromBusStop[i].company[insertionInfo.companyIdx], companies[insertionInfo.companyIdx]);
	//	console.log("idxInEvents: ", insertionInfo.idxInEvents, " companyTobusStop: ", routingResults.busStops.toBusStop[i].event[insertionInfo.idxInEvents], insertionInfo.vehicle.events[insertionInfo.idxInEvents]);
	//	console.log("companyTobusStop: ", routingResults.busStops.toBusStop[i].company[insertionInfo.companyIdx], companies[insertionInfo.companyIdx]);
	//	}
	//	console.log("idxInEvents: ", insertionInfo.idxInEvents, " companyFromUserChosen: ", routingResults.userChosen.fromUserChosen.event[insertionInfo.idxInEvents], insertionInfo.vehicle.events[insertionInfo.idxInEvents]);
	//	console.log("companyFromUserChosen: ", routingResults.userChosen.fromUserChosen.company[insertionInfo.companyIdx], companies[insertionInfo.companyIdx]);
	//	console.log("idxInEvents: ", insertionInfo.idxInEvents, " companyToUserChosen: ", routingResults.userChosen.toUserChosen.event[insertionInfo.idxInEvents], insertionInfo.vehicle.events[insertionInfo.idxInEvents]);
	//	console.log("companyToUserChosen: ", routingResults.userChosen.toUserChosen.company[insertionInfo.companyIdx], companies[insertionInfo.companyIdx]);
	//})
	return best;
}
