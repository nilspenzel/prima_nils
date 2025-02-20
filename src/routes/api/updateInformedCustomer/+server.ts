import { db } from '$lib/server/db';
import type { RequestEvent } from './$types';
import { json } from '@sveltejs/kit';
import { sql } from 'kysely';

export const POST = async (event: RequestEvent) => {
	const company = event.locals.session!.companyId;
	const p = await event.request.json();
	if (!company || !p.tourId || !p.customer) {
		return json({});
	}
	await sql`CALL update_informed_customer(${p.tourId}, ${company}, ${p.customer}, ${p.informed})`.execute(db);
	return json({});
};
