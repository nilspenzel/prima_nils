#!/usr/bin/env ts-node

import 'dotenv/config';
import { whitelist } from '../../src/routes/api/whitelist/whitelist';
import { type WhitelistRequest } from '../../src/routes/api/whitelist/WhitelistRequest';
import { Insertion } from '../../src/lib/server/booking/insertion';

const params = {
	start: {
		lat: 51.5342031,
		lng: 14.5217853
	},
	target: {
		lat: 51.496103,
		lng: 14.7953534
	},
	startBusStops: [],
	targetBusStops: [],
	directTimes: [
		'2025-08-01T03:31:00.000Z',
		'2025-08-01T02:31:00.000Z',
		'2025-07-31T20:31:00.000Z',
		'2025-07-31T19:31:00.000Z',
		'2025-07-31T18:31:00.000Z',
		'2025-07-31T17:31:00.000Z',
		'2025-07-31T16:31:00.000Z',
		'2025-07-31T15:31:00.000Z',
		'2025-07-31T14:31:00.000Z',
		'2025-07-31T13:31:00.000Z',
		'2025-07-31T12:31:00.000Z',
		'2025-07-31T11:31:00.000Z',
		'2025-07-31T10:31:00.000Z',
		'2025-07-31T09:31:00.000Z',
		'2025-07-31T08:31:00.000Z',
		'2025-07-31T07:31:00.000Z',
		'2025-07-31T06:31:00.000Z',
		'2025-07-31T05:31:00.000Z',
		'2025-07-31T04:31:00.000Z',
		'2025-07-31T03:31:00.000Z'
	],
	startFixed: false,
	capacities: {
		wheelchairs: 0,
		bikes: 0,
		passengers: 1,
		luggage: 0
	}
};

async function main() {
	const p: WhitelistRequest = {
		...params,
		directTimes: params.directTimes.map((t) => new Date(t).getTime())
	};
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
	console.log('thingy', JSON.stringify(p, null, 2));
	let [start, target] = await Promise.all([
		whitelist(p.start, p.startBusStops, p.capacities, false),
		whitelist(p.target, p.targetBusStops, p.capacities, true)
	]);

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

	const response = {
		start,
		target,
		direct
	};
	console.log(JSON.stringify(response, null, 2));
}

main().catch((err) => {
	console.error('Error during booking:', err);
	process.exit(1);
});
