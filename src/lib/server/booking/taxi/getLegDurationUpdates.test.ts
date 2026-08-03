import { PASSENGER_CHANGE_DURATION } from '$lib/constants';
import { InsertHow, InsertWhat } from '$lib/util/booking/insertionTypes';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import type { Event } from './getBookingAvailability';
import { getLegDurationUpdates } from './getLegDurationUpdates';
import type { Insertion } from './insertion';

const { oneToManyCarRouting } = vi.hoisted(() => ({ oneToManyCarRouting: vi.fn() }));
vi.mock('$lib/server/util/oneToManyCarRouting', () => ({ oneToManyCarRouting }));

beforeEach(() => {
	oneToManyCarRouting.mockReset();
});

describe('getLegDurationUpdates', () => {
	it('keeps a zero routing duration', async () => {
		oneToManyCarRouting.mockResolvedValue([0]);
		const firstEvent = { id: 2 } as Event;
		const lastEvent = { id: 1 } as Event;
		const insertion = {
			pickupCase: { how: InsertHow.CONNECT, what: InsertWhat.BOTH }
		} as Insertion;

		const updates = await getLegDurationUpdates(
			[firstEvent],
			[lastEvent],
			undefined,
			undefined,
			undefined,
			undefined,
			undefined,
			undefined,
			insertion
		);

		expect(updates.prevLegDurations).toEqual([
			{ event: firstEvent.id, duration: PASSENGER_CHANGE_DURATION }
		]);
		expect(updates.nextLegDurations).toEqual([
			{ event: lastEvent.id, duration: PASSENGER_CHANGE_DURATION }
		]);
	});
});
