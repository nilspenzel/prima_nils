import { type InsertionEvaluation } from '$lib/bookingAPI/insertions';
import type { RequestEvent } from './$types';
import { Validator } from 'jsonschema';
import {
	schemaDefinitions,
	whitelistSchema,
	type WhitelistRequest
} from '$lib/bookingApiParameters';
import { json } from '@sveltejs/kit';
import { whitelist } from './whitelist';

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
	let start = await whitelist(
		parameters.start,
		parameters.startBusStops,
		parameters.capacities,
		false
	);
	let target = await whitelist(
		parameters.target,
		parameters.targetBusStops,
		parameters.capacities,
		true
	);
	const direct = parameters.startFixed ? target[target.length - 1] : start[start.length - 1];
	if (parameters.startFixed) {
		target = target.slice(0, target.length - 1);
	} else {
		start = start.slice(0, start.length - 1);
	}
	const response: WhitelistResponse = {
		start,
		target,
		direct
	};
	return json(response);
}
