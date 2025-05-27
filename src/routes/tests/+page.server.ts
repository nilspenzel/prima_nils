import type { PageServerLoad } from './$types';
import { db } from '$lib/server/db';
import { sql } from 'kysely';
import type { Translations } from '$lib/i18n/translation';
import fs from 'fs';
import path from 'path';
import type { Actions } from './$types';

export type BookingError = { msg: keyof Translations['msg'] };

export const load: PageServerLoad = async () => {
	return {
		companies: await db.selectFrom('company').select(['id', 'lat', 'lng']).execute(),
		areas: (await areasGeoJSON()).rows[0]
	};
};

export const actions: Actions = {
	default: async ({ request }) => {
		const formData = await request.formData();
		const value = formData.get('value');

		if (typeof value !== 'string') {
			return { success: false, error: 'Invalid value' };
		}

		const testFilePath = path.resolve('src/lib/testfile.ts'); // Adjust the path if needed
		const marker = '// printhere';

		let fileContent: string;
		try {
			fileContent = fs.readFileSync(testFilePath, 'utf-8');
		} catch (err) {
			return { success: false, error: 'Could not read file' };
		}

		const index = fileContent.indexOf(marker);
		if (index === -1) {
			return { success: false, error: 'Marker not found' };
		}

		const before = fileContent.slice(0, index + marker.length);
		const after = fileContent.slice(index + marker.length);
		const newContent = `${before}\n\t\t${JSON.stringify(value)},${after}`;

		try {
			fs.writeFileSync(testFilePath, newContent, 'utf-8');
		} catch (err) {
			return { success: false, error: 'Failed to write to file' };
		}

		return { success: true };
	}
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
