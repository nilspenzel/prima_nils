import type { RequestEvent } from './$types';
import { Validator } from 'jsonschema';
import { bookingSchema, type BookingRequest } from '$lib/bookingApiParameters';
import { error, json } from '@sveltejs/kit';
import { white } from '../whitelist/whitelist';
import { db } from '$lib/database';
import type { Location } from '$lib/location';
import { sql } from 'kysely';
import { insertRequest } from './query';

export type EvNew = {
	location: Location;
	scheduledTime: Date;
	communicatedTime: Date;
	approachDuration: number;
	returnDuration: number;
	customer: string;
};

export async function POST(event: RequestEvent) {
	const customer = event.locals.user;
	if (!customer) {
		return error(403);
	}
	const p = await event.request.json();
	const validator = new Validator();
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
		const firstConnection = (
			await white(
				parameters.connection1.start.coordinates,
				[
					{
						coordinates: parameters.connection1.target.coordinates,
						times: [new Date(parameters.connection1.targetTime)]
					}
				],
				parameters.capacities,
				false,
				trx
			)
		)[0][0];
		if (firstConnection == undefined) {
			return json({ message: 'Die erste Anfrage kann nicht erfüllt werden.' }, { status: 400 });
		}
		if (parameters.connection2 == null) {
			insertRequest(firstConnection, parameters.capacities, parameters.connection1, customer.id);
			return json([]);
		}
		const secondConnection = (
			await white(
				parameters.connection2.start.coordinates,
				[
					{
						coordinates: parameters.connection2.target.coordinates,
						times: [new Date(parameters.connection2.targetTime)]
					}
				],
				parameters.capacities,
				false,
				trx
			)
		)[0][0];
		if (secondConnection == undefined) {
			return json({ message: 'Die zweite Anfrage kann nicht erfüllt werden.' }, { status: 400 });
		}
		insertRequest(secondConnection, parameters.capacities, parameters.connection2, customer.id);
		insertRequest(firstConnection, parameters.capacities, parameters.connection1, customer.id);
	});
	return json([]);
}
