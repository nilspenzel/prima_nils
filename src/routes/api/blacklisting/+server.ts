import { Validator } from 'jsonschema';
import { getViableBusStops } from './viableBusStops';
import type { RequestEvent } from './$types';
import { json } from '@sveltejs/kit';
import { schemaDefinitions, whitelistSchema } from '$lib/bookingApiParameters';
import type { WhitelistRequest as BlacklistRequest } from '$lib/bookingApiParameters';

export const POST = async (event: RequestEvent) => {
	const p = await event.request.json();
	const validator = new Validator();
	validator.addSchema(schemaDefinitions, '/schemaDefinitions');
	const result = validator.validate(p, whitelistSchema);
	if (!result.valid) {
		return json(
			{
				message: result.errors
			},
			{ status: 400 }
		);
	}
	const parameters: BlacklistRequest = p;
	if (parameters.startFixed) {
		parameters.targetBusStops.push({
			coordinates: parameters.start,
			times: parameters.times
		});
	} else {
		parameters.startBusStops.push({
			coordinates: parameters.target,
			times: parameters.times
		});
	}
	const start = await getViableBusStops(
		parameters.start,
		parameters.startBusStops,
		false,
		parameters.capacities
	);
	const target = await getViableBusStops(
		parameters.target,
		parameters.targetBusStops,
		true,
		parameters.capacities
	);
	const direct = parameters.startFixed ? target[target.length - 1] : start[start.length - 1];
	const response = {
		start,
		target,
		direct
	};
	return json(response);
};
