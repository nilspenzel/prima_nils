import { BUFFER_TIME, PASSENGER_CHANGE_MINUTES } from './constants';

export function secondsToMs(minutes: number) {
	return minutes * 1000;
}

export function minutesToMs(minutes: number) {
	return minutes * 60000;
}

export function hoursToMs(hours: number) {
	return hours * 3600000;
}

export function yearsToMs(years: number) {
	return years * 365 * 3600000 * 24;
}

export function msToMinutes(ms: number) {
	return ms / 60000;
}

export function addBuffer(ms: number) {
	return ms + (ms == 0 ? 0 : minutesToMs(BUFFER_TIME));
}

export function addPassengerChangeTime(ms: number) {
	return ms + (ms == 0 ? 0 : minutesToMs(PASSENGER_CHANGE_MINUTES));
}
