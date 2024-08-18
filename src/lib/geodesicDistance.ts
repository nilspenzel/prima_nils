import { EARTH_RADIUS } from './constants';
import type { Coordinates } from './location';

export const calculateDistance = (c1: Coordinates, c2: Coordinates) => {
	const toRadians = (degrees: number) => degrees * (Math.PI / 180);
	const dLat = toRadians(c2.lat - c1.lat);
	const dLon = toRadians(c2.lng - c1.lng);
	const a =
		Math.sin(dLat / 2) * Math.sin(dLat / 2) +
		Math.cos(toRadians(c1.lat)) *
			Math.cos(toRadians(c2.lat)) *
			Math.sin(dLon / 2) *
			Math.sin(dLon / 2);
	const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));

	return EARTH_RADIUS * c; // Distance in kilometers
};
