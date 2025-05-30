import type { Actions, PageServerLoad } from './$types';
import { db } from '$lib/server/db';
import { sql } from 'kysely';
import type { Translations } from '$lib/i18n/translation';
import { getToursWithRequests } from '$lib/server/db/getTours';
import { bookRide } from '$lib/server/booking/bookRide';
import { MINUTE } from '$lib/util/time';
import { jsonArrayFrom } from 'kysely/helpers/postgres';
import { InsertHow, InsertWhat } from '$lib/util/booking/insertionTypes';
import type { DebugInfo } from '$lib/server/util/debugInfo';

export type BookingError = { msg: keyof Translations['msg'] };

export const load: PageServerLoad = async () => {
	return {
		companies: await db
			.selectFrom('company')
			.select((eb) => [
				jsonArrayFrom(
					eb.selectFrom('vehicle').whereRef('vehicle.company', '=', 'company.id').select(['id'])
				).as('vehicles'),
				'id',
				'lat',
				'lng'
			])
			.execute(),
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
		const formData = await request.formData();
		const startLat = formData.get('startLat');
		const startLng = formData.get('startLng');
		const destinationLat = formData.get('destinationLat');
		const destinationLng = formData.get('destinationLng');
		const t = formData.get('time');
		const fixed = formData.get('startFixed');
		const v = formData.get('vehicle');
		const h = formData.get('how');
		const w = formData.get('what');
		const p = formData.get('prev');
		const n = formData.get('next');
		if (
			typeof startLat !== 'string' ||
			typeof startLng !== 'string' ||
			typeof destinationLat !== 'string' ||
			typeof destinationLng !== 'string' ||
			typeof fixed !== 'string' ||
			typeof t !== 'string' ||
			typeof v !== 'string' ||
			typeof h !== 'string' ||
			typeof w !== 'string' ||
			typeof p !== 'string' ||
			typeof n !== 'string'
		) {
			return { success: false, error: 'Invalid value' };
		}
		const start = { lat: parseFloat(startLat), lng: parseFloat(startLng) };
		const destination = { lat: parseFloat(destinationLat), lng: parseFloat(destinationLng) };
		const startFixed = fixed.toString().toLocaleLowerCase() === 'true';
		const time = new Date(t.toString()).getTime();
		const vehicleId = !v ? undefined : parseInt(v);
		let how: undefined | InsertHow = undefined;
		let what: undefined | InsertWhat = undefined;
		switch (h) {
			case 'CONNECT':
				how = InsertHow.CONNECT;
				break;
			case 'APPEND':
				how = InsertHow.APPEND;
				break;
			case 'PREPEND':
				how = InsertHow.PREPEND;
				break;
			case 'INSERT':
				how = InsertHow.INSERT;
				break;
			case 'NEW_TOUR':
				how = InsertHow.NEW_TOUR;
				break;
		}
		switch (w) {
			case 'USER_CHOSEN':
				what = InsertWhat.USER_CHOSEN;
				break;
			case 'BUS_STOP':
				what = InsertWhat.BUS_STOP;
				break;
			case 'BOTH':
				what = InsertWhat.BOTH;
				break;
		}
		const prevEventId = !p ? undefined : parseInt(p);
		const nextEventId = !n ? undefined : parseInt(n);
		const debugInfo = { vehicleId, how, what, prevEventId, nextEventId };
		console.log({ debugInfo }, { h }, { w });
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
			debugInfo
		);
	}
};
