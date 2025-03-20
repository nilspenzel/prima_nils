import { sql, Transaction } from 'kysely';
import { jsonArrayFrom } from 'kysely/helpers/postgres';
import { sendMail } from '$lib/server/sendMail';
import CancelNotificationCompany from '$lib/server/email/CancelNotificationCompany.svelte';
import { updateDirectDurations } from '../booking/updateDirectDuration';
import { db, type Database } from '$lib/server/db';
import { oneToManyCarRouting } from '../util/oneToManyCarRouting';

export const cancelRequest = async (requestId: number, userId: number) => {
	await db.transaction().execute(async (trx) => {
		await sql`LOCK TABLE tour, request, event, "user" IN ACCESS EXCLUSIVE MODE;`.execute(trx);
		const tour = await trx
			.selectFrom('request as cancelled_request')
			.where('cancelled_request.id', '=', requestId)
			.innerJoin('tour', 'tour.id', 'cancelled_request.tour')
			.select((eb) => [
				'tour.id',
				'tour.departure',
				'cancelled_request.ticketChecked',
				'tour.vehicle',
				jsonArrayFrom(
					eb
						.selectFrom('request as cancelled_request')
						.innerJoin('tour as cancelled_tour', 'cancelled_tour.id', 'cancelled_request.tour')
						.innerJoin('request', 'request.tour', 'cancelled_tour.id')
						.innerJoin('event', 'event.request', 'request.id')
						.where('cancelled_request.id', '=', requestId)
						.select([
							'event.address',
							'event.scheduledTimeStart',
							'event.scheduledTimeEnd',
							'event.cancelled',
							'event.lat',
							'event.lng',
							'request.id as requestid',
							'cancelled_tour.id as tourid',
							'event.id as eventid'
						])
				).as('events'),
				jsonArrayFrom(
					eb
						.selectFrom('request')
						.innerJoin('tour', 'tour.id', 'request.tour')
						.innerJoin('vehicle', 'vehicle.id', 'tour.vehicle')
						.innerJoin('company', 'company.id', 'vehicle.company')
						.innerJoin('user', 'user.companyId', 'company.id')
						.where('request.id', '=', requestId)
						.where('user.isTaxiOwner', '=', true)
						.select(['user.name', 'user.email'])
				).as('companyOwners')
			])
			.executeTakeFirst();
		if (tour === undefined) {
			return;
		}
		if (tour.ticketChecked === true) {
			return;
		}
		await sql`CALL cancel_request(${requestId}, ${userId}, ${Date.now()})`.execute(trx);
		if (
			(
				await trx
					.selectFrom('tour')
					.where('tour.id', '=', tour.id)
					.select(['tour.cancelled'])
					.executeTakeFirst()
			)?.cancelled
		) {
			await updateDirectDurations(tour.vehicle, tour.id, tour.departure, trx);
		}
		updateLegDurations(tour.events, requestId, trx);
		for (const companyOwner of tour.companyOwners) {
			try {
				await sendMail(CancelNotificationCompany, 'Stornierte Buchung', companyOwner.email, {
					events: tour.events,
					name: companyOwner.name,
					departure: tour.departure
				});
			} catch {
				console.log(
					'Failed to send cancellation email to company with email: ',
					companyOwner.email,
					' tourId: ',
					tour.id
				);
			}
		}
	});
};

async function updateLegDurations(
	events: {
		cancelled: boolean;
		scheduledTimeStart: number;
		scheduledTimeEnd: number;
		lat: number;
		lng: number;
		requestid: number;
		tourid: number;
		eventid: number;
	}[],
	requestId: number,
	trx: Transaction<Database>,
) {
	const update = async (idx: number, 
		events: {
			cancelled: boolean;
			scheduledTimeStart: number;
			scheduledTimeEnd: number;
			lat: number;
			lng: number;
			requestid: number;
			tourid: number;
			eventid: number;
		}[],
		trx: Transaction<Database>,
	) => {
		const duration = (await oneToManyCarRouting(events[idx - 1], [events[idx + 1]], false))[0];
		await trx.updateTable('event').set({nextLegDuration: duration}).where('event.id', '=', events[idx - 1].eventid).executeTakeFirst();
		await trx.updateTable('event').set({prevLegDuration: duration}).where('event.id', '=', events[idx + 1].eventid).executeTakeFirst();
	}

	events.filter((e) => e.requestid === requestId || e.cancelled === false);
	events.sort((e) => e.scheduledTimeStart);
	const cancelled1Idx = events.findIndex((e) => e.requestid === requestId);
	const cancelled2Idx = events.findLastIndex((e) => e.requestid === requestId);
	if(cancelled1Idx != 0) {
		await update(cancelled1Idx, events, trx);
	}
	if(cancelled2Idx != events.length - 1) {
		await update(cancelled2Idx, events, trx);
	}
}
