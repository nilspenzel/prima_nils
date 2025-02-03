import type { Event } from '$lib/compositionTypes';
import { InsertHow } from '$lib/bookingAPI/insertionTypes';
import type { ExpectedConnection } from '$lib/bookingApiParameters';
import { oneToMany } from '$lib/api';
import type { InsertionEvaluation } from '$lib/bookingAPI/insertions';

export type DirectDurations = {
	pickup: number | null;
	dropoff: number | null;
	updates: {
		id: number;
		direct: number | null;
	}[];
};

export const getDirectDurations = async (
	best: InsertionEvaluation,
	prevPickupEvent: Event | undefined,
	prevPickupEventIdx: number | undefined,
	nextPickupEvent: Event | undefined,
	prevDropoffEvent: Event | undefined,
	prevDropoffEventIdx: number | undefined,
	nextDropoffEvent: Event | undefined,
	c: ExpectedConnection
): Promise<DirectDurations> => {
	const computeDurations = async (
		prevEvent: Event | undefined,
		prevIdx: number | undefined,
		nextEvent: Event | undefined,
		isPickup: boolean
	) => {
		const bestCase = isPickup ? best.pickupCase : best.dropoffCase;
		if (
			(bestCase.how == InsertHow.APPEND || bestCase.how == InsertHow.NEW_TOUR) &&
			prevEvent != undefined
		) {
			if (isPickup) {
				direct.pickup =
					(await oneToMany(prevEvent.coordinates, [c.target.coordinates], false))[0] ?? null;
			} else {
				direct.dropoff =
					(await oneToMany(prevEvent.coordinates, [c.target.coordinates], false))[0] ?? null;
			}
			console.log(direct);
		}
		if (
			(bestCase.how == InsertHow.PREPEND || bestCase.how == InsertHow.NEW_TOUR) &&
			nextEvent != undefined
		) {
			direct.updates.push({
				id: (prevIdx ?? 0) + 1,
				direct: (await oneToMany(c.target.coordinates, [nextEvent.coordinates], false))[0] ?? null
			});
		}
	};

	const direct: DirectDurations = {
		pickup: null,
		dropoff: null,
		updates: new Array<{ id: number; direct: number | null }>()
	};
	await computeDurations(prevPickupEvent, prevPickupEventIdx, nextPickupEvent, true);
	if (prevPickupEventIdx != prevDropoffEventIdx) {
		await computeDurations(prevDropoffEvent, prevDropoffEventIdx, nextDropoffEvent, false);
	}
	console.log(direct);
	return direct;
};
