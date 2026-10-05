import type { Transaction } from 'kysely';
import { type Database } from '$lib/server/db';
import { jsonArrayFrom, jsonObjectFrom } from 'kysely/helpers/postgres';
import { getTaxiConnectionDuration } from '../getTaxiConnectionDuration';

export async function updateDirectDurations(
	oldVehicleId: number,
	tourId: number,
	departure: number,
	trx: Transaction<Database>,
	newVehicleId?: number
) {
	const vehicleIds = [oldVehicleId];
	if (newVehicleId) {
		vehicleIds.push(newVehicleId);
	}
	const vehicles = await trx
		.selectFrom('vehicle')
		.where('vehicle.id', 'in', vehicleIds)
		.select((eb) => [
			'vehicle.id',
			jsonObjectFrom(
				eb
					.selectFrom('tour')
					.innerJoin('request', 'request.tour', 'tour.id')
					.innerJoin('event', 'event.request', 'request.id')
					.innerJoin('eventGroup', 'eventGroup.id', 'event.eventGroupId')
					.whereRef('tour.vehicle', '=', 'vehicle.id')
					.where('tour.cancelled', '=', false)
					.where('tour.departure', '<=', departure)
					.where('request.cancelled', '=', false)
					.orderBy('tour.departure', 'desc')
					.orderBy('eventGroup.scheduledTimeEnd', 'desc')
					.orderBy('eventGroup.scheduledTimeStart', 'desc')
					.limit(1)
					.select([
						'eventGroup.lat',
						'eventGroup.lng',
						'request.tour',
						'eventGroup.scheduledTimeStart'
					])
			).as('prevtour'),
			jsonObjectFrom(
				eb
					.selectFrom('tour')
					.innerJoin('request', 'request.tour', 'tour.id')
					.innerJoin('event', 'event.request', 'request.id')
					.innerJoin('eventGroup', 'eventGroup.id', 'event.eventGroupId')
					.whereRef('tour.vehicle', '=', 'vehicle.id')
					.where('tour.cancelled', '=', false)
					.where('tour.departure', '>', departure)
					.where('request.cancelled', '=', false)
					.orderBy('tour.departure', 'asc')
					.orderBy('eventGroup.scheduledTimeEnd', 'asc')
					.orderBy('eventGroup.scheduledTimeStart', 'asc')
					.limit(1)
					.select([
						'eventGroup.lat',
						'eventGroup.lng',
						'request.tour',
						'eventGroup.scheduledTimeStart'
					])
			).as('nexttour'),
			jsonArrayFrom(
				eb
					.selectFrom('tour')
					.where('tour.id', '=', tourId)
					.select((eb) => [
						jsonArrayFrom(
							eb
								.selectFrom('request')
								.innerJoin('event', 'event.request', 'request.id')
								.innerJoin('eventGroup', 'eventGroup.id', 'event.eventGroupId')
								.where('request.cancelled', '=', false)
								.whereRef('request.tour', '=', 'tour.id')
								.orderBy('eventGroup.scheduledTimeEnd', 'asc')
								.orderBy('eventGroup.scheduledTimeStart', 'asc')
								.select(['eventGroup.lat', 'eventGroup.lng', 'eventGroup.scheduledTimeStart'])
						).as('events')
					])
			).as('moved')
		])
		.execute();

	const oldVehicle = vehicles[0].id === oldVehicleId ? vehicles[0] : vehicles[1];
	if (oldVehicle.nexttour) {
		const routingResult = oldVehicle?.prevtour
			? ((await getTaxiConnectionDuration(oldVehicle.prevtour, oldVehicle.nexttour, false, {
					addPassengerChange: true
				})) ?? null)
			: null;
		await trx
			.updateTable('tour')
			.set({ directDuration: routingResult })
			.where('id', '=', oldVehicle.nexttour.tour)
			.executeTakeFirst();
	}

	if (newVehicleId) {
		const newVehicle = vehicles[0].id === newVehicleId ? vehicles[0] : vehicles[1];
		const events = newVehicle.moved[0].events;
		events.sort((e) => e.scheduledTimeStart);
		const routingResultPrevTour = newVehicle?.prevtour
			? ((await getTaxiConnectionDuration(newVehicle.prevtour, events[0], false, {
					addPassengerChange: true
				})) ?? null)
			: null;
		await trx
			.updateTable('tour')
			.set({ directDuration: routingResultPrevTour })
			.where('id', '=', tourId)
			.executeTakeFirst();

		if (newVehicle.nexttour) {
			const routingResultNextTour =
				(await getTaxiConnectionDuration(events[events.length - 1], newVehicle.nexttour, false, {
					addPassengerChange: true
				})) ?? null;
			await trx
				.updateTable('tour')
				.set({ directDuration: routingResultNextTour })
				.where('id', '=', newVehicle.nexttour.tour)
				.executeTakeFirst();
		}
	}
}
