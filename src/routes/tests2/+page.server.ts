import type { Actions, PageServerLoad } from './$types';
import { db } from '$lib/server/db';
import { sql } from 'kysely';
import type { Translations } from '$lib/i18n/translation';
import { getToursWithRequests } from '$lib/server/db/getTours';
import { bookRide } from '$lib/server/booking/bookRide';
import { MINUTE } from '$lib/util/time';
import { InsertHow, InsertWhat } from '$lib/server/booking/insertionTypes';

export type BookingError = { msg: keyof Translations['msg'] };

export const load: PageServerLoad = async () => {
	return {
		companies: await db.selectFrom('company').select(['id', 'lat', 'lng']).execute(),
		areas: (await areasGeoJSON()).rows[0],
		tours: await getToursWithRequests(false)
	};
};

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

export const actions: Actions = {
	default: async ({ request }) => {
		console.log("blabla")
		const formData = await request.formData();
		const startLat = formData.get('startLat');
		const startLng = formData.get('startLng');
		const destinationLat = formData.get('destinationLat');
		const destinationLng = formData.get('destinationLng');
		const t = formData.get('time');
		const fixed = formData.get('startFixed');
		const v = formData.get('vehicle');
console.log({t})
		if (
			typeof startLat !== 'string' ||
			typeof startLng !== 'string' ||
			typeof destinationLat !== 'string' ||
			typeof destinationLng !== 'string' ||
			typeof t !== 'string' ||
			typeof fixed !== 'string' ||
			typeof v !== 'string'
		) {
			return { success: false, error: 'Invalid value' };
		}
		const start = { lat: parseFloat(startLat), lng: parseFloat(startLng) };
		const destination = { lat: parseFloat(destinationLat), lng: parseFloat(destinationLng) };
		const startFixed = fixed.toString().toLocaleLowerCase() === 'true';
		const time = new Date(t.toString()).getTime();
		const vehicleId = parseInt(v);
console.log("doing book ride")
		await bookRide(
			{
				start,
				target: destination,
				startFixed,
				startTime: startFixed ? time : time - 20 * MINUTE,
				targetTime: startFixed ? time + 20 * MINUTE : time,
				signature: ''
			},
			{ passengers: 1, wheelchairs: 0, bikes: 0, luggage: 0 },
			undefined,
			true,
			undefined,
			{vehicleId, how: InsertHow.APPEND, what:InsertWhat.BOTH}
		);
console.log("didd book ride")
	}
};
