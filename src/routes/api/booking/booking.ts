import type { Capacities } from '$lib/capacities';
import { MAX_TRAVEL_MS } from '$lib/constants';
import { Interval } from '$lib/interval';
import { bookingApiQuery } from '$lib/bookingAPI/query';
import type { Transaction } from 'kysely';
import type { Database } from '$lib/types';
import { InsertHow } from '$lib/bookingAPI/insertionTypes';
import type { ExpectedConnection } from '$lib/bookingApiParameters';
import { evaluateRequest } from '$lib/bookingAPI/evaluateRequest';
import { getEventGroupInfo } from './eventGroups';
import { getMergeTourList } from './mergeTourList';
import { getDirectDurations } from './directDrivingDurations';

export async function booking(
	c: ExpectedConnection,
	required: Capacities,
	startFixed: boolean,
	trx: Transaction<Database>
) {
	console.log('BS');
	const searchInterval = new Interval(c.startTime, c.targetTime);
	const expandedSearchInterval = searchInterval.expand(MAX_TRAVEL_MS * 6, MAX_TRAVEL_MS * 6);
	const targetCoordinates = [c.target.coordinates];
	const { companies, busStopPerm } = await bookingApiQuery(
		c.start.coordinates,
		required,
		searchInterval,
		targetCoordinates,
		trx
	);
	if (companies.length == 0 || busStopPerm[0] == undefined) {
		return undefined;
	}
	const userChosen = !startFixed ? c.start.coordinates : c.target.coordinates;
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
			{
				pickup: new Date(c.startTime),
				dropoff: new Date(c.targetTime)
			}
		)
	)[0][0];
	if (best == undefined) {
		return undefined;
	}
	const events = companies[best.company].vehicles.find((v) => v.id == best.vehicle)!.events;
	let prevPickupEventIdx = best.pickupIdx == undefined ? undefined : best.pickupIdx - 1;
	if (best.pickupCase.how == InsertHow.NEW_TOUR) {
		prevPickupEventIdx = events.findLastIndex((e) => e.communicated <= best.pickupTime);
	}
	const pickupEventGroupInfo = getEventGroupInfo(
		events,
		c.start.coordinates,
		prevPickupEventIdx,
		best.pickupIdx,
		best.pickupCase.how
	);
	const prevDropoffEventIdx = best.dropoffIdx == undefined ? undefined : best.dropoffIdx - 1;
	const dropoffEventGroupInfo = getEventGroupInfo(
		events,
		c.target.coordinates,
		prevDropoffEventIdx,
		best.dropoffIdx,
		best.dropoffCase.how
	);
	const prevPickupEvent = best.pickupIdx == undefined ? undefined : events[best.pickupIdx - 1];
	const nextPickupEvent = best.pickupIdx == undefined ? undefined : events[best.pickupIdx];
	const prevDropoffEvent = best.dropoffIdx == undefined ? undefined : events[best.dropoffIdx - 1];
	const nextDropoffEvent = best.dropoffIdx == undefined ? undefined : events[best.dropoffIdx];
	const prevEventIdxOtherTour =
		best.pickupCase.how == InsertHow.NEW_TOUR
			? events.findLastIndex((e) => e.communicated <= best.pickupTime)
			: prevPickupEventIdx;
	const prevEventInOtherTour =
		prevEventIdxOtherTour == undefined || prevEventIdxOtherTour == -1
			? undefined
			: events[prevEventIdxOtherTour];
	const directDurations = await getDirectDurations(
		best,
		prevEventInOtherTour,
		prevEventIdxOtherTour,
		nextPickupEvent,
		prevDropoffEvent,
		prevDropoffEventIdx,
		nextDropoffEvent,
		c
	);
	console.log('BE');
	return {
		best,
		tour: (() => {
			switch (best.pickupCase.how) {
				case InsertHow.NEW_TOUR:
					return undefined;
				case InsertHow.PREPEND:
					return nextPickupEvent!.tourId;
				default:
					return prevPickupEvent!.tourId;
			}
		})(),
		mergeTourList: getMergeTourList(
			events,
			best.pickupCase.how,
			best.dropoffCase.how,
			prevPickupEventIdx,
			prevDropoffEventIdx
		),
		eventGroupUpdateList: pickupEventGroupInfo.updateList.concat(dropoffEventGroupInfo.updateList),
		pickupEventGroup: pickupEventGroupInfo.newEventGroup,
		dropoffEventGroup: dropoffEventGroupInfo.newEventGroup,
		neighbourIds: {
			prevPickup: best.pickupCase.how == InsertHow.PREPEND ? undefined : prevPickupEvent?.id,
			nextPickup: best.pickupCase.how == InsertHow.APPEND ? undefined : nextPickupEvent?.id,
			prevDropoff: best.dropoffCase.how == InsertHow.PREPEND ? undefined : prevDropoffEvent?.id,
			nextDropoff: best.dropoffCase.how == InsertHow.APPEND ? undefined : nextDropoffEvent?.id
		},
		directDurations
	};
}
