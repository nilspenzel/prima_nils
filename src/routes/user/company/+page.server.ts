import type { PageServerLoad, Actions } from './$types.js';
import { fail } from '@sveltejs/kit';
import { db } from '$lib/database';
import { Coordinates } from '$lib/location.js';
import { covers, intersects } from '$lib/sqlHelpers.js';
import { bookingApiQuery22 } from '../../api/booking/query.js';
import { geocode } from '$lib/motis/services.gen.js';
import { MOTIS_BASE_URL } from '$lib/constants.js';
import type { GeocodeResponse } from '$lib/motis/types.gen.js';

export const load: PageServerLoad = async (event) => {
	//bookingApiQuery22();
	const companyId = event.locals.user?.company;
	const zones = await db
		.selectFrom('zone')
		.where('is_community', '=', false)
		.select(['id', 'name'])
		.orderBy('name')
		.execute();
	const communities = await db
		.selectFrom('zone')
		.where('is_community', '=', true)
		.select(['id', 'name'])
		.orderBy('name')
		.execute();
	const company = companyId
		? await db.selectFrom('company').where('id', '=', companyId).selectAll().executeTakeFirst()
		: {
				zone: null,
				latitude: null,
				longitude: null,
				name: null,
				community_area: null,
				street: null,
				house_number: null,
				postal_code: null,
				city: null
			};
	return {
		company,
		zones,
		communities
	};
};

export const actions = {
	default: async (event) => {
		const readInt = (x: FormDataEntryValue | null) => {
			return x === null ? NaN : parseInt(x.toString());
		};

		const companyId = event.locals.user!.company!;
		const data = await event.request.formData();
		const street = data.get('street')?.toString();
		const house_number = data.get('house_number')?.toString();
		const postal_code = data.get('postal_code')?.toString();
		const city = data.get('city')?.toString();
		const name = data.get('name')?.toString();
		const community_area = readInt(data.get('community_area'));
		const zone = readInt(data.get('zone'));

		if (!name || name.length < 2) {
			return fail(400, { error: 'Name zu kurz.' });
		}

		if (!street || street.length < 2) {
			return fail(400, { error: 'Straße zu kurz.' });
		}

		if (!city || city.length < 2) {
			return fail(400, { error: 'Stadt zu kurz.' });
		}

		if (!postal_code || postal_code.length < 2) {
			return fail(400, { error: 'Postleitzahl zu kurz.' });
		}

		if (isNaN(community_area) || community_area < 1) {
			return fail(400, { error: 'Gemeinde nicht gesetzt.' });
		}

		if (isNaN(zone) || zone < 1) {
			return fail(400, { error: 'Pflichtfahrgebiet nicht gesetzt.' });
		}

		const response: GeocodeResponse = await geocode({
			baseUrl: MOTIS_BASE_URL,
			query: {
				text: street + ' ' + house_number + ' ' + postal_code + ' ' + city
			}
		}).then((res) => {
			return res.data!;
		});
		if (response.length == 0) {
			return fail(400, { error: 'Die Addresse konnte nicht gefunden werden.' });
		}
		const bestAddressGuess = new Coordinates(response[0].lat, response[0].lon);

		if (!(await contains(community_area, bestAddressGuess))) {
			return fail(400, {
				error: 'Die Addresse liegt nicht in der ausgewählten Gemeinde.'
			});
		}

		if (!(await intersects(zone, community_area))) {
			return fail(400, {
				error: 'Die Gemeinde liegt nicht im Pflichtfahrgebiet.'
			});
		}

		await db
			.updateTable('company')
			.set({
				name,
				zone,
				community_area,
				street,
				house_number,
				postal_code,
				city,
				latitude: bestAddressGuess!.lat,
				longitude: bestAddressGuess!.lng
			})
			.where('id', '=', companyId)
			.execute();

		return { success: true };
	}
} satisfies Actions;

const contains = async (community: number, coordinates: Coordinates): Promise<boolean> => {
	return (
		(await db
			.selectFrom('zone')
			.where((eb) => eb.and([eb('zone.id', '=', community), covers(eb, coordinates!)]))
			.executeTakeFirst()) != undefined
	);
};
