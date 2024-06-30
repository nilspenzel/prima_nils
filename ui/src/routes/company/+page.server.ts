import type { PageServerLoad, Actions } from './$types.js';
import { fail } from '@sveltejs/kit';
import { superValidate } from 'sveltekit-superforms';
import { zod } from 'sveltekit-superforms/adapters';
import { formSchema } from './schema';
import { db } from '$lib/database';
import { geoCode } from '$lib/api.js';

let company_id = 0;
company_id = 1;
export const load: PageServerLoad = async () => {
	const zones = db.selectFrom('zone').selectAll().execute();
	const company = db
		.selectFrom('company')
		.where('id', '=', company_id)
		.selectAll()
		.executeTakeFirst();
	return {
		form: await superValidate(zod(formSchema)),
		zones: await zones,
		company: company_id ? await company : undefined
	};
};

export const actions: Actions = {
	default: async (event) => {
		const form = await superValidate(event, zod(formSchema));
		if (!form.valid) {
			return fail(400, {
				form
			});
		}
		const name = form.data.companyname;
		const zone = form.data.zone;
		const community = form.data.community;
		const email = form.data.email;
		const address = form.data.address;
		const addressJson = await geoCode(address);
		if (addressJson.length == 0) {
			return fail(400, {
				form
			});
		}
		const latitude = addressJson[0].lat;
		const longitude = addressJson[0].lon;
		const zone_id = await db
			.selectFrom('zone')
			.where('name', '=', zone)
			.select('id')
			.executeTakeFirst();
		const community_id = await db
			.selectFrom('zone')
			.where('name', '=', community)
			.select('id')
			.executeTakeFirst();
		if (!zone_id || !community_id) {
			return;
		}
		if (company_id == 0) {
			db.insertInto('company')
				.values({
					display_name: name,
					email: email,
					zone: zone_id.id,
					community_area: community_id.id,
					latitude: latitude,
					longitude: longitude
				})
				.execute();
		} else {
			db.updateTable('company')
				.set({
					display_name: name,
					email: email,
					zone: zone_id.id,
					community_area: community_id.id,
					latitude: latitude,
					longitude: longitude
				})
				.where('id', '=', company_id)
				.execute();
		}
	}
};
