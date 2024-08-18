import type { Event } from '$lib/compositionTypes.js';

export class Capacity {
	wheelchairs!: number;
	bikes!: number;
	passengers!: number;
	luggage!: number;
}

export class Range {
	constructor(earliest: number, latest: number) {
		this.earliestPickup = earliest;
		this.latestDropoff = latest;
	}
	earliestPickup: number;
	latestDropoff: number;

	forEachEventTuple<T>(
		events: Event[],
		fn: (prevEvent1: Event, nextEvent1: Event, prevEvent2: Event, nextEvent2: Event) => T
	) {
		for (let pickupIdx = this.earliestPickup; pickupIdx != this.latestDropoff; ++pickupIdx) {
			for (let dropoffIdx = pickupIdx; dropoffIdx != this.latestDropoff; ++dropoffIdx) {
				fn(events[pickupIdx], events[pickupIdx + 1], events[dropoffIdx], events[dropoffIdx + 1]);
			}
		}
	}
}

export class CapacitySimulation {
	constructor(
		bikeCapacity: number,
		wheelchairCapacity: number,
		seats: number,
		storageSpace: number
	) {
		this.bikeCapacity = bikeCapacity;
		this.wheelchairCapacity = wheelchairCapacity;
		this.seats = seats;
		this.storageSpace = storageSpace;
		this.bikes = 0;
		this.wheelchairs = 0;
		this.passengers = 0;
		this.luggage = 0;
	}
	private bikeCapacity: number;
	private wheelchairCapacity: number;
	private seats: number;
	private storageSpace: number;
	private bikes: number;
	private wheelchairs: number;
	private passengers: number;
	private luggage: number;

	private adjustValues(event: Event) {
		if (event.is_pickup) {
			this.bikes += event.bikes;
			this.wheelchairs += event.wheelchairs;
			this.passengers += event.passengers;
			this.luggage += event.luggage;
		} else {
			this.bikes -= event.bikes;
			this.wheelchairs -= event.wheelchairs;
			this.passengers -= event.passengers;
			this.luggage -= event.luggage;
		}
	}

	private addNewEvent(event: Capacity) {
		this.bikes += event.bikes;
		this.wheelchairs += event.wheelchairs;
		this.passengers += event.passengers;
		this.luggage += event.luggage;
	}

	private isValid(): boolean {
		return (
			this.bikeCapacity >= this.bikes &&
			this.wheelchairCapacity >= this.wheelchairs &&
			this.storageSpace + this.seats >= this.luggage + this.passengers &&
			this.seats >= this.passengers
		);
	}

	getPossibleInsertionIntervals = (events: Event[], toInsert: Capacity): Range[] => {
		const possibleInsertions = [];
		this.addNewEvent(toInsert);
		let earliestPickup: number | undefined = undefined;
		for (let i = 0; i != events.length; i++) {
			this.adjustValues(events[i]);
			if (!this.isValid()) {
				if (earliestPickup != undefined) {
					possibleInsertions.push(new Range(earliestPickup, i));
					earliestPickup = undefined;
				}
				continue;
			}
			earliestPickup = earliestPickup == undefined ? i + 1 : earliestPickup;
		}
		possibleInsertions.push(
			new Range(earliestPickup == undefined ? events.length : earliestPickup, events.length)
		);
		if (possibleInsertions.length != 0 && possibleInsertions[0].earliestPickup == 1) {
			possibleInsertions[0].earliestPickup = 0;
		} else {
			possibleInsertions.unshift(new Range(0, 0));
		}
		return possibleInsertions;
	};

	reset() {
		this.bikes = 0;
		this.wheelchairs = 0;
		this.passengers = 0;
		this.luggage = 0;
	}
}
