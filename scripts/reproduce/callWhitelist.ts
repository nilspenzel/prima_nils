#!/usr/bin/env ts-node

import 'dotenv/config';
import { whitelist } from '../../src/routes/api/whitelist/whitelist';
import { type WhitelistRequest } from '../../src/routes/api/whitelist/WhitelistRequest';
import { Insertion } from '../../src/lib/server/booking/insertion';

const params = {
	start: {
		lat: 51.5332486,
		lng: 14.5141138
	},
	target: {
		lat: 51.3280041,
		lng: 14.5841901
	},
	startBusStops: [],
	targetBusStops: [
		{
			lat: 51.50595500000001,
			lng: 14.479306000000001,
			times: [
				'2025-07-30T14:49:00.000Z',
				'2025-07-30T15:49:00.000Z',
				'2025-07-30T16:49:00.000Z',
				'2025-07-31T02:49:00.000Z',
				'2025-07-31T03:49:00.000Z',
				'2025-07-31T04:49:00.000Z',
				'2025-07-31T05:49:00.000Z',
				'2025-07-31T06:49:00.000Z',
				'2025-07-31T07:49:00.000Z',
				'2025-07-31T08:49:00.000Z',
				'2025-07-31T09:49:00.000Z',
				'2025-07-31T10:49:00.000Z',
				'2025-07-31T11:49:00.000Z',
				'2025-07-31T12:49:00.000Z',
				'2025-07-31T13:49:00.000Z',
				'2025-07-31T14:49:00.000Z',
				'2025-07-31T15:49:00.000Z'
			]
		}
	],
	directTimes: [],
	startFixed: true,
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
