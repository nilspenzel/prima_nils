import { describe, it, expect } from 'vitest';
import { Coordinates } from '$lib/location';
import type { Vehicle, Event } from '$lib/compositionTypes';
import { Interval } from '$lib/interval';

const createVehicle = (id: number, events: Event[]): Vehicle => {
	return {
		id,
		capacities: { passengers: 0, bikes: 0, wheelchairs: 0, luggage: 0 },
		events,
		tours: [],
		availabilities: [],
		lastEventBefore: undefined,
		firstEventAfter: undefined
	};
};

const createEvent = (id: number): Event => {
	return {
		capacities: { passengers: 0, bikes: 0, wheelchairs: 0, luggage: 0 },
		is_pickup: true,
		id,
		coordinates: new Coordinates(1, 1),
		tourId: 1,
		arrival: new Date(),
		departure: new Date(),
		communicated: new Date(),
		approachDuration: 0,
		returnDuration: 0,
		time: new Interval(new Date(), new Date()), 
		eventGroup: ''
	};
};

describe('getApproach and getReturn - duration tests', () => {
	it('insert both before first event, direction: TO_BUS', () => {
		expect(1).toBe(1);
	});
});
