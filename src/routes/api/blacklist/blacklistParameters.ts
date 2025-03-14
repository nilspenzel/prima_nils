import { t } from '$lib/i18n/translation';
import {
    toBusStopWithISOStrings,
    type BusStop,
    type BusStopWithISOStrings
} from '$lib/server/booking/BusStop';
import type { Capacities } from '$lib/server/booking/Capacities';
import type { Coordinates } from '$lib/util/Coordinates';
import type { UnixtimeMs } from '$lib/util/UnixtimeMs';

export type BlacklistRequest = {
    start: Coordinates;
    target: Coordinates;
    startBusStops: Coordinates[];
    targetBusStops: Coordinates[];
    earliest: number;
    latest: number;
    startFixed: boolean;
    capacities: Capacities;
};

export type BlacklistRequestWithISOStrings = {
    start: Coordinates;
    target: Coordinates;
    startBusStops: Coordinates[];
    targetBusStops: Coordinates[];
    earliest: string;
    latest: string;
    startFixed: boolean;
    capacities: Capacities;
};

export function toBlacklistRequestWithISOStrings(
    r: BlacklistRequest
): BlacklistRequestWithISOStrings {
    return {
        ...r,
        earliest: new Date(r.earliest).toISOString(),
        latest: new Date(r.latest).toISOString()
    };
}

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
    required: ['capacities']
};

export const BlacklistSchema = {
    $schema: 'http://json-schema.org/draft-07/schema#',
    type: 'object',
    properties: {
        start: { $ref: '/schemaDefinitions#/definitions/coordinates' },
        target: { $ref: '/schemaDefinitions#/definitions/coordinates' },
        startBusStops: { $ref: '/schemaDefinitions#/definitions/busStops' },
        targetBusStops: { $ref: '/schemaDefinitions#/definitions/busStops' },
        directTimes: { $ref: '/schemaDefinitions#/definitions/times' },
        startFixed: { type: 'boolean' },
        capacities: { $ref: '/schemaDefinitions#/definitions/capacities' }
    },
    required: [
        'start',
        'target',
        'startFixed',
        'capacities',
        'directTimes',
        'startBusStops',
        'targetBusStops'
    ]
};
