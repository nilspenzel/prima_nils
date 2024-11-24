import type { PageServerLoad, Actions } from './$types.js';
import { fail, type RequestEvent } from '@sveltejs/kit';
import { db } from '$lib/database';
import { Coordinates } from '$lib/location.js';
import { covers, intersects } from '$lib/sqlHelpers.js';
import { geocode } from '$lib/motis/services.gen.js';
import { MOTIS_BASE_URL } from '$lib/constants.js';
import type { GeocodeResponse } from '$lib/motis/types.gen.js';
import {
	InsertDirection,
	InsertHow,
	InsertWhat,
	InsertWhere
} from '../../../lib/bookingAPI/insertionTypes.js';
import { insertRequest } from '../../api/booking/query.js';
import type { Capacities } from '$lib/capacities.js';
import type { BusStop } from '$lib/busStop.js';
import { wl } from '$lib/api.js';

export const load: PageServerLoad = async (event: RequestEvent) => {
	//clearDatabase();
	const capacities = {
		wheelchairs: 0,
		bikes: 0,
		passengers: 1,
		luggage: 0
	};
	const exp1 = {
		start: {
			coordinates: new Coordinates(1, 1),
			address: ''
		},
		target: {
			coordinates: new Coordinates(1, 1),
			address: ''
		},
		startTime: new Date(),
		targetTime: new Date()
	};
	const exp2 = {
		start: {
			coordinates: new Coordinates(1, 1),
			address: ''
		},
		target: {
			coordinates: new Coordinates(1, 1),
			address: ''
		},
		startTime: new Date(),
		targetTime: new Date()
	};
	const c1 = {
		pickupTime: new Date(),
		dropoffTime: new Date(),
		pickupCase: {
			how: InsertHow.APPEND,
			direction: InsertDirection.FROM_BUS_STOP,
			where: InsertWhere.AFTER_LAST_EVENT,
			what: InsertWhat.BOTH
		},
		dropoffCase: {
			how: InsertHow.APPEND,
			direction: InsertDirection.FROM_BUS_STOP,
			where: InsertWhere.AFTER_LAST_EVENT,
			what: InsertWhat.BOTH
		},
		taxiWaitingTime: 1,
		taxiDuration: 1,
		passengerDuration: 1,
		cost: 1,
		company: 92,
		vehicle: 92,
		tour: undefined,
		departure: new Date(),
		arrival: new Date(),
		mergeTourList: []
	};
	const c2 = {
		pickupTime: new Date(),
		dropoffTime: new Date(),
		pickupCase: {
			how: InsertHow.APPEND,
			direction: InsertDirection.FROM_BUS_STOP,
			where: InsertWhere.AFTER_LAST_EVENT,
			what: InsertWhat.BOTH
		},
		dropoffCase: {
			how: InsertHow.APPEND,
			direction: InsertDirection.FROM_BUS_STOP,
			where: InsertWhere.AFTER_LAST_EVENT,
			what: InsertWhat.BOTH
		},
		taxiWaitingTime: 1,
		taxiDuration: 1,
		passengerDuration: 1,
		cost: 1,
		company: 92,
		vehicle: 92,
		tour: undefined,
		departure: new Date(),
		arrival: new Date(),
		mergeTourList: []
	};
	//insertRequest(c1, capacities, exp1, event.locals.user!.id, [], []);

	const goerlitz = new Coordinates(51.15211908961152, 14.980690499347247);
	const koenigshain = new Coordinates(51.181482763047086, 14.872886683336674);
	const startFixed = true;
	const times = [new Date("2024-11-30T08:47:00")];
	const capacities2: Capacities = {
		passengers: 1,
		luggage: 0,
		bikes: 0,
		wheelchairs: 0
	};
	const startBusStops = [{
		coordinates: new Coordinates(51.15490583989987, 14.97189400299564),
		times: [new Date("2024-11-30T08:55:00")]
	},{
		coordinates: new Coordinates(51.14999073525618, 14.994267244545114),
		times: [new Date("2024-11-30T08:55:00")]
	}];
	const targetBusStops = [{
			coordinates: new Coordinates(51.18191111011515, 14.87610809458937),
			times: [new Date("2024-11-30T09:10:00")]
	}];

	const a = await wl(event, goerlitz,koenigshain,startFixed,times,capacities2,startBusStops,targetBusStops);
	const b= await a.json();
	console.log(b.start[0]);

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

		if (!house_number || house_number.length < 1) {
			return fail(400, { error: 'Hausnummer zu kurz.' });
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
