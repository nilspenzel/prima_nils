import { EARLIEST_SHIFT_START, FUTURE_BOOKING_RESTRICTION, LATEST_SHIFT_END } from '$lib/constants';
import { db } from '$lib/server/db/index.js';
import { getAllowedTimes } from '$lib/util/getAllowedTimes';
import { Interval } from '$lib/util/interval';
import { DAY } from '$lib/util/time';
import { json, type RequestEvent } from '@sveltejs/kit';

export const POST = async (_: RequestEvent) => {
	const todayMidnight = new Date();
	todayMidnight.setUTCHours(0, 0, 0, 0);
	const in2weeks = todayMidnight.getTime() + FUTURE_BOOKING_RESTRICTION;
	const interval = new Interval(in2weeks, in2weeks + DAY);
	const allowedTimes = getAllowedTimes(
		interval.startTime,
		interval.endTime,
		EARLIEST_SHIFT_START,
		LATEST_SHIFT_END
	)
		.map((allowed) => allowed.intersect(interval))
		.filter((a) => a !== undefined);

	await db.transaction().execute(async (trx) => {
		for (const allowed of allowedTimes) {
			await trx
				.insertInto('availability')
				.columns(['vehicle', 'startTime', 'endTime'])
				.expression((eb) =>
					eb
						.selectFrom('company')
						.innerJoin('vehicle', 'vehicle.company', 'company.id')
						.distinctOn('company.id')
						.select([
							'vehicle.id as vehicle',
							eb.val(allowed.startTime).as('startTime'),
							eb.val(allowed.endTime).as('endTime')
						])
						.orderBy('company.id')
						.orderBy('vehicle.passengers', 'asc')
						.orderBy('vehicle.id', 'asc')
				)
				.execute();
		}
	});
	return json({});
};
