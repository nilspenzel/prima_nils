import { PASSENGER_CHANGE_DURATION } from '$lib/constants';
import { oneToManyCarRouting } from '$lib/server/util/oneToManyCarRouting';
import type { Coordinates } from '$lib/util/Coordinates';
import { isSamePlace } from '$lib/util/booking/isSamePlace';

type Options = {
	addPassengerChange: boolean;
};

export async function getTaxiConnectionDuration(
	from: Coordinates,
	to: Coordinates,
	arriveBy: boolean,
	{ addPassengerChange }: Options
): Promise<number | undefined> {
	if (isSamePlace(from, to)) {
		return 0;
	}

	const duration = (await oneToManyCarRouting(from, [to], arriveBy))[0];
	return duration === undefined
		? undefined
		: duration + (addPassengerChange ? PASSENGER_CHANGE_DURATION : 0);
}
