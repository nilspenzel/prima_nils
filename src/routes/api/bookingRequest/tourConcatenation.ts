import { Interval } from '$lib/interval.js';
import { Coordinates } from '$lib/location.js';
import { minutesToMs } from '$lib/time_utils.js';
import { Capacity, CapacitySimulation, Range } from './capacities.js';
import { forEachVehicle } from './queries.js';
import { type Company, type Event } from '$lib/compositionTypes.js';

const isInsertionPossible = (prev: Event, next: Event): boolean => {
	// TODO: Check based on beeline distance
	return true;
};

function addTourConcatCoordinates(tourConcatenation: TourConcatenation,
	startMany: Coordinates[],
	targetMany: Coordinates[]): void {
	const addCoordinates = (
		start: boolean,
		tourConcatenation: TourConcatenation,
		many: Coordinates[],
		coordinates: Coordinates
	) => {
		const position: number | undefined = many.findIndex(
			(coordinates) => coordinates.lat == coordinates.lat && coordinates.lng == coordinates.lng
		);
		let routingResultIdx: number | undefined = undefined;
		if (position == undefined) {
			routingResultIdx = many.length;
			many.push(start ? coordinates : coordinates);
		} else {
			routingResultIdx = position;
		}
		if (start) {
			tourConcatenation.oneRoutingResultIdx = routingResultIdx;
		} else {
			tourConcatenation.manyRoutingResultIdx = routingResultIdx;
		}
	};
	addCoordinates(true, tourConcatenation, startMany, tourConcatenation.getStartCoordinates());
	addCoordinates(false, tourConcatenation, targetMany, tourConcatenation.getTargetCoordinates());
}

type StartTimesWithDuration = {
	possibleStartTimes: Interval[];
	duration: number;
};

export enum TourConcatenationType {
	NEW_TOUR,
	BETWEEN_EVENTS,
	BETWEEN_EVENTS_PAIR
}

export class TourConcatenation {
	constructor(companyId: number, toIdx: number, type: TourConcatenationType) {
		this.companyId = companyId;
		this.toIdx = toIdx;
		this.oneRoutingResultIdx = undefined;
		this.manyRoutingResultIdx = undefined;
		this.fullTravelDuration = undefined;
		this.type = type;
	}
	companyId: number;
	toIdx: number;
	oneRoutingResultIdx: number | undefined;
	manyRoutingResultIdx: number | undefined;
	fullTravelDuration: number | undefined;
	type: TourConcatenationType;
	getStartCoordinates = (): Coordinates => {
		return new Coordinates(0, 0);
	};
	getTargetCoordinates = (): Coordinates => {
		return new Coordinates(0, 0);
	};
	getValidStarts(startFixed: boolean, availabilities: Interval[], arrivalTimes: Date[][]) {
		const PASSENGER_MAX_WAITING_TIME = minutesToMs(20);
		const validStarts = new Array<StartTimesWithDuration>(arrivalTimes.length);
		const times = arrivalTimes[this.toIdx];
		for (let t = 0; t != arrivalTimes.length; ++t) {
			const time = times[t];
			const searchInterval = startFixed
				? new Interval(new Date(time.getTime() - PASSENGER_MAX_WAITING_TIME), time)
				: new Interval(time, new Date(time.getTime() + PASSENGER_MAX_WAITING_TIME));
			const relevantAvailabilities = availabilities
				.filter((a) => a.size() >= this.fullTravelDuration!)
				.filter((a) => a.overlaps(searchInterval))
				.map((a) => (a.contains(searchInterval) ? a : a.cut(searchInterval)));
			if (relevantAvailabilities.length == 0) {
				validStarts[t] = {
					possibleStartTimes: [],
					duration: 0
				};
				continue;
			}
		}
		return validStarts;
	}
}

class NewTour extends TourConcatenation {
	constructor(companyId: number, toIdx: number, coordinates: Coordinates) {
		super(companyId, toIdx, TourConcatenationType.NEW_TOUR);
		this.coordinates = coordinates;
	}
	coordinates: Coordinates;
	getStartCoordinates = (): Coordinates => {
		return this.coordinates;
	};
	getTargetCoordinates = (): Coordinates => {
		return this.coordinates;
	};
}

class BetweenEvents extends TourConcatenation {
	constructor(event1: Event, event2: Event, companyId: number, vehicleId: number) {
		super(companyId, 1, TourConcatenationType.BETWEEN_EVENTS);
		this.event1 = event1;
		this.event2 = event2;
		this.vehicleId = vehicleId;
	}
	event1: Event;
	event2: Event;
	vehicleId: number;
	getStartCoordinates = (): Coordinates => {
		return this.event1.coordinates;
	};
	getTargetCoordinates = (): Coordinates => {
		return this.event2.coordinates;
	};
}

class BetweenEventsPair extends TourConcatenation {
	constructor(
		insertion1: BetweenEvents,
		insertion2: BetweenEvents,
		companyId: number,
		vehicleId: number,
		toIdx: number
	) {
		super(companyId, toIdx, TourConcatenationType.BETWEEN_EVENTS_PAIR);
		this.pickupInsertion = insertion1;
		this.dropoffInsertion = insertion2;
		this.vehicleId = vehicleId;
	}
	vehicleId: number;
	pickupInsertion: BetweenEvents;
	dropoffInsertion: BetweenEvents;
}

export class TourConcatenations {
	constructor() {
		this.concatenations = [];
		this.startMany = [];
		this.targetMany = [];
	}
	concatenations: TourConcatenation[];
	startMany: Coordinates[];
	targetMany: Coordinates[];

	cmpFullTravelDurations = (
		durationStart: number[],
		durationsTargets: number[][],
		travelDurations: number[]
	) => {
		this.concatenations.forEach((tc) => {
			tc.fullTravelDuration =
				durationStart[tc.oneRoutingResultIdx!] +
				durationsTargets[tc.toIdx][tc.manyRoutingResultIdx!] +
				travelDurations[tc.toIdx];
		});
	};

	createTourConcatenations = (companies: Company[], requiredCapacity: Capacity) => {
		this.concatenations = companies.map((c) => new NewTour(c.id, 1, c.coordinates));
		forEachVehicle(companies, (c, v) => {
			let allEvents: Event[] = [];
			v.tours.forEach((t) => (allEvents = allEvents.concat(t.events)));
			if (allEvents.length == 0) {
				return;
			}
			const simulation = new CapacitySimulation(
				v.bike_capacity,
				v.wheelchair_capacity,
				v.seats,
				v.storage_space
			);
			let validEventInsertions: Range[] = simulation.getPossibleInsertionIntervals(
				allEvents,
				requiredCapacity
			);
			const isInsertionAfterEventPossible = new Map<number, boolean>();
			validEventInsertions.forEach((insertion) => {
				insertion.forEachEventTuple(allEvents, (prevEvent1, nextEvent1, prevEvent2, nextEvent2) => {
					if (!isInsertionAfterEventPossible.has(prevEvent1.id)) {
						isInsertionAfterEventPossible.set(
							prevEvent1.id,
							isInsertionPossible(prevEvent1, nextEvent1)
						);
					}
					if (!isInsertionAfterEventPossible.get(prevEvent1.id)) {
						return;
					}
					if (prevEvent1.id == prevEvent2.id) {
						this.concatenations.push(new BetweenEvents(prevEvent1, nextEvent1, c.id, v.id));
						return;
					}
					this.concatenations.push(
						new BetweenEventsPair(
							new BetweenEvents(prevEvent1, nextEvent1, c.id, v.id),
							new BetweenEvents(prevEvent2, nextEvent2, c.id, v.id),
							c.id,
							v.id,
							1
						)
					);
				});
			});
		});
	};

	addCoordinates() {
		this.concatenations.forEach((t) => {
			addTourConcatCoordinates(t, this.startMany, this.targetMany);
		});
	}
}
