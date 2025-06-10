import { getCompanyCosts } from '$lib/server/db/getCompanyCosts';
import { getToursWithRequests } from '$lib/server/db/getTours.js';
import { db } from '$lib/server/db/index.js';
import { oneToManyCarRouting } from '$lib/server/util/oneToManyCarRouting.js';
import type { PageServerLoad, RequestEvent } from './$types.js';

export const load: PageServerLoad = async (event: RequestEvent) => {
	const tours2 = getToursWithRequests(false);
	const events = (await tours2).flatMap((t) => t.requests.flatMap((r) => r.events));
	const companies = await db.selectFrom('company').selectAll().execute();
	const results: { res: number | undefined; e1: number; e2: number }[] = [];
	const events1 = events.filter((e) => e.id === 71 || e.id === 72);
	const events2 = events.filter((e) => e.id === 57 || e.id === 59 || e.id === 60);
	for (let i = 0; i != events1.length; ++i) {
		for (let j = 0; j != events2.length; ++j) {
			console.log(
				{ e1: events1[i].id },
				{ e2: events2[j].id },
				{ result: (await oneToManyCarRouting(events1[i], [events[j]], false))[0] }
			);
		}
	}
	for (let i = 0; i != events2.length; ++i) {
		for (let j = 0; j != events1.length; ++j) {
			console.log(
				{ e1: events1[j].id },
				{ e2: events2[i].id },
				{ result: (await oneToManyCarRouting(events2[i], [events1[j]], false))[0] }
			);
		}
	}
	//console.log("stuffy1: ", results.filter((r) => r.res === 175000))
	//console.log("stuffy: ", await oneToManyCarRouting(events.filter((e) => e.id === 63)[0], events.filter((e) => e.id === 90), false));
	//console.log("stuffy: ", await oneToManyCarRouting(events.filter((e) => e.id === 63)[0], events.filter((e) => e.id === 90), true));
	//console.log("stuffy: ", await oneToManyCarRouting(events.filter((e) => e.id === 90)[0], events.filter((e) => e.id === 63), false));
	//console.log("stuffy: ", await oneToManyCarRouting(events.filter((e) => e.id === 90)[0], events.filter((e) => e.id === 63), true));

	/*
	72 -> busstop
	71 -> userChosen
	coords[0] -> companyid===57
	coords[1] -> companyid===59
	coords[2] -> eventid===60
*/

	const url = event.url;
	const tourParam = url.searchParams.get('tourId');
	const tourId = tourParam === null || isNaN(parseInt(tourParam)) ? undefined : parseInt(tourParam);

	const companyId = event.locals.session!.companyId!;
	const { tours, earliestTime, latestTime, costPerDayAndVehicle } =
		await getCompanyCosts(companyId);
	return {
		tours: tours.map(({ interval: _, ...rest }) => rest),
		earliestTime,
		latestTime,
		costPerDayAndVehicle,
		tourId
	};
};
