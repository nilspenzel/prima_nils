import crypto from 'crypto';
import { SECRET_KEY } from '$env/static/private';

export function signEntry(
	fromLat: number,
	fromLng: number,
	toLat: number,
	toLng: number,
	startTime: number,
	endTime: number,
	startFixed: boolean
): string {
	const serialized = JSON.stringify({
		fromLat,
		fromLng,
		toLat,
		toLng,
		startTime: startTime,
		endTime: endTime,
		startFixed
	});
	return crypto.createHmac('sha256', SECRET_KEY).update(serialized).digest('hex');
}
