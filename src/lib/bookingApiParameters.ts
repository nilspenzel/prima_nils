import type { BusStop, RequestBusStop } from './busStop';
import type { Capacities } from './capacities';
import { Coordinates, type Location } from './location';

export type RequestExpectedConnection = {
	start: Location;
	target: Location;
	startTime: string;
	targetTime: string;
};

export type ExpectedConnection = {
	start: Location;
	target: Location;
	startTime: Date;
	targetTime: Date;
};

export type WhitelistRequest = {
	start: Coordinates;
	target: Coordinates;
	startBusStops: RequestBusStop[];
	targetBusStops: RequestBusStop[];
	times: string[];
	startFixed: boolean;
	capacities: Capacities;
};

export type WhitelistParameters = {
	start: Coordinates;
	target: Coordinates;
	startBusStops: BusStop[];
	targetBusStops: BusStop[];
	times: Date[];
	startFixed: boolean;
	capacities: Capacities;
}

export function toWhitelistParameters(r: WhitelistRequest) {
	const stringsToDates = (strings: string[]): Date[] => {
		return strings.map((s) => new Date(s));
	}
	return {
		...r,
		startBusStops: r.startBusStops.map((bs) => {
			return {
				coordinates: bs.coordinates,
				times: stringsToDates(bs.times)
			};
		}),
		targetBusStops: r.targetBusStops.map((bs) => {
			return {
				coordinates: bs.coordinates,
				times: stringsToDates(bs.times)
			};
		}),
		times: stringsToDates(r.times)
	}
}

export type BookingRequest = {
	connection1: RequestExpectedConnection | null;
	connection2: RequestExpectedConnection | null;
	capacities: Capacities;
};

export type BookingParameters = {
	connection1: ExpectedConnection | null;
	connection2: ExpectedConnection | null;
	capacities: Capacities;
}

export function toBookingParameters(r: BookingRequest): BookingParameters {
	const toExpectedConnection = (r: RequestExpectedConnection|null) => {
		return r == null ? null : {
			...r,
			startTime: new Date(r.startTime),
			targetTime: new Date(r.targetTime)
		}
	};
	return {
		...r,
		connection1: toExpectedConnection(r.connection1),
		connection2: toExpectedConnection(r.connection2)
	}
}

export const schemaDefinitions = {
	$schema: 'http://json-schema.org/draft-07/schema#',
	definitions: {
		coordinates: {
			type: 'object',
			properties: {
				lat: { type: 'number', minimum: -90, maximum: 90 },
				lng: { type: 'number', minimum: -180, maximum: 180 }
			},
			required: ['lat', 'lng']
		},
		times: {
			type: 'array',
			items: { type: 'string', format: 'date-time' }
		},
		capacities: {
			type: 'object',
			properties: {
				passengers: { type: 'integer', minimum: 1 },
				wheelchairs: { type: 'integer', minimum: 0 },
				bikes: { type: 'integer', minimum: 0 },
				luggage: { type: 'integer', minimum: 0 }
			},
			required: ['passengers', 'wheelchairs', 'bikes', 'luggage']
		},
		location: {
			type: 'object',
			properties: {
				coordinates: { $ref: '#/definitions/coordinates' },
				address: { type: 'string' }
			}
		},
		connection: {
			type: 'object',
			properties: {
				start: { $ref: '#/definitions/location' },
				target: { $ref: '#/definitions/location' },
				startTime: { type: 'string', format: 'date-time' },
				targetTime: { type: 'string', format: 'date-time' }
			}
		},
		busStops: {
			type: 'array',
			items: {
				type: 'object',
				properties: {
					coordinates: { $ref: '#/definitions/coordinates' },
					times: { $ref: '#/definitions/times' }
				},
				required: ['coordinates', 'times']
			}
		}
	}
};

export const bookingSchema = {
	$schema: 'http://json-schema.org/draft-07/schema#',
	type: 'object',
	properties: {
		connection1: {
			oneOf: [{ $ref: '/schemaDefinitions#/definitions/connection' }, { type: 'null' }]
		},
		connection2: {
			oneOf: [{ $ref: '/schemaDefinitions#/definitions/connection' }, { type: 'null' }]
		},
		capacities: { $ref: '/schemaDefinitions#/definitions/capacities' }
	},
	required: ['connection1', 'capacities']
};

export const whitelistSchema = {
	$schema: 'http://json-schema.org/draft-07/schema#',
	type: 'object',
	properties: {
		start: { $ref: '/schemaDefinitions#/definitions/coordinates' },
		target: { $ref: '/schemaDefinitions#/definitions/coordinates' },
		startBusStops: { $ref: '/schemaDefinitions#/definitions/busStops' },
		targetBusStops: { $ref: '/schemaDefinitions#/definitions/busStops' },
		times: { $ref: '/schemaDefinitions#/definitions/times' },
		startFixed: { type: 'boolean' },
		capacities: { $ref: '/schemaDefinitions#/definitions/capacities' }
	},
	required: ['start', 'target', 'startFixed', 'capacities']
};
