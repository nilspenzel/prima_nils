import type { PageServerLoad } from './$types.js';
import { db } from '$lib/database';
import { sql } from 'kysely';

export const load: PageServerLoad = async () => {
	const zones = await db
		.selectFrom('zone')
		.where('zone.is_community', '=', false)
		.select([sql<string>`ST_AsGeoJSON(ST_Boundary(zone.area::geometry))`.as('border')])
		.execute();
	const companies = await db
		.selectFrom('company')
		.select(['id', 'latitude', 'longitude'])
		.execute();
	return {
		drawBorders: true,
		zones,
		companies
	};
};
