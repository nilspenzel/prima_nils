import { describe, it, expect } from 'vitest';
import { Coordinates } from '$lib/location';
import type { Vehicle, Event } from '$lib/compositionTypes';
import { Interval } from '$lib/interval';
import {
	InsertDirection,
	InsertHow,
	InsertWhat,
	InsertWhere,
	type InsertionType
} from './insertionTypes';
import { getAllowedOperationTimes } from './durations';

const createVehicle = (availabilities: Interval[]): Vehicle => {
	return {
		id: 1,
		capacities: { passengers: 0, bikes: 0, wheelchairs: 0, luggage: 0 },
		events: [],
		tours: [],
		availabilities,
		lastEventBefore: undefined,
		firstEventAfter: undefined
	};
};

const createEvent = (departure: number, communicated: number, arrival: number): Event => {
	return {
		capacities: { passengers: 0, bikes: 0, wheelchairs: 0, luggage: 0 },
		is_pickup: true,
		id: 1,
		coordinates: new Coordinates(1, 1),
		tourId: 1,
		arrival: inX(arrival),
		departure: inX(departure),
		communicated: inX(communicated),
		approachDuration: 0,
		returnDuration: 0,
		time: new Interval(new Date(), new Date()),
		eventGroup: ''
	};
};

const BASE_MS = new Date('4000-01-01T00:00:00.0Z').getTime();
const inX = (ms: number) => {
	return new Date(BASE_MS + ms);
};

describe('get allowed operation times test', () => {
	it('insert as new tour', () => {
		const insertionCase: InsertionType = {
			how: InsertHow.NEW_TOUR,
			direction: InsertDirection.FROM_BUS_STOP,
			where: InsertWhere.AFTER_LAST_EVENT,
			what: InsertWhat.BOTH
		};
		const prev = createEvent(1, 2, 3);
		const next = createEvent(7, 8, 9);
		const expandedSearchInterval = new Interval(inX(-5), inX(1000));
		const prepTime = new Date();
		const vehicle = createVehicle([new Interval(inX(2), inX(5))]);

		const res = getAllowedOperationTimes(
			insertionCase,
			prev,
			next,
			expandedSearchInterval,
			prepTime,
			vehicle
		);
		expect(res[0].startTime.getTime()).toBe(new Date('4000-01-01T00:00:00.003Z').getTime());
		expect(res[0].endTime.getTime()).toBe(new Date('4000-01-01T00:00:00.005Z').getTime());
	});
	it('undefined events', () => {
		const insertionCase: InsertionType = {
			how: InsertHow.NEW_TOUR,
			direction: InsertDirection.FROM_BUS_STOP,
			where: InsertWhere.AFTER_LAST_EVENT,
			what: InsertWhat.BOTH
		};
		const prev = createEvent(1, 2, 3);
		const next = createEvent(1001, 8, 9);
		const expandedSearchInterval = new Interval(inX(0), inX(1000));
		const prepTime = new Date();
		const vehicle = createVehicle([new Interval(inX(2), inX(1001))]);

		const res = getAllowedOperationTimes(
			insertionCase,
			prev,
			next,
			expandedSearchInterval,
			prepTime,
			vehicle
		);
		expect(res[0].startTime.getTime()).toBe(new Date('4000-01-01T00:00:00.003Z').getTime());
		expect(res[0].endTime.getTime()).toBe(new Date('4000-01-01T00:00:01.001Z').getTime());

		const resNextUndefined = getAllowedOperationTimes(
			insertionCase,
			prev,
			undefined,
			expandedSearchInterval,
			prepTime,
			vehicle
		);
		expect(resNextUndefined[0].endTime.getTime()).toBe(
			new Date('4000-01-01T00:00:01.000Z').getTime()
		);

		const resPrevUndefined = getAllowedOperationTimes(
			insertionCase,
			undefined,
			next,
			expandedSearchInterval,
			prepTime,
			vehicle
		);
		expect(resPrevUndefined[0].startTime.getTime()).toBe(
			new Date('4000-01-01T00:00:00.002Z').getTime()
		);
	});
	it('insert as new test, one allowed time point', () => {
		const insertionCase: InsertionType = {
			how: InsertHow.NEW_TOUR,
			direction: InsertDirection.FROM_BUS_STOP,
			where: InsertWhere.AFTER_LAST_EVENT,
			what: InsertWhat.BOTH
		};
		const prev = createEvent(1, 2, 4);
		const next = createEvent(4, 5, 6);
		const expandedSearchInterval = new Interval(inX(-5), inX(1000));
		const prepTime = new Date();
		const vehicle = createVehicle([new Interval(inX(2), inX(5))]);

		const res = getAllowedOperationTimes(
			insertionCase,
			prev,
			next,
			expandedSearchInterval,
			prepTime,
			vehicle
		);
		expect(res[0].startTime.getTime()).toBe(new Date('4000-01-01T00:00:00.004Z').getTime());
		expect(res[0].endTime.getTime()).toBe(new Date('4000-01-01T00:00:00.004Z').getTime());
	});
	it('insert by appending', () => {
		const insertionCase: InsertionType = {
			how: InsertHow.APPEND,
			direction: InsertDirection.FROM_BUS_STOP,
			where: InsertWhere.AFTER_LAST_EVENT,
			what: InsertWhat.BOTH
		};
		const prev = createEvent(1, 2, 3);
		const next = createEvent(7, 8, 9);
		const expandedSearchInterval = new Interval(inX(-5), inX(1000));
		const prepTime = new Date();
		const vehicle = createVehicle([new Interval(inX(0), inX(7))]);

		const res = getAllowedOperationTimes(
			insertionCase,
			prev,
			next,
			expandedSearchInterval,
			prepTime,
			vehicle
		);
		expect(res[0].startTime.getTime()).toBe(new Date('4000-01-01T00:00:00.002Z').getTime());
		expect(res[0].endTime.getTime()).toBe(new Date('4000-01-01T00:00:00.007Z').getTime());

		vehicle.availabilities[0] = new Interval(inX(0), inX(6));
		const resNoAvailability = getAllowedOperationTimes(
			insertionCase,
			prev,
			next,
			expandedSearchInterval,
			prepTime,
			vehicle
		);
		expect(resNoAvailability).toHaveLength(1);
	});
	it('insert by prepending', () => {
		const insertionCase: InsertionType = {
			how: InsertHow.PREPEND,
			direction: InsertDirection.FROM_BUS_STOP,
			where: InsertWhere.AFTER_LAST_EVENT,
			what: InsertWhat.BOTH
		};
		const prev = createEvent(1, 2, 3);
		const next = createEvent(7, 8, 9);
		const expandedSearchInterval = new Interval(inX(-5), inX(1000));
		const prepTime = new Date();
		const vehicle = createVehicle([new Interval(inX(0), inX(7))]);

		const res = getAllowedOperationTimes(
			insertionCase,
			prev,
			next,
			expandedSearchInterval,
			prepTime,
			vehicle
		);
		expect(res.length).toBe(0);
		//expect(res[0].startTime.getTime()).toBe(new Date('4000-01-01T00:00:00.003Z').getTime());
		//expect(res[0].endTime.getTime()).toBe(new Date('4000-01-01T00:00:00.007Z').getTime());

		vehicle.availabilities[0] = new Interval(inX(4), inX(7));
		const resNoAvailability = getAllowedOperationTimes(
			insertionCase,
			prev,
			next,
			expandedSearchInterval,
			prepTime,
			vehicle
		);
		expect(resNoAvailability).toHaveLength(0);
	});
	it('insert by connecting', () => {
		const insertionCase: InsertionType = {
			how: InsertHow.CONNECT,
			direction: InsertDirection.FROM_BUS_STOP,
			where: InsertWhere.AFTER_LAST_EVENT,
			what: InsertWhat.BOTH
		};
		const prev = createEvent(1, 2, 3);
		const next = createEvent(7, 8, 9);
		const expandedSearchInterval = new Interval(inX(-5), inX(1000));
		const prepTime = new Date();
		const vehicle = createVehicle([new Interval(inX(0), inX(7))]);

		const res = getAllowedOperationTimes(
			insertionCase,
			prev,
			next,
			expandedSearchInterval,
			prepTime,
			vehicle
		);
		expect(res[0].startTime.getTime()).toBe(new Date('4000-01-01T00:00:00.003Z').getTime());
		expect(res[0].endTime.getTime()).toBe(new Date('4000-01-01T00:00:00.007Z').getTime());

		vehicle.availabilities[0] = new Interval(inX(4), inX(7));
		const resNoAvailability1 = getAllowedOperationTimes(
			insertionCase,
			prev,
			next,
			expandedSearchInterval,
			prepTime,
			vehicle
		);
		expect(resNoAvailability1).toHaveLength(0);

		vehicle.availabilities[0] = new Interval(inX(0), inX(6));
		const resNoAvailability2 = getAllowedOperationTimes(
			insertionCase,
			prev,
			next,
			expandedSearchInterval,
			prepTime,
			vehicle
		);
		expect(resNoAvailability2).toHaveLength(0);
	});
	it('insert', () => {
		const insertionCase: InsertionType = {
			how: InsertHow.INSERT,
			direction: InsertDirection.FROM_BUS_STOP,
			where: InsertWhere.AFTER_LAST_EVENT,
			what: InsertWhat.BOTH
		};
		const prev = createEvent(1, 2, 3);
		const next = createEvent(7, 8, 9);
		const expandedSearchInterval = new Interval(inX(-5), inX(1000));
		const prepTime = new Date();
		const vehicle = createVehicle([]);

		const res = getAllowedOperationTimes(
			insertionCase,
			prev,
			next,
			expandedSearchInterval,
			prepTime,
			vehicle
		);
		expect(res[0].startTime.getTime()).toBe(new Date('4000-01-01T00:00:00.002Z').getTime());
		expect(res[0].endTime.getTime()).toBe(new Date('4000-01-01T00:00:00.008Z').getTime());
	});
});
