import { beforeEach, describe, expect, it, vi } from 'vitest';
import { PASSENGER_CHANGE_DURATION } from '$lib/constants';
import { oneToManyCarRouting } from '$lib/server/util/oneToManyCarRouting';
import { getTaxiConnectionDuration } from './getTaxiConnectionDuration';

vi.mock('$lib/server/util/oneToManyCarRouting', () => ({
	oneToManyCarRouting: vi.fn()
}));

const mockedOneToManyCarRouting = vi.mocked(oneToManyCarRouting);
const from = { lat: 51, lng: 14 };

beforeEach(() => {
	mockedOneToManyCarRouting.mockReset();
});

describe('getTaxiConnectionDuration', () => {
	it('returns zero without routing when the places are considered equal', async () => {
		const to = { lat: from.lat + 0.000001, lng: from.lng - 0.000001 };

		await expect(
			getTaxiConnectionDuration(from, to, false, { addPassengerChange: true })
		).resolves.toBe(0);
		expect(mockedOneToManyCarRouting).not.toHaveBeenCalled();
	});

	it('adds passenger-change time for different places when requested', async () => {
		const to = { lat: 51.1, lng: 14.1 };
		mockedOneToManyCarRouting.mockResolvedValue([120_000]);

		await expect(
			getTaxiConnectionDuration(from, to, true, { addPassengerChange: true })
		).resolves.toBe(120_000 + PASSENGER_CHANGE_DURATION);
		expect(mockedOneToManyCarRouting).toHaveBeenCalledWith(from, [to], true);
	});

	it('returns the raw duration when passenger-change time is disabled', async () => {
		const to = { lat: 51.1, lng: 14.1 };
		mockedOneToManyCarRouting.mockResolvedValue([120_000]);

		await expect(
			getTaxiConnectionDuration(from, to, false, { addPassengerChange: false })
		).resolves.toBe(120_000);
	});

	it('preserves an unavailable routing result', async () => {
		const to = { lat: 51.1, lng: 14.1 };
		mockedOneToManyCarRouting.mockResolvedValue([undefined]);

		await expect(
			getTaxiConnectionDuration(from, to, false, { addPassengerChange: true })
		).resolves.toBeUndefined();
	});
});
