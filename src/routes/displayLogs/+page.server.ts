import type { PageServerLoad } from './$types';
import { db } from '$lib/server/db';
import { sql } from 'kysely';
import {
	toWhitelistRequestWithISOStrings,
	toWhitelistResponseWithISOStrings,
	type WhitelistRequestWithISOStrings
} from '../api/whitelist/WhitelistRequest';
import type { ExpectedConnectionWithISoStrings } from '$lib/server/booking/bookRide';
import { isSamePlace } from '$lib/server/booking/isSamePlace';

const areasGeoJSON = async () => {
	return await sql`
		SELECT 'FeatureCollection' AS TYPE,
			array_to_json(array_agg(f)) AS features
		FROM
			(SELECT 'Feature' AS TYPE,
				ST_AsGeoJSON(lg.area, 15, 0)::json As geometry,
				json_build_object('id', id, 'name', name) AS properties
			FROM zone AS lg) AS f`.execute(db);
};

export const load: PageServerLoad = async () => {
	return {
		companies: await db.selectFrom('company').select(['id', 'lat', 'lng']).execute(),
		areas: (await areasGeoJSON()).rows[0]
	};
};

export const actions = {
	default: async ({ request, locals }) => {
		const formData = await request.formData();
		const text = formData.get('logs');
		const readData = detectAll(toFind, text);
		const blacklistParams: WhitelistRequestWithISOStrings = toWhitelistRequestWithISOStrings(
			readData[6]
		);
		const blacklistResponse: {
			startResponse: boolean[][];
			targetResponse: boolean[][];
			directResponse: boolean[];
		} = readData[5];
		const whitelistParams: WhitelistRequestWithISOStrings = toWhitelistRequestWithISOStrings(
			readData[4]
		);
		const whitelistResponse = toWhitelistResponseWithISOStrings(readData[3]);
		const bookingParams = readData[2];
		const booking1: ExpectedConnectionWithISoStrings | null = readData[1];
		const booking2: ExpectedConnectionWithISoStrings | null = readData[0];
		const info = {
			...blacklistParams,
			startBusStops: blacklistParams.startBusStops.map((bs, bi) => {
				return {
					...bs,
					responses: bs.times.map((t, ti) => {
						return {
							time: t,
							blr: blacklistResponse.startResponse[bi][ti]
						};
					}),
					wlr: whitelistResponse.start[
						whitelistParams.startBusStops.findIndex((b) => isSamePlace(b, bs))
					]?.map((b, i) => {
						return {
							...b,
							requestedTime: whitelistParams.startBusStops[whitelistParams.startBusStops.findIndex((b) => isSamePlace(b, bs))]?.times[i] ?? undefined
						}
					}),
				};
			}),
			targetBusStops: blacklistParams.targetBusStops.map((bs, bi) => {
				return {
					...bs,
					responses: bs.times.map((t, ti) => {
						return {
							time: t,
							blr: blacklistResponse.targetResponse[bi][ti]
						};
					}),
					wlr: whitelistResponse.target[
						whitelistParams.targetBusStops.findIndex((b) => isSamePlace(b, bs))
					]?.map((b, i) => {
						return {
							...b,
							requestedTime: whitelistParams.targetBusStops[whitelistParams.targetBusStops.findIndex((b) => isSamePlace(b, bs))]?.times[i] ?? undefined
						}
					}),
				};
			}),
			directTimesBlack: blacklistParams.directTimes.map((t, ti) => {
				return {
					time: t,
					blr: blacklistResponse.directResponse[ti]
				};
			}),
			directTimesWhite: whitelistParams.directTimes.map((t, ti) => {
				return {
					requestedTime: t,
					...whitelistResponse.direct[ti]
				}
			})
		};
		return { info, booking1 };
	}
};

function detect(start: string, end: string, text: string) {
	const a = text.lastIndexOf(start);
	const b = text.slice(a).indexOf(end) + a;
	return [a, b];
}

function detectAll(toFind: string[], text: string) {
	const result: any[] = [];
	toFind.forEach((f) => {
		const [a, b] = detect(f + 'START', f + 'END', text);
		result.push(JSON.parse(text.slice(a + (f + 'START').length, b)));
	});
	return result;
}

const toFind = [
	'BOOKING: C2=',
	'BOOKING: C1=',
	'BOOKING PARAMS =',
	'WHITELIST RESPONSE: ',
	'WHITELIST REQUEST PARAMS',
	'BLACKLIST RESPONSE: ',
	'BLACKLIST PARAMS: '
];
