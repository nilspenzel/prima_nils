import type { BusStop } from './busStop';
import type { Capacities } from './capacities';
import type { Coordinates, Location } from './location';

export type ExpectedConnection = {
	start: Location;
	target: Location;
	startTime: Date;
	targetTime: Date;
};

export type WhitelistRequest = {
	start: Coordinates;
	target: Coordinates;
	startBusStops: BusStop[];
	targetBusStops: BusStop[];
	times: Date[];
	startFixed: boolean;
	capacities: Capacities;
};

export type BookingRequest = {
	connection1: ExpectedConnection;
	connection2: ExpectedConnection | null;
	capacities: Capacities;
};

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
				passengers: { type: 'integer', minimum: 0 },
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
				startAddress: { type: 'string' },
				targetAddress: { type: 'string' }
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
		connection1: { $ref: '/schemaDefinitions#/definitions/connection' },
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
