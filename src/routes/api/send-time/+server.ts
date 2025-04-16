import { nowOrSimulationTime, setSimulationTime } from '$lib/util/time';
import { json } from '@sveltejs/kit';

export const POST = async (event) => {
	setSimulationTime((await event.request.json()).t);
	return json({});
};
