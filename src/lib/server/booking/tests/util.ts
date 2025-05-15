import { createSession } from '$lib/server/auth/session';
import { addTestUser, clearDatabase } from '$lib/testHelpers';
import { MINUTE } from '$lib/util/time';

export async function prepareTest() {
	await clearDatabase();
	const mockUserId = (await addTestUser()).id;
	const sessionToken = 'generateSessionToken()';
	console.log('Creating session for user ', mockUserId);
	await createSession(sessionToken, mockUserId);
	return mockUserId;
}

const BASE_DATE = new Date('2050-09-23T17:00Z').getTime();
export const dateInXMinutes = (x: number) => new Date(BASE_DATE + x * MINUTE);
export const inXMinutes = (x: number) => BASE_DATE + x * MINUTE;

export const black = async (body: string) => {
	return await fetch('http://localhost:5173/api/blacklist', {
		method: 'POST',
		headers: {
			'Content-Type': 'application/json'
		},
		body
	});
};

export const white = async (body: string) => {
	return await fetch('http://localhost:5173/api/whitelist', {
		method: 'POST',
		headers: {
			'Content-Type': 'application/json'
		},
		body
	});
};
