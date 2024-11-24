import type { RequestEvent } from './$types';
import { Validator } from 'jsonschema';
import { bookingSchema, schemaDefinitions, type BookingRequest } from '$lib/bookingApiParameters';
import { error, json } from '@sveltejs/kit';
import { db } from '$lib/database';
import type { Location } from '$lib/location';
import { sql } from 'kysely';
import { insertRequest } from './query';
import { booking } from './booking';

export const POST = async (event: RequestEvent) => {
	const customer = event.locals.user;
	if (!customer) {
		return error(403);
	}
	const p = await event.request.json();
	const validator = new Validator();
	validator.addSchema(schemaDefinitions, '/schemaDefinitions');
	const result = validator.validate(p, bookingSchema);
	if (!result.valid) {
		return json(
			{
				message: result.errors
			},
			{ status: 400 }
		);
	}
	const parameters: BookingRequest = p;

	await db.transaction().execute(async (trx) => {
		sql`LOCK TABLE tour, request, event, availability IN ACCESS EXCLUSIVE MODE;`.execute(trx);
		const firstConnection = await booking(
			parameters.connection1,
			parameters.capacities,
			false,
			trx
		);
		if (firstConnection == undefined) {
			return json({ message: 'Die erste Anfrage kann nicht erfüllt werden.' }, { status: 400 });
		}
		if (parameters.connection2 == null) {
			insertRequest(
				firstConnection.best,
				parameters.capacities,
				parameters.connection1,
				customer.id,
				firstConnection.eventGroupUpdateList,
				firstConnection.mergeTourList
			);
			return json([]);
		}
		const secondConnection = await booking(
			parameters.connection2,
			parameters.capacities,
			false,
			trx
		);
		if (secondConnection == undefined) {
			return json({ message: 'Die zweite Anfrage kann nicht erfüllt werden.' }, { status: 400 });
		}
		insertRequest(
			firstConnection.best,
			parameters.capacities,
			parameters.connection2,
			customer.id,
			firstConnection.eventGroupUpdateList,
			firstConnection.mergeTourList
		);
		insertRequest(
			secondConnection.best,
			parameters.capacities,
			parameters.connection1,
			customer.id,
			secondConnection.eventGroupUpdateList,
			secondConnection.mergeTourList
		);
	});
	return json([]);
};
