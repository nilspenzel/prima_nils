import type { RequestEvent } from './$types';
import { Validator } from 'jsonschema';
import { json } from '@sveltejs/kit';
import { whitelist } from './whitelist';
import {
	schemaDefinitions,
	toWhitelistRequestWithISOStrings,
	toWhitelistResponseWithISOStrings,
	whitelistSchema,
	type WhitelistRequest,
	type WhitelistResponse
} from './WhitelistRequest';
import { type Insertion } from '$lib/server/booking/insertion';
import { assertArraySizes } from '$lib/testHelpers';

export async function POST(event: RequestEvent) {
	const p: WhitelistRequest = await event.request.json();
	const validator = new Validator();
	validator.addSchema(schemaDefinitions, '/schemaDefinitions');
	const result = validator.validate(p, whitelistSchema);
	if (!result.valid) {
		return json({ message: result.errors }, { status: 400 });
	}

	console.log(
		'WHITELIST REQUEST PARAMSSTART',
		JSON.stringify(toWhitelistRequestWithISOStrings(p), null, '\t'),
		'WHITELIST REQUEST PARAMSEND'
	);
	let direct: (Insertion | undefined)[] = [];
	if (p.directTimes.length != 0) {
		if (p.startFixed) {
			p.targetBusStops.push({
				...p.start,
				times: p.directTimes
			});
		} else {
			p.startBusStops.push({
				...p.target,
				times: p.directTimes
			});
		}
	}
	let [start, target] = await Promise.all([
		whitelist(p.start, p.startBusStops, p.capacities, false),
		whitelist(p.target, p.targetBusStops, p.capacities, true)
	]);

	assertArraySizes(start, p.startBusStops, 'Whitelist', false);
	assertArraySizes(target, p.targetBusStops, 'Whitelist', false);

	if (p.directTimes.length != 0) {
		direct = p.startFixed ? target[target.length - 1] : start[start.length - 1];
		if (p.startFixed) {
			target = target.slice(0, target.length - 1);
		} else {
			start = start.slice(0, start.length - 1);
		}
	}

	console.assert(
		direct.length === p.directTimes.length,
		'Array size mismatch in Whitelist - direct.'
	);

	const response: WhitelistResponse = {
		start,
		target,
		direct
	};
	console.log(
		'WHITELIST RESPONSE: START',
		JSON.stringify(toWhitelistResponseWithISOStrings(response), null, '\t'),
		'WHITELIST RESPONSE: END'
	);
	return json(response);
}
