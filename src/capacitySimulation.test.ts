import type { Event } from '$lib/compositionTypes';
import { describe, it, expect } from 'vitest';
import { Capacity, CapacitySimulation, Range } from './routes/api/bookingRequest/capacities';
import { Interval } from '$lib/interval';
import { Coordinates } from '$lib/location';

const defaultSimulation = () => {
	return new CapacitySimulation(3, 3, 3, 3);
};

const createEvents = (
	e: (
		| {
				passengers?: number;
				bikes?: number;
				wheelchairs?: number;
				luggage?: number;
				tourId?: number;
				isPickup: boolean;
		  }
		| boolean
	)[]
): Event[] => {
	return e.map((e) => {
		if (typeof e == 'boolean') {
			return {
				passengers: 1,
				bikes: 0,
				wheelchairs: 0,
				luggage: 0,
				is_pickup: e,
				time: new Interval(new Date(Date.now()), new Date(Date.now())),
				id: 0,
				tourId: 1,
				coordinates: new Coordinates(0, 0)
			};
		}
		return {
			passengers: e.passengers == undefined ? 1 : e.passengers,
			bikes: e.bikes == undefined ? 0 : e.bikes,
			wheelchairs: e.wheelchairs == undefined ? 0 : e.wheelchairs,
			luggage: e.luggage == undefined ? 0 : e.luggage,
			is_pickup: e.isPickup,
			time: new Interval(new Date(Date.now()), new Date(Date.now())),
			id: 0,
			tourId: e.tourId == undefined ? 1 : e.tourId,
			coordinates: new Coordinates(0, 0)
		};
	});
};

describe('capacity Simulation yields correct insertion-intervals, simple', async () => {
	const events: Event[] = createEvents([true, false]);
	const simulation: CapacitySimulation = new CapacitySimulation(1, 0, 0, 0);
	const requiredCapacities: Capacity = {
		passengers: 1,
		bikes: 0,
		wheelchairs: 0,
		luggage: 0
	};
	const insertions = simulation.getPossibleInsertionIntervals(events, requiredCapacities);
	console.log("ins",insertions);
	it('zones match', () => {
		expect(insertions).toStrictEqual([new Range(0, 0), new Range(2, 2)]);
	});
});

describe('capacity Simulation yields correct insertion-intervals', async () => {
	const events: Event[] = createEvents([true, true, true, false, true, false, false, false]);
	const simulation: CapacitySimulation = defaultSimulation();
	const requiredCapacities: Capacity = {
		passengers: 1,
		bikes: 0,
		wheelchairs: 0,
		luggage: 0
	};
	const insertions = simulation.getPossibleInsertionIntervals(events, requiredCapacities);
	it('zones match', () => {
		expect(insertions).toStrictEqual([new Range(0, 2), new Range(4, 4), new Range(6, 8)]);
	});
});
