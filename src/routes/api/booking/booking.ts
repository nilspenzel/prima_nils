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
import { samePlace } from '$lib/bookingAPI/utils';

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
	const userChosen = !startFixed ? c.start.coordinates : c.target.coordinates;
	const userChosenTime = !startFixed ? c.startTime : c.targetTime;
	const busStop = startFixed ? c.start.coordinates : c.target.coordinates;
	const busTime = startFixed ? c.startTime : c.targetTime;
	const best = (
		await evaluateRequest(
			companies,
			expandedSearchInterval,
			userChosen,
			[{ coordinates: busStop, times: [busTime] }],
			required,
			startFixed,
			new Date(userChosenTime)
		)
	)[0][0];
	//console.log("BEST: ", best);
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
	const prevPickupEventIdx = events.findLastIndex((e) => e.communicated <= best.pickupTime);
	const prevDropoffEventIdx = events.findLastIndex((e) => e.communicated <= best.dropoffTime);
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
	const mergeTourList = getMergeTourList(events, best.pickupCase.how, best.dropoffCase.how, prevPickupEventIdx, prevDropoffEventIdx);
	return {
		best,
		tour,
		mergeTourList,
		eventGroupUpdateList,
		startEventGroup: startEventGroupInfo.newEventGroup,
		targetEventGroup: targetEventGroupInfo.newEventGroup
	};
}

const getMergeTourList = (events: Event[], pickupHow: InsertHow, dropoffHow: InsertHow, pickupIdx: number, dropoffIdx: number): Set<number> => {
	if(events.length == 0){
		return new Set<number>();
	}
	const tours = new Set<number>();
	if((pickupHow==InsertHow.CONNECT)){
		tours.add(events[pickupIdx].tourId);
	}
	if((dropoffHow==InsertHow.CONNECT)){
		tours.add(events[dropoffIdx+1].tourId);
	}
	events.slice(pickupIdx, dropoffIdx+1).forEach((ev) => {
		tours.add(ev.tourId);
	});
	if(tours.size == 1){
		return new Set<number>();
	}
	return tours;
}

export type EventGroup = {
	id: number;
	group: string;
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
