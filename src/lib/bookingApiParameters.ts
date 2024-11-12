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

export const bookingSchema = {
	$schema: 'http://json-schema.org/draft-07/schema#',
	type: 'object',
	definitions: {
		coordinates: {
			type: 'object',
			properties: {
				lat: {
					type: 'number',
					minimum: -90,
					maximum: 90
				},
				lng: {
					type: 'number',
					minimum: -180,
					maximum: 180
				}
			},
			required: ['lat', 'lng']
		},
		location: {
			type: 'object',
			properties: {
				coordinates: {
					$ref: '#/definitions/coordinates'
				},
				address: {
					type: 'string'
				}
			}
		},
		times: {
			type: 'array',
			items: {
				type: 'string',
				format: 'date-time'
			}
		},
		connection: {
			type: 'object',
			properties: {
				start: {
					$ref: '#/definitions/location'
				},
				target: {
					$ref: '#/definitions/location'
				},
				startAddress: {
					type: 'string'
				},
				targetAddress: {
					type: 'string'
				}
			}
		}
	},
	properties: {
		connection1: {
			$ref: '#/definitions/connection'
		},
		connection2: {
			oneOf: [
				{ $ref: '#/definitions/connection' },
				{ type: 'null' }
			  ]
		},
		capacities: {
			type: 'object',
			properties: {
				passengers: {
					type: 'integer',
					minimum: 0
				},
				wheelchairs: {
					type: 'integer',
					minimum: 0
				},
				bikes: {
					type: 'integer',
					minimum: 0
				},
				luggage: {
					type: 'integer',
					minimum: 0
				}
			},
			required: ['passengers', 'wheelchairs', 'bikes', 'luggage']
		}
	},
	required: ['connection1', 'capacities']
};

export const whitelistSchema = {
	$schema: 'http://json-schema.org/draft-07/schema#',
	type: 'object',
	definitions: {
		coordinates: {
			type: 'object',
			properties: {
				lat: {
					type: 'number',
					minimum: -90,
					maximum: 90
				},
				lng: {
					type: 'number',
					minimum: -180,
					maximum: 180
				}
			},
			required: ['lat', 'lng']
		},
		times: {
			type: 'array',
			items: {
				type: 'string',
				format: 'date-time'
			}
		},
		busStops: {
			type: 'array',
			items: {
				type: 'object',
				properties: {
					coordinates: {
						$ref: '#/definitions/coordinates'
					},
					times: {
						$ref: '#/definitions/coordinates'
					}
				},
				required: ['coordinates', 'times']
			}
		}
	},
	properties: {
		start: {
			$ref: '#/definitions/coordinates'
		},
		target: {
			$ref: '#/definitions/coordinates'
		},
		startBusStops: {
			$ref: '#definitions/busStops'
		},
		targetBusStops: {
			$ref: '#definitions/busStops'
		},
		times: {
			$ref: '#definitions/times'
		},
		startFixed: {
			type: 'boolean'
		},
		capacities: {
			type: 'object',
			properties: {
				passengers: {
					type: 'integer',
					minimum: 0
				},
				wheelchairs: {
					type: 'integer',
					minimum: 0
				},
				bikes: {
					type: 'integer',
					minimum: 0
				},
				luggage: {
					type: 'integer',
					minimum: 0
				}
			},
			required: ['passengers', 'wheelchairs', 'bikes', 'luggage']
		}
	},
	required: ['userChosen', 'busStops', 'startFixed', 'capacities']
};
