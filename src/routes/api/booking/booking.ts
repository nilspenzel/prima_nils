import type { Capacities } from '$lib/capacities';
import { MAX_TRAVEL_MS } from '$lib/constants';
import { Interval } from '$lib/interval';
import type { Coordinates } from '$lib/location';
import { bookingApiQuery } from '../whitelist/query';
import type { Transaction } from 'kysely';
import type { Database } from '$lib/types';
import type { Event } from '$lib/compositionTypes';
import { v4 as uuidv4 } from 'uuid';
import { InsertHow } from '../whitelist/insertionTypes';
import type { ExpectedConnection } from '$lib/bookingApiParameters';
import { evaluateRequest } from '../whitelist/whitelist';

export async function booking(
	c: ExpectedConnection,
	required: Capacities,
	startFixed: boolean,
	trx: Transaction<Database>
) {
	const searchInterval = new Interval(c.startTime, c.targetTime);
	const expandedSearchInterval = searchInterval.expand(MAX_TRAVEL_MS * 6, MAX_TRAVEL_MS * 6);
	const targetCoordinates = [c.target.coordinates];
	const companies = await bookingApiQuery(
		c.start.coordinates,
		required,
		searchInterval,
		targetCoordinates,
		trx
	);

	const best = (
		await evaluateRequest(
			companies,
			expandedSearchInterval,
			c.start.coordinates,
			[{ coordinates: c.target.coordinates, times: [c.targetTime] }],
			required,
			startFixed
		)
	)[0][0];
	if (best == undefined) {
		return best;
	}
	const events = companies
		.find((c) => c.id == best.company)!
		.vehicles.find((v) => v.id == best.vehicle)!.events;
	const prevEventIdx = events.findLastIndex((e) => e.communicated <= best.pickupTime);
	const prevEvent: Event | undefined = events[prevEventIdx];
	const nextEvent: Event | undefined = events[prevEventIdx + 1];
	const res1 = getEventGroups(events, c.start.coordinates, prevEventIdx, best.pickupCase.how);
	const res2 = getEventGroups(events, c.target.coordinates, prevEventIdx, best.dropoffCase.how);
	const eventGroupUpdateList = res1.updateList.concat(res2.updateList);
	const tour = (() => {
		switch (best.pickupCase.how) {
			case InsertHow.NEW_TOUR:
				return undefined;
			case InsertHow.INSERT:
				return prevEvent!.tourId;
			case InsertHow.APPEND:
				return prevEvent!.tourId;
			case InsertHow.PREPEND:
				return nextEvent!.tourId;
			case InsertHow.CONNECT:
				return prevEvent!.tourId;
		}
	})();
	const mergeTourList: number[] = [];
	if (best.pickupCase.how == InsertHow.CONNECT) {
		mergeTourList.push(prevEvent.tourId);
		mergeTourList.push(nextEvent.tourId);
	}
	return {
		best,
		tour,
		mergeTourList,
		eventGroupUpdateList
	};
}

export type EventGroup = {
	id: number;
	group: string;
};

const getEventGroups = (
	events: Event[],
	coordinates: Coordinates,
	prevEventIdx: number,
	how: InsertHow
) => {
	const samePlace = (c1: Coordinates, c2: Coordinates) => {
		return c1.lat == c2.lat && c1.lng == c2.lng;
	};
	const updateList: EventGroup[] = [];
	const nextEvent = events[prevEventIdx + 1];
	if (how == InsertHow.NEW_TOUR) {
		return { updateList, eventGroup: uuidv4() };
	}
	if (how == InsertHow.PREPEND) {
		const eventGroup = !samePlace(nextEvent.coordinates, coordinates)
			? uuidv4()
			: nextEvent.eventGroup;
		return { updateList, eventGroup };
	}
	const prevEvent = events[prevEventIdx];
	const eventGroup = !samePlace(prevEvent.coordinates, coordinates)
		? uuidv4()
		: prevEvent.eventGroup;
	if (how != InsertHow.CONNECT) {
		return { updateList, eventGroup };
	}
	const nextTour = nextEvent!.tourId;
	for (let i = prevEventIdx + 1; i != events.length; ++i) {
		if (nextTour != events[i].tourId || !samePlace(events[i].coordinates, coordinates)) {
			break;
		}
		updateList.push({
			id: events[i].id,
			group: eventGroup
		});
	}
	return {
		updateList,
		eventGroup
	};
};
