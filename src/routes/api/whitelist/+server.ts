import { type InsertionEvaluation } from './insertions';
import type { RequestEvent } from './$types';
import { Validator } from 'jsonschema';
import {
	schemaDefinitions,
	whitelistSchema,
	type WhitelistRequest
} from '$lib/bookingApiParameters';
import { json } from '@sveltejs/kit';
import { white } from './whitelist';

export type WhitelistResponse = {
	start: (InsertionEvaluation | undefined)[][];
	target: (InsertionEvaluation | undefined)[][];
	direct: (InsertionEvaluation | undefined)[];
};

export async function POST(event: RequestEvent) {
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
	const parameters: WhitelistRequest = p;
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
	const start = await white(
		parameters.start,
		parameters.startBusStops,
		parameters.capacities,
		false
	);
	const target = await white(
		parameters.target,
		parameters.targetBusStops,
		parameters.capacities,
		true
	);
	const direct = parameters.startFixed ? target[target.length - 1] : start[start.length - 1];
	const response: WhitelistResponse = {
		start,
		target,
		direct
	};
	return json(response);
}
