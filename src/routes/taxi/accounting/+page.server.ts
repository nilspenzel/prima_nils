import { getCompanyCosts } from '$lib/server/db/getCompanyCosts';
import { getToursWithRequests } from '$lib/server/db/getTours.js';
import { getCost } from '$lib/testHelpers.js';
import type { PageServerLoad, RequestEvent } from './$types.js';

export const load: PageServerLoad = async (event: RequestEvent) => {
	const t = await getToursWithRequests(false);
	const ft = t.filter((t) => t.tourId === 151)[0];
	console.log("jada12",getCost(ft));
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
