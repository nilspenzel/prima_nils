

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
			items: { type: 'integer' }
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
				lat: { type: 'number', minimum: -90, maximum: 90 },
				lng: { type: 'number', minimum: -180, maximum: 180 },
				address: { type: 'string' }
			},
			required: ['lat', 'lng', 'address']
		},
		connection: {
			type: 'object',
			properties: {
				start: { $ref: '#/definitions/location' },
				target: { $ref: '#/definitions/location' },
				startTime: { type: 'integer' },
				targetTime: { type: 'integer' }
			},
			required: ['start', 'target', 'startTime', 'targetTime']
		},
		busStops: {
			type: 'array',
			items: {
				type: 'object',
				properties: {
					lat: { type: 'number', minimum: -90, maximum: 90 },
					lng: { type: 'number', minimum: -180, maximum: 180 },
					times: { $ref: '#/definitions/times' }
				},
				required: ['lat', 'lng', 'times']
			}
		}
	}
};