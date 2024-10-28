import { describe, it, expect } from 'vitest';
import { Coordinates } from '$lib/location';
import type { Vehicle, Event } from '$lib/compositionTypes';
import { type RoutingResults } from './routing';
import { Interval } from '$lib/interval';
import { getApproachDuration, getReturnDuration } from './durations';
import {
	InsertDirection,
	InsertHow,
	InsertWhat,
	InsertWhere,
	type InsertionInfo,
	type InsertionType
} from './insertionTypes';
import { MAX_TRAVEL_DURATION } from '$lib/constants';

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
		time: new Interval(new Date(), new Date())
	};
};

describe('getApproach and getReturn - duration tests', () => {
	it('insert both before first event, direction: TO_BUS', () => {
		const insertionCase: InsertionType = {
			how: InsertHow.PREPEND,
			direction: InsertDirection.TO_BUS_STOP,
			where: InsertWhere.BEFORE_FIRST_EVENT,
			what: InsertWhat.BOTH
		};
		const routingResults: RoutingResults = {
			userChosen: {
				fromCompany: [
					{
						duration: 1,
						distance: 0
					}
				],
				toCompany: [
					{
						duration: 2,
						distance: 0
					}
				],
				fromPrevEvent: [
					{
						duration: 3,
						distance: 0
					}
				],
				toNextEvent: [
					{
						duration: 4,
						distance: 0
					}
				]
			},
			busStops: [
				{
					fromCompany: [
						{
							duration: 5,
							distance: 0
						}
					],
					toCompany: [
						{
							duration: 6,
							distance: 0
						}
					],
					fromPrevEvent: [
						{
							duration: 7,
							distance: 0
						}
					],
					toNextEvent: [
						{
							duration: 8,
							distance: 0
						}
					]
				},
				{
					fromCompany: [
						{
							duration: 9,
							distance: 0
						}
					],
					toCompany: [
						{
							duration: 10,
							distance: 0
						}
					],
					fromPrevEvent: [
						{
							duration: 11,
							distance: 0
						}
					],
					toNextEvent: [
						{
							duration: 12,
							distance: 0
						}
					]
				}
			]
		};
		const insertionInfo: InsertionInfo = {
			companyIdx: 0,
			prevEventIdxInRoutingResults: -1,
			nextEventIdxInRoutingResults: 0,
			vehicle: createVehicle(1, [createEvent(2), createEvent(3)]),
			insertionIdx: 7,
			currentRange: {
				earliestPickup: -5,
				latestDropoff: -5
			}
		};

		const approach1 = getApproachDuration(
			insertionCase,
			routingResults,
			insertionInfo,
			0,
			createEvent(4)
		);
		expect(approach1).toBe(240001);
		const return1 = getReturnDuration(
			insertionCase,
			routingResults,
			insertionInfo,
			0,
			createEvent(4)
		);
		expect(return1).toBe(360008);
		const return2 = getReturnDuration(
			insertionCase,
			routingResults,
			insertionInfo,
			1,
			createEvent(4)
		);
		expect(return2).toBe(360012);
	});
	it('insert both before first event, direction: FROM_BUS', () => {
		const insertionCase: InsertionType = {
			how: InsertHow.PREPEND,
			direction: InsertDirection.FROM_BUS_STOP,
			where: InsertWhere.BEFORE_FIRST_EVENT,
			what: InsertWhat.BOTH
		};
		const routingResults: RoutingResults = {
			userChosen: {
				fromCompany: [
					{
						duration: 1,
						distance: 0
					}
				],
				toCompany: [
					{
						duration: 2,
						distance: 0
					}
				],
				fromPrevEvent: [
					{
						duration: 3,
						distance: 0
					}
				],
				toNextEvent: [
					{
						duration: 4,
						distance: 0
					}
				]
			},
			busStops: [
				{
					fromCompany: [
						{
							duration: 5,
							distance: 0
						}
					],
					toCompany: [
						{
							duration: 6,
							distance: 0
						}
					],
					fromPrevEvent: [
						{
							duration: 7,
							distance: 0
						}
					],
					toNextEvent: [
						{
							duration: 8,
							distance: 0
						}
					]
				},
				{
					fromCompany: [
						{
							duration: 9,
							distance: 0
						}
					],
					toCompany: [
						{
							duration: 10,
							distance: 0
						}
					],
					fromPrevEvent: [
						{
							duration: 11,
							distance: 0
						}
					],
					toNextEvent: [
						{
							duration: 12,
							distance: 0
						}
					]
				}
			]
		};
		const insertionInfo: InsertionInfo = {
			companyIdx: 0,
			prevEventIdxInRoutingResults: -1,
			nextEventIdxInRoutingResults: 0,
			vehicle: createVehicle(1, [createEvent(2), createEvent(3)]),
			insertionIdx: 1,
			currentRange: {
				earliestPickup: -5,
				latestDropoff: -5
			}
		};

		const approach1 = getApproachDuration(
			insertionCase,
			routingResults,
			insertionInfo,
			0,
			createEvent(4)
		);
		expect(approach1).toBe(240005);
		const approach2 = getApproachDuration(
			insertionCase,
			routingResults,
			insertionInfo,
			1,
			createEvent(4)
		);
		expect(approach2).toBe(240009);
		const return1 = getReturnDuration(
			insertionCase,
			routingResults,
			insertionInfo,
			0,
			createEvent(4)
		);
		expect(return1).toBe(360004);
	});
	it('insert before first event, no predecessor', () => {
		const insertionCase: InsertionType = {
			how: InsertHow.PREPEND,
			direction: InsertDirection.FROM_BUS_STOP,
			where: InsertWhere.BEFORE_FIRST_EVENT,
			what: InsertWhat.BOTH
		};
		const routingResults: RoutingResults = {
			userChosen: {
				fromCompany: [
					{
						duration: 1,
						distance: 0
					}
				],
				toCompany: [
					{
						duration: 2,
						distance: 0
					}
				],
				fromPrevEvent: [
					{
						duration: 3,
						distance: 0
					}
				],
				toNextEvent: [
					{
						duration: 4,
						distance: 0
					}
				]
			},
			busStops: [
				{
					fromCompany: [
						{
							duration: 5,
							distance: 0
						}
					],
					toCompany: [
						{
							duration: 6,
							distance: 0
						}
					],
					fromPrevEvent: [
						{
							duration: 7,
							distance: 0
						}
					],
					toNextEvent: [
						{
							duration: 8,
							distance: 0
						}
					]
				},
				{
					fromCompany: [
						{
							duration: 9,
							distance: 0
						}
					],
					toCompany: [
						{
							duration: 10,
							distance: 0
						}
					],
					fromPrevEvent: [
						{
							duration: 11,
							distance: 0
						}
					],
					toNextEvent: [
						{
							duration: 12,
							distance: 0
						}
					]
				}
			]
		};
		const insertionInfo: InsertionInfo = {
			companyIdx: 0,
			prevEventIdxInRoutingResults: -1,
			nextEventIdxInRoutingResults: 0,
			vehicle: createVehicle(1, [createEvent(2), createEvent(3)]),
			insertionIdx: 1,
			currentRange: {
				earliestPickup: -5,
				latestDropoff: -5
			}
		};

		const approach1 = getApproachDuration(
			insertionCase,
			routingResults,
			insertionInfo,
			0,
			undefined
		);
		expect(approach1).toBe(MAX_TRAVEL_DURATION);
	});
	it('insert both after last event, direction: to_bus', () => {
		const insertionCase: InsertionType = {
			how: InsertHow.APPEND,
			direction: InsertDirection.TO_BUS_STOP,
			where: InsertWhere.AFTER_LAST_EVENT,
			what: InsertWhat.BOTH
		};
		const routingResults: RoutingResults = {
			userChosen: {
				fromCompany: [
					{
						duration: 1,
						distance: 0
					}
				],
				toCompany: [
					{
						duration: 2,
						distance: 0
					}
				],
				fromPrevEvent: [
					{
						duration: 3,
						distance: 0
					}
				],
				toNextEvent: [
					{
						duration: 4,
						distance: 0
					}
				]
			},
			busStops: [
				{
					fromCompany: [
						{
							duration: 5,
							distance: 0
						}
					],
					toCompany: [
						{
							duration: 6,
							distance: 0
						}
					],
					fromPrevEvent: [
						{
							duration: 7,
							distance: 0
						}
					],
					toNextEvent: [
						{
							duration: 8,
							distance: 0
						}
					]
				},
				{
					fromCompany: [
						{
							duration: 9,
							distance: 0
						}
					],
					toCompany: [
						{
							duration: 10,
							distance: 0
						}
					],
					fromPrevEvent: [
						{
							duration: 11,
							distance: 0
						}
					],
					toNextEvent: [
						{
							duration: 12,
							distance: 0
						}
					]
				}
			]
		};
		const insertionInfo: InsertionInfo = {
			companyIdx: 0,
			prevEventIdxInRoutingResults: 0,
			nextEventIdxInRoutingResults: 0,
			vehicle: createVehicle(1, [createEvent(2), createEvent(3)]),
			insertionIdx: 1,
			currentRange: {
				earliestPickup: -5,
				latestDropoff: -5
			}
		};

		const approach1 = getApproachDuration(
			insertionCase,
			routingResults,
			insertionInfo,
			0,
			createEvent(4)
		);
		expect(approach1).toBe(240003);
		const return1 = getReturnDuration(
			insertionCase,
			routingResults,
			insertionInfo,
			0,
			createEvent(4)
		);
		expect(return1).toBe(360006);
		const return2 = getReturnDuration(
			insertionCase,
			routingResults,
			insertionInfo,
			1,
			createEvent(4)
		);
		expect(return2).toBe(360010);
	});
	it('insert both after last event, direction: from_bus', () => {
		const insertionCase: InsertionType = {
			how: InsertHow.APPEND,
			direction: InsertDirection.FROM_BUS_STOP,
			where: InsertWhere.AFTER_LAST_EVENT,
			what: InsertWhat.BOTH
		};
		const routingResults: RoutingResults = {
			userChosen: {
				fromCompany: [
					{
						duration: 1,
						distance: 0
					}
				],
				toCompany: [
					{
						duration: 2,
						distance: 0
					}
				],
				fromPrevEvent: [
					{
						duration: 3,
						distance: 0
					}
				],
				toNextEvent: [
					{
						duration: 4,
						distance: 0
					}
				]
			},
			busStops: [
				{
					fromCompany: [
						{
							duration: 5,
							distance: 0
						}
					],
					toCompany: [
						{
							duration: 6,
							distance: 0
						}
					],
					fromPrevEvent: [
						{
							duration: 7,
							distance: 0
						}
					],
					toNextEvent: [
						{
							duration: 8,
							distance: 0
						}
					]
				},
				{
					fromCompany: [
						{
							duration: 9,
							distance: 0
						}
					],
					toCompany: [
						{
							duration: 10,
							distance: 0
						}
					],
					fromPrevEvent: [
						{
							duration: 11,
							distance: 0
						}
					],
					toNextEvent: [
						{
							duration: 12,
							distance: 0
						}
					]
				}
			]
		};
		const insertionInfo: InsertionInfo = {
			companyIdx: 0,
			prevEventIdxInRoutingResults: 0,
			nextEventIdxInRoutingResults: 0,
			vehicle: createVehicle(1, [createEvent(2), createEvent(3)]),
			insertionIdx: 1,
			currentRange: {
				earliestPickup: -5,
				latestDropoff: -5
			}
		};

		const approach1 = getApproachDuration(
			insertionCase,
			routingResults,
			insertionInfo,
			0,
			createEvent(4)
		);
		expect(approach1).toBe(240007);
		const approach2 = getApproachDuration(
			insertionCase,
			routingResults,
			insertionInfo,
			1,
			createEvent(4)
		);
		expect(approach2).toBe(240011);
		const return1 = getReturnDuration(
			insertionCase,
			routingResults,
			insertionInfo,
			0,
			createEvent(4)
		);
		expect(return1).toBe(360002);
	});
	it('insert both after last event, no successor', () => {
		const insertionCase: InsertionType = {
			how: InsertHow.APPEND,
			direction: InsertDirection.FROM_BUS_STOP,
			where: InsertWhere.AFTER_LAST_EVENT,
			what: InsertWhat.BOTH
		};
		const routingResults: RoutingResults = {
			userChosen: {
				fromCompany: [
					{
						duration: 1,
						distance: 0
					}
				],
				toCompany: [
					{
						duration: 2,
						distance: 0
					}
				],
				fromPrevEvent: [
					{
						duration: 3,
						distance: 0
					}
				],
				toNextEvent: [
					{
						duration: 4,
						distance: 0
					}
				]
			},
			busStops: [
				{
					fromCompany: [
						{
							duration: 5,
							distance: 0
						}
					],
					toCompany: [
						{
							duration: 6,
							distance: 0
						}
					],
					fromPrevEvent: [
						{
							duration: 7,
							distance: 0
						}
					],
					toNextEvent: [
						{
							duration: 8,
							distance: 0
						}
					]
				},
				{
					fromCompany: [
						{
							duration: 9,
							distance: 0
						}
					],
					toCompany: [
						{
							duration: 10,
							distance: 0
						}
					],
					fromPrevEvent: [
						{
							duration: 11,
							distance: 0
						}
					],
					toNextEvent: [
						{
							duration: 12,
							distance: 0
						}
					]
				}
			]
		};
		const insertionInfo: InsertionInfo = {
			companyIdx: 0,
			prevEventIdxInRoutingResults: 0,
			nextEventIdxInRoutingResults: 0,
			vehicle: createVehicle(1, [createEvent(2), createEvent(3)]),
			insertionIdx: 1,
			currentRange: {
				earliestPickup: -5,
				latestDropoff: -5
			}
		};

		const approach1 = getApproachDuration(
			insertionCase,
			routingResults,
			insertionInfo,
			0,
			undefined
		);
		expect(approach1).toBe(MAX_TRAVEL_DURATION);
	});
	it('insert bus after last event', () => {
		const insertionCase: InsertionType = {
			how: InsertHow.APPEND,
			direction: InsertDirection.FROM_BUS_STOP,
			where: InsertWhere.AFTER_LAST_EVENT,
			what: InsertWhat.BUS_STOP
		};
		const routingResults: RoutingResults = {
			userChosen: {
				fromCompany: [
					{
						duration: 1,
						distance: 0
					}
				],
				toCompany: [
					{
						duration: 2,
						distance: 0
					}
				],
				fromPrevEvent: [
					{
						duration: 3,
						distance: 0
					}
				],
				toNextEvent: [
					{
						duration: 4,
						distance: 0
					}
				]
			},
			busStops: [
				{
					fromCompany: [
						{
							duration: 5,
							distance: 0
						}
					],
					toCompany: [
						{
							duration: 6,
							distance: 0
						}
					],
					fromPrevEvent: [
						{
							duration: 7,
							distance: 0
						}
					],
					toNextEvent: [
						{
							duration: 8,
							distance: 0
						}
					]
				},
				{
					fromCompany: [
						{
							duration: 9,
							distance: 0
						}
					],
					toCompany: [
						{
							duration: 10,
							distance: 0
						}
					],
					fromPrevEvent: [
						{
							duration: 11,
							distance: 0
						}
					],
					toNextEvent: [
						{
							duration: 12,
							distance: 0
						}
					]
				}
			]
		};
		const insertionInfo: InsertionInfo = {
			companyIdx: 0,
			prevEventIdxInRoutingResults: 0,
			nextEventIdxInRoutingResults: 0,
			vehicle: createVehicle(1, [createEvent(2), createEvent(3)]),
			insertionIdx: 1,
			currentRange: {
				earliestPickup: 1,
				latestDropoff: 1
			}
		};

		const approach1 = getApproachDuration(
			insertionCase,
			routingResults,
			insertionInfo,
			0,
			createEvent(4)
		);
		expect(approach1).toBe(240007);
		const approach2 = getApproachDuration(
			insertionCase,
			routingResults,
			insertionInfo,
			1,
			createEvent(4)
		);
		expect(approach2).toBe(240011);
		const return1 = getReturnDuration(
			insertionCase,
			routingResults,
			insertionInfo,
			0,
			createEvent(4)
		);
		expect(return1).toBe(360006);
		const return2 = getReturnDuration(
			insertionCase,
			routingResults,
			insertionInfo,
			1,
			createEvent(4)
		);
		expect(return2).toBe(360010);
	});
	it('insert user chosen after last event', () => {
		const insertionCase: InsertionType = {
			how: InsertHow.APPEND,
			direction: InsertDirection.FROM_BUS_STOP,
			where: InsertWhere.AFTER_LAST_EVENT,
			what: InsertWhat.USER_CHOSEN
		};
		const routingResults: RoutingResults = {
			userChosen: {
				fromCompany: [
					{
						duration: 1,
						distance: 0
					}
				],
				toCompany: [
					{
						duration: 2,
						distance: 0
					}
				],
				fromPrevEvent: [
					{
						duration: 3,
						distance: 0
					}
				],
				toNextEvent: [
					{
						duration: 4,
						distance: 0
					}
				]
			},
			busStops: [
				{
					fromCompany: [
						{
							duration: 5,
							distance: 0
						}
					],
					toCompany: [
						{
							duration: 6,
							distance: 0
						}
					],
					fromPrevEvent: [
						{
							duration: 7,
							distance: 0
						}
					],
					toNextEvent: [
						{
							duration: 8,
							distance: 0
						}
					]
				},
				{
					fromCompany: [
						{
							duration: 9,
							distance: 0
						}
					],
					toCompany: [
						{
							duration: 10,
							distance: 0
						}
					],
					fromPrevEvent: [
						{
							duration: 11,
							distance: 0
						}
					],
					toNextEvent: [
						{
							duration: 12,
							distance: 0
						}
					]
				}
			]
		};
		const insertionInfo: InsertionInfo = {
			companyIdx: 0,
			prevEventIdxInRoutingResults: 0,
			nextEventIdxInRoutingResults: 0,
			vehicle: createVehicle(1, [createEvent(2), createEvent(3)]),
			insertionIdx: 1,
			currentRange: {
				earliestPickup: 1,
				latestDropoff: 1
			}
		};

		const approach1 = getApproachDuration(
			insertionCase,
			routingResults,
			insertionInfo,
			0,
			createEvent(4)
		);
		expect(approach1).toBe(240003);
		const return1 = getReturnDuration(
			insertionCase,
			routingResults,
			insertionInfo,
			0,
			createEvent(4)
		);
		expect(return1).toBe(360002);
	});
});
