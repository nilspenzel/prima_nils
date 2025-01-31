import type { Capacities } from '$lib/capacities';
import { MAX_TRAVEL_MS } from '$lib/constants';
import { Interval } from '$lib/interval';
import type { Coordinates } from '$lib/location';
import { bookingApiQuery } from '$lib/bookingAPI/query';
import type { BusStop } from '$lib/busStop';
import { evaluateRequest } from '$lib/bookingAPI/evaluateRequest';
import type { InsertionEvaluation } from '$lib/bookingAPI/insertions';
import { InsertHow, printInsertionType } from '$lib/bookingAPI/insertionTypes';

export async function whitelist(
	userChosen: Coordinates,
	busStops: BusStop[],
	required: Capacities,
	startFixed: boolean
) {
	if (busStops.length == 0) {
		return [];
	}
	console.log('WLS');
	let lastTime = new Date(0);
	let firstTime = new Date('5000-01-01T00:00:00.0Z');
	for (let busStopIdx = 0; busStopIdx != busStops.length; ++busStopIdx) {
		for (let timeIdx = 0; timeIdx != busStops[busStopIdx].times.length; ++timeIdx) {
			const time = new Date(busStops[busStopIdx].times[timeIdx]);
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

	const { companies, busStopPerm } = await bookingApiQuery(
		userChosen,
		required,
		searchInterval,
		busStops.map((busStop) => busStop.coordinates),
		null
	);

	const validBusStops = new Array<BusStop>();
	for (let i = 0; i != busStopPerm.length; ++i) {
		if (busStopPerm[i] != undefined) {
			validBusStops.push(busStops[i]);
		}
	}
	const bestEvals = await evaluateRequest(
		companies,
		expandedSearchInterval,
		userChosen,
		validBusStops,
		required,
		startFixed,
		undefined
	);
	const ret: (InsertionEvaluation | undefined)[][] = new Array<(InsertionEvaluation | undefined)[]>(
		busStopPerm.length
	);
	for (let i = 0; i != busStopPerm.length; ++i) {
		if (busStopPerm[i] == undefined) {
			ret[i] = new Array<undefined>(busStops[i].times.length);
		} else {
			ret[i] = bestEvals[busStopPerm[i]!];
		}
	}
	console.log('WLE');
	return ret;
}

export function printMsg(b: InsertionEvaluation | undefined) {
	if (b == undefined) {
		console.log('    not possible');
		return;
	}
	if (b.pickupIdx == undefined) {
		console.assert(b.dropoffIdx == undefined, 'dropoffIdx==undefined unexpectedly');
		console.assert(
			b.pickupCase.how == b.dropoffCase.how && b.pickupCase.how == InsertHow.NEW_TOUR,
			"undefined pickupIdx doesn't yield NEW_TOUR"
		);
		console.log('    accepted as new tour');
		return;
	}
	console.assert(
		b.pickupIdx != undefined &&
			b.dropoffIdx != undefined &&
			b.pickupCase.how != InsertHow.NEW_TOUR &&
			b.dropoffCase.how != InsertHow.NEW_TOUR,
		'defined pickupIdx has unexpected behaviour'
	);
	if (b.pickupIdx == b.dropoffIdx) {
		console.log(
			'    inserted at same position as: ',
			printInsertionType(b.pickupCase),
			'   idx: ',
			b.pickupIdx
		);
		return;
	}
}
