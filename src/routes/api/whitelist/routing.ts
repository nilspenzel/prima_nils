import { Direction, oneToMany, type oneToManyResult } from '$lib/api';
import type { BusStop } from '$lib/busStop';
import type { Capacities } from '$lib/capacities';
import type { Company, Vehicle, Event } from '$lib/compositionTypes';
import { MAX_PASSENGER_WAITING_TIME } from '$lib/constants';
import { Interval } from '$lib/interval';
import type { Coordinates } from '$lib/location';
import { capacitySimulation } from './capacitySimulation';

enum Timing {
	BEFORE = 0,
	AFTER = 1
}

type Range = {
	earliestPickup: number;
	latestDropoff: number;
};

type RoutingCoordinates = {
	busStopMany: Coordinates[][];
	userChosenMany: Coordinates[];
};

type RoutingResults = {
	busStops: oneToManyResult[][][];
	userChosen: oneToManyResult[][];
};

function forEachInsertion<T>(insertions: Range[], fn: (insertionIdx: number) => T) {
	insertions.forEach((insertion) => {
		for (let i = insertion.earliestPickup; i != insertion.latestDropoff; ++i) {
			fn(i);
		}
	});
}

export function gatherRoutingCoordinates(
	companies: Company[],
	busStops: BusStop[],
	possibleInsertionsByVehicle: Map<number, Range[]>
): RoutingCoordinates {
	const busStopMany = new Array<Coordinates[]>(busStops.length);
	const userChosenMany = new Array<Coordinates>();
	companies.forEach((c) => {
		for (let busStopIdx = 0; busStopIdx != busStops.length; ++busStopIdx) {
			busStopMany[busStopIdx].push(c.coordinates);
		}
		userChosenMany.push(c.coordinates);
		c.vehicles.forEach((v) => {
			const allEvents = v.tours.flatMap((t) => t.events);
			const insertions = possibleInsertionsByVehicle.get(v.id)!;
			forEachInsertion(insertions, (insertionIdx) => {
				const eventCoordinates = allEvents[insertionIdx].coordinates;
				for (let busStopIdx = 0; busStopIdx != busStops.length; ++busStopIdx) {
					busStopMany[busStopIdx].push(eventCoordinates);
				}
				userChosenMany.push(eventCoordinates);
			});
		});
	});
	return {
		busStopMany,
		userChosenMany
	};
}

function iterateAllInsertions(
	companies: Company[],
	insertions: Map<number, Range[]>,
	companyFn: (c: Company) => void,
	vehicleFn: (v: Vehicle) => void,
	insertionFn: (events: Event[], insertionIdx: number) => void
) {
	companies.forEach((c) => {
		companyFn(c);
		c.vehicles.forEach((v) => {
			vehicleFn(v);
			const events = v.tours.flatMap((t) => t.events);
			forEachInsertion(insertions.get(v.id)!, (insertionIdx) => {
				insertionFn(events, insertionIdx);
			});
		});
	});
}

export async function routing(
	coordinates: RoutingCoordinates,
	userChosen: Coordinates,
	busStops: BusStop[]
): Promise<RoutingResults> {
	const ret = {
		userChosen: new Array<oneToManyResult[]>(coordinates.userChosenMany.length),
		busStops: new Array<oneToManyResult[][]>(coordinates.userChosenMany.length)
	};
	ret.userChosen[Timing.BEFORE] = await oneToMany(
		userChosen,
		coordinates.userChosenMany,
		Direction.Backward
	);
	ret.userChosen[Timing.AFTER] = await oneToMany(
		userChosen,
		coordinates.userChosenMany,
		Direction.Forward
	);
	for (let busStopIdx = 0; busStopIdx != busStops.length; ++busStopIdx) {
		const busStop = busStops[busStopIdx];
		const busStopMany = coordinates.busStopMany[busStopIdx];
		ret.busStops[Timing.BEFORE][busStopIdx] = await oneToMany(
			busStop.coordinates,
			busStopMany,
			Direction.Backward
		);
		ret.busStops[Timing.AFTER][busStopIdx] = await oneToMany(
			busStop.coordinates,
			busStopMany,
			Direction.Forward
		);
	}
	return ret;
}

enum InsertionType {
	CONNECT,
	APPEND,
	PREPEND,
	INSERT
}

type Insertions = {
	userChosen: Interval[][];
	busStops: Interval[][][][];
	both: Interval[][][][];
};

function computeTravelDurations(
	companies: Company[],
	possibleInsertionsByVehicle: Map<number, Range[]>,
	routingResults: RoutingResults,
	travelDurations: number[],
	startFixed: boolean,
	busStopTimes: Interval[][]
) {
	const restrictWindowsByDuration = (windows: Interval[],
		approachDuration: number,
		returnDuration: number,
		): Interval[] => {
			return windows
			.filter((a) => a.getDurationMs() >= approachDuration + returnDuration)
			.map(
				(a) =>
					new Interval(
						new Date(a.startTime.getTime() + approachDuration),
						new Date(a.endTime.getTime() - returnDuration)
					)
			);
		}
	const cases = [
		InsertionType.CONNECT,
		InsertionType.APPEND,
		InsertionType.PREPEND,
		InsertionType.INSERT
	];
	const allInsertions: Insertions = {
		userChosen: new Array<Interval[]>(),
		busStops: new Array<Interval[][][]>(),
		both: new Array<Interval[][][]>()
	};
	let eventPos = 0;
	let busStopPos = 0;
	let companyPos = 0;
	companies.forEach((c) => {
		++eventPos;
		c.vehicles.forEach((v) => {
			const allEvents = v.tours.flatMap((t) => t.events);
			const insertions = possibleInsertionsByVehicle.get(v.id)!;
			forEachInsertion(insertions, (insertionIdx) => {
				const prev = allEvents[insertionIdx - 1];
				const next = allEvents[insertionIdx];
				const departure = v.tours.find((t) => t.id == next.tourId)!.departure;
				const arrival = v.tours.find((t) => t.id == prev.tourId)!.arrival;
				cases.forEach((type) => {
					busStopPos = eventPos;
					if ((prev.tourId == next.tourId) != (type == InsertionType.INSERT)) {
						return;
					}
					const isAppend = type === InsertionType.CONNECT || type === InsertionType.APPEND;
					const isPrepend = type === InsertionType.CONNECT || type === InsertionType.PREPEND;
					const window = new Interval(
						isAppend ? arrival : prev.time.startTime,
						isPrepend ? departure : next.time.endTime
					);
					const windows: Interval[] =
						type == InsertionType.INSERT ? [window] : Interval.intersect(v.availabilities, window);
					const prevPos = isAppend ? companyPos : eventPos;
					const nextPos = isPrepend ? companyPos : eventPos;
					allInsertions.userChosen[eventPos] = restrictWindowsByDuration(windows, routingResults.userChosen[Timing.BEFORE][prevPos].distance, routingResults.userChosen[Timing.AFTER][nextPos].distance);
					for (let busStopIdx = 0; busStopIdx != travelDurations.length; ++busStopIdx) {
						++busStopPos;
						const prevBusStopPos = isAppend ? companyPos : busStopPos;
						const nextBusStopPos = isPrepend ? companyPos : busStopPos;
						for (let busStopTimeIdx = 0; busStopTimeIdx != busStopTimes[busStopIdx].length; ++busStopTimeIdx) {
							allInsertions.busStops[eventPos][busStopIdx][busStopTimeIdx] = Interval.intersect(restrictWindowsByDuration(
								windows,
								routingResults.busStops[Timing.BEFORE][busStopIdx][prevBusStopPos].distance,
								routingResults.busStops[Timing.AFTER][busStopIdx][nextBusStopPos].distance),
								busStopTimes[busStopIdx][busStopTimeIdx]
							);
							allInsertions.both[eventPos][busStopIdx][busStopTimeIdx] = Interval.intersect(restrictWindowsByDuration(
								windows,
								startFixed
									? routingResults.busStops[Timing.BEFORE][busStopIdx][prevBusStopPos].distance
									: routingResults.userChosen[Timing.BEFORE][nextBusStopPos].distance +
											travelDurations[busStopIdx],
								startFixed
									? routingResults.userChosen[Timing.AFTER][prevPos].distance + travelDurations[busStopIdx]
									: routingResults.busStops[Timing.AFTER][busStopIdx][nextBusStopPos].distance),
								busStopTimes[busStopIdx][busStopTimeIdx]
							);
						}
					}
				});
				++eventPos;
			});
		});
		companyPos = eventPos;
	});
}

export async function doStuff(
	companies: Company[],
	required: Capacities,
	busStops: BusStop[],
	userChosen: Coordinates,
	travelDurations: number[],
	startFixed: boolean
): Promise<Answer[]> {
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

	const routingResults = await routing(gatherRoutingCoordinates(companies, busStops, insertions), userChosen, busStops);

	computeTravelDurations(
		companies,
		insertions,
		routingResults,
		travelDurations,
		startFixed,
		busStops.map((bs) =>
			bs.times.map(
				(t) =>
					new Interval(
						startFixed ? t : new Date(t.getTime() - MAX_PASSENGER_WAITING_TIME),
						startFixed ? new Date(t.getTime() + MAX_PASSENGER_WAITING_TIME) : t
					)
			)
		)
	);

	return createInsertionPairs(companies, insertions, busStops);
}

type Answer = {
	companyId: number;
	vehicleId: number;
	pickupAfterEventId: number | undefined;
	dropoffAfterEventId: number | undefined;
	type: InsertionType;
	windowsAtBusStop: Interval[];
	busStopIdx: number;
};

const createInsertionPairs = (companies: Company[], insertions: Map<number, Range[]>, busStops: BusStop[]): Answer[] => {
	const answers = new Array<Answer>();
companies.forEach((c, companyIdx) => {
	c.vehicles.forEach((v, vehicleIdx) => {
		const allEvents = v.tours.flatMap((t) => t.events);
		insertions.get(v.id)!.forEach((insertion) => {
			for (
				let pickupIdx = insertion.earliestPickup;
				pickupIdx != insertion.latestDropoff;
				++pickupIdx
			) {
				for (let dropoffIdx = pickupIdx; dropoffIdx != insertion.latestDropoff; ++dropoffIdx) {
					const prevPickup = allEvents[pickupIdx];
					const nextPickup = allEvents[pickupIdx + 1];
					const prevDropoff = allEvents[dropoffIdx];
					const nextDropoff = allEvents[dropoffIdx + 1];
					const pickupTimeDifference =
						nextPickup.time.startTime.getTime() - prevPickup.time.endTime.getTime();
					if (nextPickup.tourId != prevDropoff.tourId) {
						break;
					}
					if(prevPickup.tourId == nextDropoff.tourId) {
						if(prevPickup.id == prevDropoff.id) {
							busStops.forEach((_, busStopIdx) => {
								const duration =
									insertDurations[InsertionType.INSERT][companyIdx][vehicleIdx][pickupIdx].bothDurations[busStopIdx];		
								if (duration != undefined && duration <= pickupTimeDifference) {
									answers[busStopIdx].push({
										companyId: c.id,
										vehicleId: v.id,
										pickupAfterEventId: prevPickup.id,
										dropoffAfterEventId: prevDropoff.id,
										type: InsertionType.INSERT
									});
								}
							});
						}
						else{

						}
						continue;
					}
					if(prevPickup.tourId == nextPickup.tourId) {
						continue;
					}
					if(prevDropoff.tourId == nextDropoff.tourId) {
						continue;
					}

				}
			}
		});
	});
});
return answers;
}