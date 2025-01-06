import type { RequestEvent } from './$types';
import { Validator } from 'jsonschema';
import {
	bookingSchema,
	schemaDefinitions,
	toBookingParameters,
	type BookingParameters
} from '$lib/bookingApiParameters';
import { error, json } from '@sveltejs/kit';
import { db } from '$lib/database';
import { sql } from 'kysely';
import { insertRequest } from './query';
import { booking } from './booking';

export const POST = async (event: RequestEvent) => {
	const getCommonTour = (l1: Set<number>, l2: Set<number>) => {
		for (const e of l1) {
			if (l2.has(e)) {
				return e;
			}
		}
		return undefined;
	};
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
	const parameters: BookingParameters = toBookingParameters(p);
	let message: string | undefined = undefined;
	let success = false;
	await db.transaction().execute(async (trx) => {
		sql`LOCK TABLE tour, request, event, availability IN ACCESS EXCLUSIVE MODE;`.execute(trx);
		let firstConnection = undefined;
		let secondConnection = undefined;
		if (parameters.connection1 != null) {
			firstConnection = await booking(parameters.connection1, parameters.capacities, false, trx);
			if (firstConnection == undefined) {
				message = 'Die erste Anfrage kann nicht erfüllt werden.';
				return;
			}
		}
		if (parameters.connection2 != null) {
			secondConnection = await booking(parameters.connection2, parameters.capacities, true, trx);
			if (secondConnection == undefined) {
				message = 'Die zweite Anfrage kann nicht erfüllt werden.';
				return;
			}
		}
		if (
			parameters.connection1 != null &&
			parameters.connection2 != null &&
			firstConnection!.tour != undefined &&
			secondConnection!.tour != undefined
		) {
			const newTour = getCommonTour(
				firstConnection!.mergeTourList,
				secondConnection!.mergeTourList
			);
			if (newTour != undefined) {
				firstConnection!.tour = newTour;
				secondConnection!.tour = newTour;
			}
		}
		if (parameters.connection1 != null) {
			insertRequest(
				firstConnection!.best,
				parameters.capacities,
				parameters.connection1,
				customer.id,
				firstConnection!.eventGroupUpdateList,
				[...firstConnection!.mergeTourList],
				firstConnection!.startEventGroup,
				firstConnection!.targetEventGroup,
				firstConnection!.neighbourIds,
				trx
			);
		}
		if (parameters.connection2 != null) {
			insertRequest(
				secondConnection!.best,
				parameters.capacities,
				parameters.connection2,
				customer.id,
				secondConnection!.eventGroupUpdateList,
				[...secondConnection!.mergeTourList],
				secondConnection!.startEventGroup,
				secondConnection!.targetEventGroup,
				secondConnection!.neighbourIds,
				trx
			);
		}
		message = 'Die Anfrage wurde erfolgreich bearbeitet.';
		success = true;
		return;
	});
	if (message == undefined) {
		return json({ status: 500 });
	}
	return json({ message }, { status: success ? 200 : 400 });
};
