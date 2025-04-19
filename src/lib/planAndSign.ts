import type { Itinerary, PlanData, PlanResponse } from './openapi';

export type SignedItinerary = Itinerary & { signature1?: string; signature2?: string };

export type SignedPlanResponse = Omit<PlanResponse, 'itineraries'> & {
	itineraries: SignedItinerary[];
};

export async function planAndSign(q: PlanData): Promise<{ data: SignedPlanResponse }> {
	return await fetch('/api/signPlanResponse', {
		method: 'POST',
		headers: {
			'Content-Type': 'application/json'
		},
		body: JSON.stringify({
			query: q.query
		})
	}).then(async (r) => {
		return { data: (await r.json()).data };
	});
}
