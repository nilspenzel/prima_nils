import type { RequestEvent } from './$types';
import { Validator } from 'jsonschema';
import { json } from '@sveltejs/kit';
import { whitelist } from './whitelist';
import {
	schemaDefinitions,
	toWhitelistRequestWithISOStrings,
	whitelistSchema,
	type WhitelistRequest
} from './WhitelistRequest';
import { toInsertionWithISOStrings, type Insertion } from '$lib/server/booking/insertion';
import { assertArraySizes } from '$lib/testHelpers';

export type WhitelistResponse = {
	start: ((Insertion & {sendTime: number}) | undefined)[][];
	target: ((Insertion & {sendTime: number}) | undefined)[][];
	direct: ((Insertion & {sendTime: number}) | undefined)[];
};

export async function POST(event: RequestEvent) {
	const p: WhitelistRequest = await event.request.json();
	const validator = new Validator();
	validator.addSchema(schemaDefinitions, '/schemaDefinitions');
	const result = validator.validate(p, whitelistSchema);
	if (!result.valid) {
		return json({ message: result.errors }, { status: 400 });
	}

	console.log(
		'WHITELIST REQUEST PARAMS',
		JSON.stringify(toWhitelistRequestWithISOStrings(p), null, '\t')
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
		start: start.map((s1, busIdx) => s1.map((s2, timeIdx) => {return{...s2, sendTime: p.startBusStops[busIdx].times[timeIdx]}})),
		target: target.map((t1, busIdx) => t1.map((t2, timeIdx) => {return{...t2, sendTime: p.targetBusStops[busIdx].times[timeIdx]}})),
		direct: direct.map((d1, timeIdx) => {return{...d1, sendTime: p.directTimes[timeIdx]}})
	};
	console.log(
		'WHITELIST RESPONSE: ',
		JSON.stringify(toWhitelistResponseWithISOStrings(response), null, '\t')
	);
	return json(response);
}

function toWhitelistResponseWithISOStrings(r: WhitelistResponse) {
	return {
		start: r.start.map((i) => i.map((j) => toInsertionWithISOStrings(j))),
		target: r.target.map((i) => i.map((j) => toInsertionWithISOStrings(j))),
		direct: r.direct.map((j) => toInsertionWithISOStrings(j))
	};
}
