import type { Company, Event } from '$lib/compositionTypes';
import { describe, it, expect } from 'vitest';
import { Capacity, CapacitySimulation, Range } from './routes/api/bookingRequest/capacities';
import { Interval } from '$lib/interval';
import { Coordinates } from '$lib/location';
import { TourConcatenationType, TourConcatenations } from './routes/api/bookingRequest/tourConcatenation';
import { bookingApiQuery } from './routes/api/bookingRequest/queries';
import { hoursToMs } from '$lib/time_utils';

describe('capacity Simulation yields correct insertion-intervals, simple', async () => {
	const tc = new TourConcatenations();
	const requiredCapacities: Capacity = {
		passengers: 1,
		bikes: 0,
		wheelchairs: 0,
		luggage: 0
	};
    const baseDate = new Date("2025-04-19");
    const p = {
        start: new Coordinates(51.506830990075144, 14.625787678141847),
    target: new Coordinates(51.50607958830929, 14.642887782399583),
    interval: new Interval(
        new Date(baseDate.getTime()),
        new Date(baseDate.getTime() + hoursToMs(24))
    ),
    capacities: { bikes: 0, wheelchairs: 0, luggage: 0, passengers: 1 }
}
	const dbResult = await bookingApiQuery(p.start, p.capacities, p.interval, [p.target]);
    tc.createTourConcatenations(dbResult.companies, requiredCapacities);   
	it('zones match', () => {
		expect(tc.concatenations.length).toBe(4);
	});
});
