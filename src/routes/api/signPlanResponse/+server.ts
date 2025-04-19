import { PUBLIC_MOTIS_URL } from '$env/static/public';
import { plan } from '$lib/openapi';
import { signEntry } from '$lib/server/signEntry';
import { json } from '@sveltejs/kit';
import type { RequestEvent } from './$types';
import type { QuerySerializerOptions } from '@hey-api/client-fetch';

export const POST = async (event: RequestEvent) => {
	const p = await event.request.json();
	const response = (
		await plan({
			baseUrl: PUBLIC_MOTIS_URL,
			querySerializer: { array: { explode: false } } as QuerySerializerOptions,
			query: p.query
		})
	).data;
	const data = {
		...response,
		itineraries: response?.itineraries.map((i) => {
			const odmLeg1 = i.legs.find((l) => l.mode === 'ODM');
			const odmLeg2 = i.legs.findLast((l) => l.mode === 'ODM');
			return {
				...i,
				signature1:
					odmLeg1 !== undefined
						? signEntry(
								odmLeg1.from.lat,
								odmLeg1.from.lon,
								odmLeg1.to.lat,
								odmLeg1.to.lon,
								new Date(odmLeg1.startTime).getTime(),
								new Date(odmLeg1.endTime).getTime(),
								false
							)
						: undefined,
				signature2:
					odmLeg2 !== undefined
						? signEntry(
								odmLeg2.from.lat,
								odmLeg2.from.lon,
								odmLeg2.to.lat,
								odmLeg2.to.lon,
								new Date(odmLeg2.startTime).getTime(),
								new Date(odmLeg2.endTime).getTime(),
								true
							)
						: undefined
			};
		})
	};
	return json({ data });
};
