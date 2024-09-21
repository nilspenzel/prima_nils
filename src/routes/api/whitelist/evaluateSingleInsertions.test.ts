import { describe, it, expect } from 'vitest';
import { type Range } from './capacitySimulation';
import { Coordinates } from '$lib/location';
import { gatherRoutingCoordinates, type RoutingResults } from './routing';
import { computeTravelDurations } from './insertions';
import type { Vehicle, Company, Tour, Event } from '$lib/compositionTypes';
import { Interval } from '$lib/interval';
import type { OneToManyResult } from '$lib/api';

const createCompany = (vehicles: Vehicle[], coordinates: Coordinates): Company => {
	return {
		id: 1,
		coordinates: coordinates,
		vehicles,
		zoneId: 1
	};
};

const createVehicle = (id: number, tours: Tour[]): Vehicle => {
	return {
		id,
		capacities: { passengers: 0, bikes: 0, wheelchairs: 0, luggage: 0 },
		tours,
		availabilities: []
	};
};

const createTour = (events: Event[]): Tour => {
	return {
		departure: new Date(),
		arrival: new Date(),
		id: 1,
		events
	};
};

const createEvent = (coordinates: Coordinates): Event => {
	return {
		capacities: { passengers: 0, bikes: 0, wheelchairs: 0, luggage: 0 },
		is_pickup: true,
		time: new Interval(new Date(), new Date()),
		id: 1,
		coordinates,
		tourId: 1,
		communitcated: new Date(),
		arrival: new Date(),
		departure: new Date()
	};
};

describe('compute Intervals for single insertions test', () => {
	it('TODO', () => {


		let eventLatLng = 100;
		let companyLatLng = 5;
		const companies = [
			createCompany(
				[
					createVehicle(1, [
						createTour([
							//createEvent(new Coordinates(eventLatLng, eventLatLng++)),
							createEvent(new Coordinates(eventLatLng, eventLatLng++))
						])
					])
				],
				new Coordinates(companyLatLng, companyLatLng++)
			)
		];
		const insertions = new Map<number, Range[]>();
		insertions.set(1, [{ earliestPickup: 0, latestDropoff: 1 }]);
        const travelDurations = [50];
        const routingResults: RoutingResults = {busStops: [{fromPrev: [{duration: 0, distance: 0},{duration: 0, distance: 0}], toNext:[{duration: 0, distance: 0},{duration: 0, distance: 0}]}], userChosen: {fromPrev: [{duration: 0, distance: 0},{duration: 0, distance: 0}], toNext:[{duration: 0, distance: 0},{duration: 0, distance: 0}]}};
        const busStopTimes = [[new Interval(new Date(), new Date())]];
        const result = computeTravelDurations(companies, insertions, routingResults, travelDurations, true, busStopTimes, []);
        console.log(result);
	});
});