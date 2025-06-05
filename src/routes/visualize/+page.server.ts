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
	const localDateParam = url.searchParams.get('date');
	const timezoneOffset = url.searchParams.get('offset');
	const utcDate =
		localDateParam && timezoneOffset
			? new Date(new Date(localDateParam!).getTime() + Number(timezoneOffset) * 60 * 1000)
			: new Date();
	return {
		tours: (await getToursWithRequests(false)).sort(
			(t1, t2) => t1.tourId - t2.tourId
		),
		utcDate
	};
};
