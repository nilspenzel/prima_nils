import type { Mode } from '$lib/openapi';
import { describe, expect, it, vi } from 'vitest';
import {
	findSuboptimalEdgeOdmConnections,
	findSuboptimalEdgeOdmConnectionsInItineraries
} from './checkEdgeOdmStreetRouting';

const place = (name: string, lat: number, lon: number) => ({ name, lat, lon });
const leg = (
	mode: Mode,
	duration: number,
	from: ReturnType<typeof place>,
	to: ReturnType<typeof place>
) => ({
	mode,
	duration,
	from,
	to
});
const tolerance = { minSavingSeconds: 60, minSavingPercent: 10 };

describe('findSuboptimalEdgeOdmConnections', () => {
	it('finds a faster extension of an initial ODM leg', async () => {
		const start = place('start', 51.5, 14.5);
		const stop = place('stop', 51.6, 14.6);
		const target = place('target', 51.7, 14.7);
		const routing = vi.fn().mockResolvedValue([400_000]);

		const result = await findSuboptimalEdgeOdmConnections(
			{ legs: [leg('ODM', 600, start, stop), leg('BUS', 300, stop, target)] },
			tolerance,
			routing
		);

		expect(routing).toHaveBeenCalledWith(
			{ lat: start.lat, lng: start.lon },
			[{ lat: target.lat, lng: target.lon }],
			false
		);
		expect(result).toEqual([
			{
				edge: 'start',
				comparedLegIndex: 1,
				comparedMode: 'BUS',
				odmDurationSeconds: 600,
				streetDurationSeconds: 400,
				savingSeconds: 200,
				savingPercent: 33
			}
		]);
	});

	it('reverses the routing direction for a final ODM leg', async () => {
		const start = place('start', 51.5, 14.5);
		const stop = place('stop', 51.6, 14.6);
		const target = place('target', 51.7, 14.7);
		const routing = vi.fn().mockResolvedValue([400_000]);

		const result = await findSuboptimalEdgeOdmConnections(
			{ legs: [leg('BUS', 300, start, stop), leg('ODM', 600, stop, target)] },
			tolerance,
			routing
		);

		expect(routing).toHaveBeenCalledWith(
			{ lat: target.lat, lng: target.lon },
			[{ lat: start.lat, lng: start.lon }],
			true
		);
		expect(result[0]).toMatchObject({ edge: 'end', comparedLegIndex: 0 });
	});

	it.each([
		{ odmDuration: 300, streetDurationMs: 250_000 },
		{ odmDuration: 2_000, streetDurationMs: 1_900_000 }
	])(
		'requires both saving tolerances for $odmDuration seconds',
		async ({ odmDuration, streetDurationMs }) => {
			const start = place('start', 51.5, 14.5);
			const stop = place('stop', 51.6, 14.6);
			const target = place('target', 51.7, 14.7);
			const routing = vi.fn().mockResolvedValue([streetDurationMs]);

			const result = await findSuboptimalEdgeOdmConnections(
				{ legs: [leg('ODM', odmDuration, start, stop), leg('BUS', 300, stop, target)] },
				tolerance,
				routing
			);

			expect(result).toEqual([]);
		}
	);

	it('does not route to WALK or ODM legs', async () => {
		const start = place('start', 51.5, 14.5);
		const stop = place('stop', 51.6, 14.6);
		const target = place('target', 51.7, 14.7);
		const routing = vi.fn();

		const result = await findSuboptimalEdgeOdmConnections(
			{
				legs: [
					leg('ODM', 600, start, stop),
					leg('WALK', 300, stop, target),
					leg('ODM', 300, target, stop)
				]
			},
			tolerance,
			routing
		);

		expect(result).toEqual([]);
		expect(routing).not.toHaveBeenCalled();
	});

	it('batches itineraries with the same journey endpoints and deduplicates targets', async () => {
		const start = place('start', 51.5, 14.5);
		const stop = place('stop', 51.6, 14.6);
		const target = place('target', 51.7, 14.7);
		const routing = vi.fn().mockResolvedValue([400_000]);
		const itinerary = {
			legs: [leg('ODM', 600, start, stop), leg('BUS', 300, stop, target)]
		};

		const result = await findSuboptimalEdgeOdmConnectionsInItineraries(
			[itinerary, itinerary],
			tolerance,
			routing
		);

		expect(routing).toHaveBeenCalledTimes(1);
		expect(routing).toHaveBeenCalledWith(
			{ lat: start.lat, lng: start.lon },
			[{ lat: target.lat, lng: target.lon }],
			false
		);
		expect(result.map(({ itineraryIndex }) => itineraryIndex)).toEqual([0, 1]);
	});
});
