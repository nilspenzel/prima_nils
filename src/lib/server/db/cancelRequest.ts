import { sql, Transaction } from 'kysely';
import { jsonArrayFrom } from 'kysely/helpers/postgres';
import { sendMail } from '$lib/server/sendMail';
import CancelNotificationCompany from '$lib/server/email/CancelNotificationCompany.svelte';
import { getScheduledEventTime } from '$lib/util/getScheduledEventTime';
import { sendNotifications } from '../firebase/notifications';
import { TourChange } from '$lib/server/firebase/firebase';
import { updateDirectDurations } from '$lib/server/booking/updateDirectDuration';
import { db, type Database } from '$lib/server/db';
import { oneToManyCarRouting } from '$lib/server/util/oneToManyCarRouting';
import { HOUR } from '$lib/util/time';
import { retry } from './retryQuery';

export const cancelRequest = async (requestId: number, userId: number) => {
	console.log(
		'Cancel Request PARAMS START: ',
		JSON.stringify({ requestId, userId }, null, '\t'),
		' Cancel Request PARAMS END'
	);
	await retry(() =>
		db.transaction().execute(async (trx) => {
			const tour = await trx
				.selectFrom('request')
				.where('request.id', '=', requestId)
				.innerJoin('tour as relevant_tour', 'relevant_tour.id', 'request.tour')
				.select((eb) => [
					'relevant_tour.id as tourId',
					'request.ticketChecked',
					jsonArrayFrom(
						eb
							.selectFrom('request as cancelled_request')
							.where('cancelled_request.id', '=', requestId)
							.innerJoin('tour as relevant_tour', 'cancelled_request.tour', 'relevant_tour.id')
							.innerJoin('request as relevant_request', 'relevant_request.tour', 'relevant_tour.id')
							.select((eb) => [
								'relevant_request.wheelchairs',
								jsonArrayFrom(
									eb
										.selectFrom('event')
										.whereRef('event.request', '=', 'relevant_request.id')
										.select([
											'event.scheduledTimeStart',
											'event.scheduledTimeEnd',
											'event.isPickup',
											'event.request as requestId'
										])
								).as('events')
							])
					).as('requests')
				])
				.executeTakeFirst();
			if (tour === undefined) {
				console.log(
					'Cancel Request early exit - cannot find tour associated with requestId in db. ',
					{ requestId, userId }
				);
				return;
			}
			if (tour.ticketChecked === true) {
				console.log('Cancel Request early exit - cannot cancel request, ticket was checked. ', {
					requestId,
					userId
				});
				return;
			}
			const queryResult = await sql<{
				wastourcancelled: boolean;
			}>`SELECT cancel_request(${requestId}, ${userId}, ${Date.now()}) AS wasTourCancelled`.execute(
				trx
			);
			const tourInfo = await trx
				.selectFrom('request as cancelled_request')
				.where('cancelled_request.id', '=', requestId)
				.innerJoin('tour', 'tour.id', 'cancelled_request.tour')
				.select((eb) => [
					'cancelled_request.ticketChecked',
					'tour.vehicle',
					'tour.id',
					'tour.departure',
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
							.select([
								'user.name',
								'user.email',
								'company.lat',
								'company.lng',
								'company.id as companyId'
							])
					).as('companyOwners')
				])
				.executeTakeFirst();
			if (tourInfo === undefined) {
				console.log(
					'Tour was undefined unexpectedly in cancelRequest cannot send notification Emails, requestId: ',
					requestId
				);
				return;
			}
			console.assert(queryResult.rows.length === 1);
			if (queryResult.rows[0].wastourcancelled) {
				await updateDirectDurations(tourInfo.vehicle, tourInfo.id, tourInfo.departure, trx);
			} else {
				await updateLegDurations(
					tourInfo.events,
					{ lat: tourInfo.companyOwners[0].lat!, lng: tourInfo.companyOwners[0].lng! },
					requestId,
					trx
				);
			}
			for (const companyOwner of tourInfo.companyOwners) {
				try {
					await sendMail(CancelNotificationCompany, 'Stornierte Buchung', companyOwner.email, {
						events: tourInfo.events,
						name: companyOwner.name,
						departure: tourInfo.departure
					});
				} catch {
					console.log(
						'Failed to send cancellation email to company with email: ',
						companyOwner.email,
						' tourId: ',
						tourInfo.id
					);
				}
			}

			const firstEvent = tour.requests
				.flatMap((r) => r.events)
				.sort((e) => e.scheduledTimeStart)[0];
			const wheelchairs = tour.requests.reduce((prev, curr) => prev + curr.wheelchairs, 0);
			if (firstEvent.requestId === requestId && tourInfo.companyOwners.length !== 0) {
				await sendNotifications(tourInfo.companyOwners[0].companyId, {
					tourId: tour.tourId,
					pickupTime: getScheduledEventTime(firstEvent),
					vehicleId: tourInfo.vehicle,
					wheelchairs,
					change: TourChange.CANCELLED
				});
			}

			console.log('Cancel Request - success', { requestId, userId });
		})
	);
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
	company: maplibregl.LngLatLike,
	requestId: number,
	trx: Transaction<Database>
) {
	const update = async (
		prevIdx: number,
		nextIdx: number,
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
		company: maplibregl.LngLatLike,
		trx: Transaction<Database>
	) => {
		if (prevIdx === -1) {
			const routingResult = await oneToManyCarRouting(company, [events[nextIdx]], false, HOUR * 10);
			console.log({ routingResult });
			if (
				routingResult === undefined ||
				routingResult.length === 0 ||
				routingResult[0] === undefined
			) {
				console.log(
					`unable to update prevLegDuration for event ${events[nextIdx].eventid}, routing result was undefined.`
				);
				return;
			}
			await trx
				.updateTable('event')
				.set({ prevLegDuration: routingResult[0] })
				.where('event.id', '=', events[nextIdx].eventid)
				.executeTakeFirst();
			return;
		}
		if (nextIdx === events.length) {
			const routingResult = await oneToManyCarRouting(events[prevIdx], [company], false, HOUR * 10);
			console.log({ routingResult });
			if (
				routingResult === undefined ||
				routingResult.length === 0 ||
				routingResult[0] === undefined
			) {
				console.log(
					`unable to update prevLegDuration for event ${events[prevIdx].eventid}, routing result was undefined.`
				);
				return;
			}
			await trx
				.updateTable('event')
				.set({ nextLegDuration: routingResult[0] })
				.where('event.id', '=', events[prevIdx].eventid)
				.executeTakeFirst();
			return;
		}
		const routingResult = await oneToManyCarRouting(
			events[prevIdx],
			[events[nextIdx]],
			false,
			HOUR * 10
		);
		console.log({ routingResult });
		if (
			routingResult === undefined ||
			routingResult.length === 0 ||
			routingResult[0] === undefined
		) {
			console.log(
				`unable to update prevLegDuration for event ${events[prevIdx].eventid} and nextLegDuration for event ${events[nextIdx].eventid}, routing result was undefined.`
			);
			return;
		}
		await trx
			.updateTable('event')
			.set({ nextLegDuration: routingResult[0] })
			.where('event.id', '=', events[prevIdx].eventid)
			.executeTakeFirst();
		await trx
			.updateTable('event')
			.set({ prevLegDuration: routingResult[0] })
			.where('event.id', '=', events[nextIdx].eventid)
			.executeTakeFirst();
	};

	const uncancelledEvents = events
		.filter((e) => e.requestid === requestId || e.cancelled === false)
		.sort((e1, e2) => e1.scheduledTimeStart - e2.scheduledTimeStart);
	const cancelled1Idx = uncancelledEvents.findIndex((e) => e.requestid === requestId);
	const cancelled2Idx = uncancelledEvents.findLastIndex((e) => e.requestid === requestId);
	console.assert(
		cancelled1Idx != -1 && cancelled2Idx != -1 && cancelled1Idx < cancelled2Idx,
		'Invalid cancelledIdx in cancelRequest.ts',
		{ cancelled1Idx },
		{ cancelled2Idx }
	);
	if (cancelled1Idx === cancelled2Idx - 1) {
		await update(cancelled1Idx - 1, cancelled2Idx + 1, uncancelledEvents, company, trx);
		return;
	}
	await update(cancelled1Idx - 1, cancelled1Idx + 1, uncancelledEvents, company, trx);
	await update(cancelled2Idx - 1, cancelled2Idx + 1, uncancelledEvents, company, trx);
}
