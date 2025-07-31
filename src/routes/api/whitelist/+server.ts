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
import { HOUR, MINUTE } from '$lib/util/time';

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
		start,
		target,
		direct: vaguelyOncePerHour(direct, p.directTimes)
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

interface ConsideredOption {
	insertions: { cost: number; idx: number; time: number }[];
	cost: number;
	toLookAt: { cost: number; idx: number; time: number }[];
}

function vaguelyOncePerHour(
	response: (Insertion | undefined)[],
	requestedTimes: number[]
): (Insertion | undefined)[] {
	const minGap = 40 * MINUTE;
	const maxGap = 80 * MINUTE;
	const beamWidth = 20;
	const maxValue = Number.MAX_SAFE_INTEGER / 2;
	const endOfFirstHour = (response[0]?.pickupTime ?? requestedTimes[0]) + HOUR;
	const options = response.map((r, idx) => {
		return { cost: r?.cost ?? maxValue, idx, time: r?.pickupTime ?? requestedTimes[idx] };
	});
	const firstHourInsertions = options.filter((r) => r.time < endOfFirstHour);
	let consideredOptions: ConsideredOption[] = firstHourInsertions.map((insertion) => ({
		insertions: [],
		cost: 0,
		toLookAt: [insertion]
	}));

	const finalOptions: ConsideredOption[] = [];

	while (consideredOptions.length > 0) {
		const nextOptions: ConsideredOption[] = [];

		for (const option of consideredOptions) {
			if (option.toLookAt.length === 0) {
				finalOptions.push(option);
			}
			for (const insertion of option.toLookAt) {
				const newInsertions = [...option.insertions, insertion];
				const newCost = option.cost + insertion.cost;

				const futureOptions = options.filter(
					(i) =>
						i.time > insertion.time + minGap &&
						i.time <= insertion.time + maxGap &&
						!newInsertions.includes(i)
				);

				const newOption: ConsideredOption = {
					insertions: newInsertions,
					cost: newCost,
					toLookAt: futureOptions
				};

				nextOptions.push(newOption);
			}
		}

		consideredOptions = nextOptions
			.sort((a, b) => a.cost / a.insertions.length - b.cost / b.insertions.length)
			.slice(0, beamWidth);

		//finalOptions.push(...consideredOptions.filter(o => o.toLookAt.length === 0));
	}

	const allCandidates = [...finalOptions];
	console.log({
		allCandidates: JSON.stringify(
			allCandidates.map((c) => {
				return { cost: c.cost, insertions: c.insertions.map((i) => i.idx) };
			})
		)
	});
	const best = allCandidates.reduce(
		(best, curr) => {
			if (!best) return curr;
			return curr.cost / curr.insertions.length < best.cost / best.insertions.length ? curr : best;
		},
		null as ConsideredOption | null
	);
	if (best === null) {
		console.log('unexpected null in vaguelyOncePerHour');
		throw new Error();
	}
	return response.map((r, idx) => (best.insertions.some((i) => i.idx === idx) ? r : undefined));
}
