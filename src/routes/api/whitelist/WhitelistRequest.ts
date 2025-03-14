import {
	toBusStopWithISOStrings,
	type BusStop,
	type BusStopWithISOStrings
} from '$lib/server/booking/BusStop';
import type { Capacities } from '$lib/server/booking/Capacities';
import type { Coordinates } from '$lib/util/Coordinates';
import type { UnixtimeMs } from '$lib/util/UnixtimeMs';

export type WhitelistRequest = {
	start: Coordinates;
	target: Coordinates;
	startBusStops: BusStop[];
	targetBusStops: BusStop[];
	directTimes: UnixtimeMs[];
	startFixed: boolean;
	capacities: Capacities;
};

export type WhitelistRequestWithISOStrings = {
	start: Coordinates;
	target: Coordinates;
	startBusStops: BusStopWithISOStrings[];
	targetBusStops: BusStopWithISOStrings[];
	directTimes: string[];
	startFixed: boolean;
	capacities: Capacities;
};

export function toWhitelistRequestWithISOStrings(
	r: WhitelistRequest
): WhitelistRequestWithISOStrings {
	return {
		...r,
		startBusStops: r.startBusStops.map((b) => toBusStopWithISOStrings(b)),
		targetBusStops: r.targetBusStops.map((b) => toBusStopWithISOStrings(b)),
		directTimes: r.directTimes.map((t) => new Date(t).toISOString())
	};
}

export const whitelistSchema = {
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
