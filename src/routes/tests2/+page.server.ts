import type { PageServerLoad } from './$types';
import { db } from '$lib/server/db';
import { sql } from 'kysely';
import type { Translations } from '$lib/i18n/translation';
import { getToursWithRequests } from '$lib/server/db/getTours';

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
