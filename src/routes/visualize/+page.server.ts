import type { PageServerLoad } from './$types';
import { db } from '$lib/server/db';
import type { Translations } from '$lib/i18n/translation';
import type { RequestEvent } from './$types';
import { Interval } from '$lib/util/interval';
import { DAY } from '$lib/util/time';
import { groupBy } from '$lib/util/groupBy';
import { getToursWithRequests } from '$lib/server/db/getTours';

export type BookingError = { msg: keyof Translations['msg'] };

export const load: PageServerLoad = async (event: RequestEvent) => {
	const url = event.url;
	const day = url.searchParams.get('day');
	let time = new Interval(Date.now() - DAY * 4, Date.now() + DAY * 20);
	if (day) {
		const d = new Date(day);
		time = new Interval(d.getTime(), d.getTime() + DAY);
	}
	const availabilities = await db
		.selectFrom('availability')
		.where('availability.startTime', '<=', time.endTime)
		.where('availability.endTime', '>=', time.startTime)
		.selectAll()
		.execute();
	const avas = groupBy(
		availabilities,
		(a) => a.vehicle,
		(a) => new Interval(a.startTime, a.endTime)
	);
	const ab: Interval[] = [];
	avas.forEach((a, _) => ab.concat(Interval.merge(a)));
	return {
		availabilities: ab,
		tours: (await getToursWithRequests(false, undefined, [time.startTime, time.endTime])).sort(
			(t1, t2) => t1.tourId - t2.tourId
		)
	};
};
