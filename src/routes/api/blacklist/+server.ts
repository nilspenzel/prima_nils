import { Validator } from 'jsonschema';
import { getViableBusStops, type BlacklistingResult } from './viableBusStops';
import type { RequestEvent } from './$types';
import { json } from '@sveltejs/kit';
import { schemaDefinitions } from '$lib/server/booking/jsonSchemaDefinitions';
import {
	blacklistSchema,
	toBlacklistRequestWithISOStrings,
	type BlacklistRequest
} from './blacklistParameters';
import type { Coordinates } from '$lib/util/Coordinates';
import type { UnixtimeMs } from '$lib/util/UnixtimeMs';

export const POST = async (event: RequestEvent) => {
	// Validate parameters.
	const parameters: BlacklistRequest = await event.request.json();
	const validator = new Validator();
	validator.addSchema(schemaDefinitions, '/schemaDefinitions');
	const result = validator.validate(parameters, blacklistSchema);
	if (!result.valid) {
		return json({ message: result.errors }, { status: 400 });
	}

	console.log(
		'BLACKLIST PARAMS: ',
		JSON.stringify(toBlacklistRequestWithISOStrings(parameters), null, '\t')
	);

	// Add direct lookup to either start or target.
	if (parameters.startFixed) {
		parameters.targetBusStops.push(parameters.start);
	} else {
		parameters.startBusStops.push(parameters.target);
	}

	// Database lookup.
	const [start, target] = await Promise.all([
		getViableBusStops(
			parameters.start,
			parameters.startBusStops,
			parameters.capacities,
			parameters.earliest,
			parameters.latest
		),
		getViableBusStops(
			parameters.target,
			parameters.targetBusStops,
			parameters.capacities,
			parameters.earliest,
			parameters.latest
		)
	]);

	// Convert response.
	const createResponse = (allowedConnections: BlacklistingResult[], busStops: Coordinates[]) => {
		const response = Array.from({ length: busStops.length }, () =>
			Array<{ startTime: UnixtimeMs; endTime: UnixtimeMs }>()
		);
		allowedConnections.forEach((s) => {
			response[s.busStopIndex] = s.intervals;
		});
		return response;
	};
	let startResponse = createResponse(start, parameters.startBusStops);
	let targetResponse = createResponse(target, parameters.targetBusStops);

	// Extract direct response.
	const directResponse = parameters.startFixed
		? targetResponse[targetResponse.length - 1]
		: startResponse[startResponse.length - 1];
	if (parameters.startFixed) {
		targetResponse = targetResponse.slice(0, targetResponse.length - 1);
	} else {
		startResponse = startResponse.slice(0, startResponse.length - 1);
	}

	console.log('BLACKLIST RESPONSE: ', { startResponse, targetResponse, directResponse });
	return json({
		start: startResponse,
		target: targetResponse,
		direct: directResponse,
		...(parameters.uuid !== undefined && { uuid: parameters.uuid })
	});
};
