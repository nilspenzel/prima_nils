import type { Company, Event } from '$lib/compositionTypes';
import { Interval } from '$lib/interval';
import { gatherRoutingCoordinates, iterateAllInsertions, routing, type RoutingResults } from './routing';
import { capacitySimulation, type Range } from './capacitySimulation';
import { hoursToMs, minutesToMs } from '$lib/time_utils';
import { MAX_PASSENGER_WAITING_TIME_DROPOFF, MAX_PASSENGER_WAITING_TIME_PICKUP, MIN_PREP_MINUTES, PASSENGER_COST_FACTOR, TAXI_COST_FACTOR } from '$lib/constants';
import type { BusStop } from '$lib/busStop';
import type { Capacities } from '$lib/capacities';
import type { Coordinates } from '$lib/location';

enum InsertionType {
	CONNECT,
	APPEND,
	PREPEND,
	INSERT
}

const cases = [
	InsertionType.CONNECT,
	InsertionType.APPEND,
	InsertionType.PREPEND,
	InsertionType.INSERT
];

type Insertions = {
	userChosen: Interval[][];
	busStops: Interval[][][][];
	both: Interval[][][][];
	approachDurations: (number|undefined)[];
	returnDurations: (number|undefined)[];
};

type Answer = {
		arrivals: Interval,
		passengerCost: number,
		taxiCost: number,
		cost: number
};

export function computeTravelDurations(
	companies: Company[],
	possibleInsertionsByVehicle: Map<number, Range[]>,
	routingResults: RoutingResults,
	travelDurations: number[],
	startFixed: boolean,
	busStopTimes: Interval[][]
): Insertions {
	const restrictWindowsByDuration = (
		windows: Interval[],
		approachDuration: number,
		returnDuration: number
	): Interval[] => {
		return windows
			.filter((window) => window.getDurationMs() >= approachDuration + returnDuration)
			.map((window) => window.shrink(approachDuration, returnDuration));
	};
	const allInsertions: Insertions = {
		userChosen: new Array<Interval[]>(),
		busStops: new Array<Interval[][][]>(busStopTimes.length),
		both: new Array<Interval[][][]>(busStopTimes.length)
	};
	for (let busStopIdx = 0; busStopIdx != busStopTimes.length; ++busStopIdx) {
		allInsertions.busStops[busStopIdx] = new Array<Interval[][]>(busStopTimes[busStopIdx].length);
		allInsertions.both[busStopIdx] = new Array<Interval[][]>(busStopTimes[busStopIdx].length);
		for (let timeIdx = 0; timeIdx != busStopTimes[busStopIdx].length; ++timeIdx) {
			allInsertions.busStops[busStopIdx][timeIdx] = new Array<Interval[]>();
			allInsertions.both[busStopIdx][timeIdx] = new Array<Interval[]>();
		}
	}
	const afterPrepTime = new Interval(
		new Date(Date.now() + minutesToMs(MIN_PREP_MINUTES)),
		new Date(Date.now() + hoursToMs(2400))
	);
	const dummyP = new Date();
	const dummyN = new Date();
	iterateAllInsertions(
		companies,
		possibleInsertionsByVehicle,
		(
			events,
			insertionIdx,
			companyPosInRoutingResult,
			prevEventPosInRoutingResult,
			nextEventPosInRoutingResult,
			vehicle
		) => {
			const prev: Event | undefined = insertionIdx == 0 ? undefined : events[insertionIdx - 1];
			const next: Event | undefined =
				insertionIdx == events.length ? undefined : events[insertionIdx];
			cases.forEach((type) => {
				if (
					prev != undefined &&
					next != undefined &&
					(prev.tourId == next.tourId) != (type == InsertionType.INSERT)
				) {
					return;
				}
				const returnsToCompany = type === InsertionType.CONNECT || type === InsertionType.APPEND;
				const comesFromCompany = type === InsertionType.CONNECT || type === InsertionType.PREPEND;

				const window = new Interval(
					prev != undefined ? (comesFromCompany ? prev.arrival : prev.communitcated) : dummyP,
					next != undefined ? (returnsToCompany ? next.departure : next.communitcated) : dummyN
				);
				const windows: Interval[] =
					type == InsertionType.INSERT
						? [window]
						: Interval.intersect(vehicle.availabilities, window.intersect(afterPrepTime));

				let prevPosInRoutingResult = comesFromCompany
					? companyPosInRoutingResult
					: prevEventPosInRoutingResult!;
				let nextPosInRoutingResult = returnsToCompany
					? companyPosInRoutingResult
					: nextEventPosInRoutingResult!;
				prevPosInRoutingResult = prevPosInRoutingResult == undefined ? 0 : prevPosInRoutingResult;
				nextPosInRoutingResult = nextPosInRoutingResult == undefined ? 0 : nextPosInRoutingResult;

				allInsertions.userChosen.push(
					restrictWindowsByDuration(
						windows,
						routingResults.userChosen.fromPrev[prevPosInRoutingResult].distance,
						routingResults.userChosen.toNext[nextPosInRoutingResult].distance
					)
				);
				for (let busStopIdx = 0; busStopIdx != travelDurations.length; ++busStopIdx) {
					const busStopRoutingResult = routingResults.busStops[busStopIdx];
					const travelDuration = travelDurations[busStopIdx];
					const times = busStopTimes[busStopIdx];
					for (let timeIdx = 0; timeIdx != times.length; ++timeIdx) {
						const approachDuration = busStopRoutingResult.fromPrev[prevPosInRoutingResult].distance;
						const returnDuration = busStopRoutingResult.toNext[nextPosInRoutingResult].distance;
						allInsertions.busStops[busStopIdx][timeIdx].push(
							Interval.intersect(
								restrictWindowsByDuration(windows, approachDuration, returnDuration),
								times[timeIdx]
							)
						);
						const approachDurationBoth = startFixed
							? busStopRoutingResult.toNext[prevPosInRoutingResult].distance
							: routingResults.userChosen.toNext[nextPosInRoutingResult].distance + travelDuration;
						const returnDurationBoth = startFixed
							? routingResults.userChosen.fromPrev[prevPosInRoutingResult].distance + travelDuration
							: busStopRoutingResult.fromPrev[nextPosInRoutingResult].distance;
						allInsertions.both[busStopIdx][timeIdx].push(
							Interval.intersect(
								restrictWindowsByDuration(windows, approachDurationBoth, returnDurationBoth),
								times[timeIdx]
							)
						);
					}
				}
			});
		}
	);
	return allInsertions;
}

const costFn = (passengerCost: number, taxiCost: number) => {
	return PASSENGER_COST_FACTOR * passengerCost + TAXI_COST_FACTOR * taxiCost;
}

const combine = (existing: Answer[], toAdd: Answer[]): Answer[] => {
	if(toAdd.length==0){
		return existing;
	}
	const cost = toAdd[0].cost;
	console.assert(toAdd.forEach((a) => a.cost==cost));
	const ret = existing.filter((e)=>e.cost<cost);
	toAdd = subtract(toAdd, ret);
	ret.concat(subtract(existing.filter((e) => e.cost > cost), toAdd));
	ret.concat(merge(existing.filter((e)=>e.cost==cost), toAdd));
	return ret;
}

const subtract = (base: Answer[], subtractor: Answer[]):Answer[] => {
	console.assert(subtractor.forEach((a,idx) => idx==0 || subtractor[idx-1].arrivals.startTime.getTime() <= a.arrivals.startTime.getTime()));
	base.sort((a1, a2) => a1.arrivals.startTime.getTime() - a2.arrivals.startTime.getTime());
	let basePos=0;
	let subtractorPos=0;
	const ret: Answer[] = [];
	let currentBase = base[basePos];
	let currentSubtractor = subtractor[subtractorPos];
	while(basePos!=base.length&&subtractorPos!=subtractor.length){
		if(currentBase.arrivals.startTime >= currentSubtractor.arrivals.endTime){
			subtractorPos++;
			currentSubtractor = subtractor[subtractorPos];
			continue;
		}
		if(currentBase.arrivals.endTime <= currentSubtractor.arrivals.startTime){
			ret.push(currentBase);
			basePos++;
			currentBase = base[basePos];
			continue;
		}
		if(currentSubtractor.arrivals.contains(currentBase.arrivals)){
			basePos++;
			currentBase = base[basePos];
			continue;
		}
		if(currentBase.arrivals.contains(currentSubtractor.arrivals)){
			const splitResult = currentBase.arrivals.split(currentSubtractor.arrivals);
			ret.push({arrivals: splitResult[0], cost: currentBase.cost, passengerCost: currentBase.passengerCost, taxiCost:currentBase.taxiCost});
			currentBase = {arrivals: splitResult[1], cost: currentBase.cost, passengerCost: currentBase.passengerCost, taxiCost:currentBase.taxiCost};
			subtractorPos++;
			currentSubtractor = subtractor[subtractorPos];
			continue;
		}
		const cutResult = {arrivals: currentBase.arrivals.cut(currentSubtractor.arrivals), cost: currentBase.cost, passengerCost: currentBase.passengerCost, taxiCost:currentBase.taxiCost};
		if(cutResult.arrivals.endTime<currentSubtractor.arrivals.startTime){
			ret.push(cutResult);
			basePos++;
			currentBase=base[basePos];
			continue;
		}
		currentBase = cutResult;
		subtractorPos++;
		currentSubtractor=subtractor[subtractorPos];
	}
	return ret;
}

const createInsertionPairs = (
	companies: Company[],
	startFixed: boolean,
	possibleInsertionsByVehicle: Map<number, Range[]>,
	busStops: BusStop[],
	insertionIntervals: Insertions[]
): Answer[][] => {
	const best = new Array<Answer[]>(busStops.length);
	let pos = 0;
	for(let insertionIdx=0;insertionIdx!=insertionIntervals[0].both.length;++insertionIdx){
		for(let busStopIdx=0;busStopIdx!=busStops.length;++busStopIdx){
			cases.forEach((type) => {
				const insertions = insertionIntervals[pos];
				if(insertions.approachDurations[type]==undefined){
					return;
				}
				const passengerCost = insertions.approachDurations[type]! + insertions.returnDurations[type]!;
				const taxiCost=0;//TODO
				const cost = costFn(passengerCost, taxiCost);
				if(best[busStopIdx] == undefined){
					best[busStopIdx] = insertions.both[busStopIdx][0][0].map((i)=>{return{
						arrivals: i, passengerCost, taxiCost, cost
					}});
					return;
				}
				best[busStopIdx] = combine(best[busStopIdx], insertions.both[busStopIdx][0][0].map((i) => {return{arrivals:i,cost,taxiCost,passengerCost};}));
			});
		}
	}
	pos=0;
	companies.forEach((company) => {
		company.vehicles.forEach((vehicle)=>{
			const events = vehicle.tours.flatMap((t)=> t.events);
			const insertionRanges = possibleInsertionsByVehicle.get(vehicle.id)!;
			insertionRanges.forEach((range) => {
				for(let pickup=range.earliestPickup;pickup!=range.latestDropoff;++pickup){
					for(let dropoff=pickup+1;dropoff!=range.latestDropoff+1;++dropoff){
						for(let busStopIdx=0;busStopIdx!=busStops.length;++busStopIdx){
							const insertions = insertionIntervals[pos];
							
						}
					}
					pos++;
				}
			})
		})
	});
	return best;
};

export async function doStuff(
	companies: Company[],
	required: Capacities,
	busStops: BusStop[],
	userChosen: Coordinates,
	travelDurations: number[],
	startFixed: boolean
): Promise<Answer[][]> {
	const insertions = new Map<number, Range[]>();
	companies.forEach((c) => {
		c.vehicles.forEach((v) => {
			insertions.set(
				v.id,
				capacitySimulation(
					v.capacities,
					required,
					v.tours.flatMap((t) => t.events)
				)
			);
		});
	});

	const routingResults = await routing(
		gatherRoutingCoordinates(companies, busStops, insertions),
		userChosen,
		busStops
	);

	const insertionss = computeTravelDurations(
		companies,
		insertions,
		routingResults,
		travelDurations,
		startFixed,
		busStops.map((bs) =>
			bs.times.map(
				(t) =>
					new Interval(
						startFixed ? t : new Date(t.getTime() - MAX_PASSENGER_WAITING_TIME_PICKUP),
						startFixed ? new Date(t.getTime() + MAX_PASSENGER_WAITING_TIME_DROPOFF) : t
					)
			)
		)
	);

	return createInsertionPairs(companies, startFixed, insertions, busStops, insertionss);
}
