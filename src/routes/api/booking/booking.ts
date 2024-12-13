import type { Capacities } from '$lib/capacities';
import { MAX_TRAVEL_MS } from '$lib/constants';
import { Interval } from '$lib/interval';
import type { Coordinates } from '$lib/location';
import { bookingApiQuery } from '$lib/bookingAPI/query';
import type { Transaction } from 'kysely';
import type { Database } from '$lib/types';
import type { Event } from '$lib/compositionTypes';
import { InsertHow } from '$lib/bookingAPI/insertionTypes';
import type { ExpectedConnection } from '$lib/bookingApiParameters';
import { evaluateRequest } from '$lib/bookingAPI/evaluateRequest';
import { v4 as uuidv4 } from 'uuid';

export async function booking(
	c: ExpectedConnection,
	required: Capacities,
	startFixed: boolean,
	trx: Transaction<Database>
) {
	const searchInterval = new Interval(new Date(c.startTime), new Date(c.targetTime));
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
	const events = companies[best.company].vehicles.find((v) => v.id == best.vehicle)!.events;
	const prevEventIdx = events.findLastIndex((e) => e.communicated <= best.pickupTime);
	const startEventGroupInfo = handleEventGroups(
		events,
		c.start.coordinates,
		prevEventIdx,
		best.pickupCase.how
	);
	const prevDropoffEventIdx = events.findLastIndex((e) => e.communicated <= best.pickupTime);
	const targetEventGroupInfo = handleEventGroups(
		events,
		c.target.coordinates,
		prevDropoffEventIdx,
		best.dropoffCase.how
	);
	const eventGroupUpdateList = {
		ids: startEventGroupInfo.updateList.ids.concat(targetEventGroupInfo.updateList.ids),
		updates: startEventGroupInfo.updateList.updates.concat(targetEventGroupInfo.updateList.updates)
	};

	const prevEvent = events[prevEventIdx];
	const nextEvent = events[prevEventIdx + 1];
	const tour = (() => {
		switch (best.pickupCase.how) {
			case InsertHow.NEW_TOUR:
				return undefined;
			case InsertHow.PREPEND:
				return nextEvent!.tourId;
			default:
				return prevEvent!.tourId;
		}
	})();
	const mergeTourList: number[] = [];
	if (best.pickupCase.how == InsertHow.CONNECT) {
		mergeTourList.push(prevEvent.tourId);
		mergeTourList.push(nextEvent.tourId);
	}
	if (best.dropoffCase.how == InsertHow.CONNECT) {
		const prevDropoffEvent = events[prevDropoffEventIdx];
		const nextDropoffEvent = events[prevDropoffEventIdx + 1];
		if (mergeTourList.find((t) => t == prevDropoffEvent.tourId) == undefined) {
			mergeTourList.push(prevDropoffEvent.tourId);
		}
		if (mergeTourList.find((t) => t == nextDropoffEvent.tourId) == undefined) {
			mergeTourList.push(nextDropoffEvent.tourId);
		}
	}

	return {
		best,
		tour,
		mergeTourList,
		eventGroupUpdateList,
		startEventGroup: startEventGroupInfo.newEventGroup,
		targetEventGroup: targetEventGroupInfo.newEventGroup
	};
}

export type EventGroup = {
	id: number;
	group: string;
};

const samePlace = (c1: Coordinates, c2: Coordinates) => {
	return c1.lat == c2.lat && c1.lng == c2.lng;
};

const handleEventGroups = (
	events: Event[],
	coordinates: Coordinates,
	prevEventIdx: number,
	how: InsertHow
) => {
	const prevEvent = events[prevEventIdx];
	const nextEvent = events[prevEventIdx + 1];
	const newEventGroup = getNewEventGroup(prevEvent, nextEvent, coordinates, how);
	return {
		newEventGroup,
		updateList: getEventGroupUpdates(events, coordinates, prevEventIdx, how, newEventGroup)
	};
};

const getNewEventGroup = (
	prevEvent: Event,
	nextEvent: Event,
	coordinates: Coordinates,
	how: InsertHow
) => {
	if (how == InsertHow.NEW_TOUR) {
		return uuidv4();
	}
	const comparisonEvent = how == InsertHow.PREPEND ? nextEvent : prevEvent;
	return !samePlace(comparisonEvent.coordinates, coordinates)
		? uuidv4()
		: comparisonEvent.eventGroup;
};

const getEventGroupUpdates = (
	events: Event[],
	coordinates: Coordinates,
	prevEventIdx: number,
	how: InsertHow,
	newEventGroup: string
): EventGroupUpdateList => {
	if (how != InsertHow.CONNECT) {
		return {
			ids: [],
			updates: []
		};
	}
	const nextEvent = events[prevEventIdx + 1];
	const nextTour = nextEvent!.tourId;
	const idList: number[] = [];
	const newEventGroupList: string[] = [];
	for (let i = prevEventIdx + 1; i != events.length; ++i) {
		if (nextTour != events[i].tourId || !samePlace(events[i].coordinates, coordinates)) {
			break;
		}
		idList.push(events[i].id);
		newEventGroupList.push(newEventGroup);
	}
	return {
		ids: idList,
		updates: newEventGroupList
	};
};

export type EventGroupUpdateList = {
	ids: number[];
	updates: string[];
};
