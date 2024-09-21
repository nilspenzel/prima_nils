import type { Company, Event } from '$lib/compositionTypes';
import { Interval } from '$lib/interval';
import { iterateAllInsertions, type InsertionRoutingResult, type RoutingResults } from './routing';
import type { Range } from './capacitySimulation';
import { hoursToMs, minutesToMs } from '$lib/time_utils';
import { MIN_PREP_MINUTES } from '$lib/constants';

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
};

export function computeTravelDurations(
	companies: Company[],
	possibleInsertionsByVehicle: Map<number, Range[]>,
	routingResults: RoutingResults,
	travelDurations: number[],
	startFixed: boolean,
	busStopTimes: Interval[][],
	busStopCompanies: boolean[][]
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
	for(let busStopIdx=0;busStopIdx!=busStopTimes.length;++busStopIdx){
		allInsertions.busStops[busStopIdx] = new Array<Interval[][]>(busStopTimes[busStopIdx].length);
		allInsertions.both[busStopIdx] = new Array<Interval[][]>(busStopTimes[busStopIdx].length);
		for(let timeIdx=0;timeIdx!=busStopTimes[busStopIdx].length;++timeIdx){
			allInsertions.busStops[busStopIdx][timeIdx] = new Array<Interval[]>();
			allInsertions.both[busStopIdx][timeIdx] = new Array<Interval[]>();
		}
	}
	const afterPrepTime = new Interval(new Date(Date.now() + minutesToMs(MIN_PREP_MINUTES)), new Date(Date.now() + hoursToMs(2400)));
	const dummyP = new Date();
	const dummyN = new Date();
	iterateAllInsertions(
		companies,
		possibleInsertionsByVehicle,
		(events, insertionIdx, companyPosInRoutingResult, prevEventPosInRoutingResult, nextEventPosInRoutingResult, vehicle) => {
			const prev: Event|undefined = insertionIdx==0?undefined:events[insertionIdx - 1];
			const next: Event|undefined = insertionIdx==events.length?undefined:events[insertionIdx];
			cases.forEach((type) => {
				if (prev !=undefined && next!=undefined && (prev.tourId == next.tourId) != (type == InsertionType.INSERT)) {
					return;
				}
				const returnsToCompany = type === InsertionType.CONNECT || type === InsertionType.APPEND;
				const comesFromCompany = type === InsertionType.CONNECT || type === InsertionType.PREPEND;

				const window = new Interval(
					prev!=undefined?(comesFromCompany ? prev.arrival : prev.communitcated):dummyP,
					next!=undefined?(returnsToCompany ? next.departure : next.communitcated):dummyN
				);
				const windows: Interval[] =
					type == InsertionType.INSERT
						? [window]
						: Interval.intersect(vehicle.availabilities, window.intersect(afterPrepTime));

				let prevPosInRoutingResult = comesFromCompany ? companyPosInRoutingResult : prevEventPosInRoutingResult!;
				let nextPosInRoutingResult = returnsToCompany ? companyPosInRoutingResult : nextEventPosInRoutingResult!;
				prevPosInRoutingResult=prevPosInRoutingResult==undefined?0:prevPosInRoutingResult;
				nextPosInRoutingResult=nextPosInRoutingResult==undefined?0:nextPosInRoutingResult;

				allInsertions.userChosen.push(restrictWindowsByDuration(
					windows,
					routingResults.userChosen.fromPrev[prevPosInRoutingResult].distance,
					routingResults.userChosen.toNext[nextPosInRoutingResult].distance
				));
				for (let busStopIdx = 0; busStopIdx != travelDurations.length; ++busStopIdx) {
					const busStopRoutingResult = routingResults.busStops[busStopIdx];
					const travelDuration = travelDurations[busStopIdx];
					const times = busStopTimes[busStopIdx];
					for (let timeIdx = 0; timeIdx != times.length; ++timeIdx) {
						const approachDuration =
							busStopRoutingResult.fromPrev[prevPosInRoutingResult].distance;
						const returnDuration =
							busStopRoutingResult.toNext[nextPosInRoutingResult].distance;
						allInsertions.busStops[busStopIdx][timeIdx].push(Interval.intersect(
							restrictWindowsByDuration(windows, approachDuration, returnDuration),
							times[timeIdx]
						));
						const approachDurationBoth = startFixed
							? busStopRoutingResult.toNext[prevPosInRoutingResult].distance
							: routingResults.userChosen.toNext[nextPosInRoutingResult].distance + travelDuration;
						const returnDurationBoth = startFixed
							? routingResults.userChosen.fromPrev[prevPosInRoutingResult].distance + travelDuration
							: busStopRoutingResult.fromPrev[nextPosInRoutingResult].distance;
						allInsertions.both[busStopIdx][timeIdx].push(Interval.intersect(
							restrictWindowsByDuration(windows, approachDurationBoth, returnDurationBoth),
							times[timeIdx]
						));
					}
				}
			});
		}
	);
	return allInsertions;
}
