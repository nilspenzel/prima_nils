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
import {
	toInsertionWithISOStrings as toRideShareInsertionWithISOStrings,
	type Insertion as RideShareInsertion
} from '$lib/server/rideShareBooking/insertion';
import { assertArraySizes } from '$lib/testHelpers';
import { whitelistRideShare } from './whitelistRideShare';

export type WhitelistResponse = {
	start: (Insertion | undefined)[][];
	target: (Insertion | undefined)[][];
	direct: (Insertion | undefined)[];
	startRideShare: (RideShareInsertion | undefined)[][];
	targetRideShare: (RideShareInsertion | undefined)[][];
	directRideShare: (RideShareInsertion | undefined)[];
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
	let directRideShare: (RideShareInsertion | undefined)[] = [];
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
	let [start, target, startRideShare, targetRideShare] = await Promise.all([
		whitelist(p.start, p.startBusStops, p.capacities, false),
		whitelist(p.target, p.targetBusStops, p.capacities, true),
		whitelistRideShare(p.start, p.startBusStops, p.capacities, false),
		whitelistRideShare(p.target, p.targetBusStops, p.capacities, true)
	]);

	assertArraySizes(start, p.startBusStops, 'Whitelist', false);
	assertArraySizes(target, p.targetBusStops, 'Whitelist', false);
	assertArraySizes(startRideShare, p.startBusStops, 'Whitelist', false);
	assertArraySizes(targetRideShare, p.targetBusStops, 'Whitelist', false);

	if (p.directTimes.length != 0) {
		direct = p.startFixed ? target[target.length - 1] : start[start.length - 1];
		directRideShare = p.startFixed
			? targetRideShare[targetRideShare.length - 1]
			: startRideShare[startRideShare.length - 1];
		if (p.startFixed) {
			target = target.slice(0, target.length - 1);
			targetRideShare = targetRideShare.slice(0, targetRideShare.length - 1);
		} else {
			start = start.slice(0, start.length - 1);
			startRideShare = startRideShare.slice(0, startRideShare.length - 1);
		}
	}

	console.assert(
		direct.length === p.directTimes.length,
		'Array size mismatch in Whitelist - direct.'
	);

	const response: WhitelistResponse = {
		start,
		target,
		direct,
		startRideShare,
		targetRideShare,
		directRideShare
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
