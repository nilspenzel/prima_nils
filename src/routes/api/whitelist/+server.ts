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
import { PASSENGER_CHANGE_DURATION } from '$lib/constants';

export type WhitelistResponse = {
	start: (Insertion | undefined)[][];
	target: (Insertion | undefined)[][];
	direct: (Insertion | undefined)[];
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
		start: start.map((s1) =>
			s1.map((s2) => {
				return s2 === undefined
					? undefined
					: {
							...s2,
							pickupTime: s2.communicatedPickupTime,
							dropoffTime: s2.communicatedDropoffTime
						};
			})
		),
		target: target.map((t1) =>
			t1.map((t2) => {
				return t2 === undefined
					? undefined
					: {
							...t2,
							pickupTime: t2.communicatedPickupTime,
							dropoffTime: t2.communicatedDropoffTime
						};
			})
		),
		direct: direct.map((d) => {
			return d === undefined
				? undefined
				: {
						...d,
						pickupTime: d.communicatedPickupTime,
						dropoffTime: d.communicatedDropoffTime
					};
		})
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
