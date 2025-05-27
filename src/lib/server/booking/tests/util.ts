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

const now = new Date();
const baseDate = new Date(
	Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate() + 2, 13, 0, 0, 0)
);

const BASE_DATE = baseDate.getTime();

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
