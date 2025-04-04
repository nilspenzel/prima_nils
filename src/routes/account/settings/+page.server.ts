import { error, fail, redirect, type RequestEvent } from '@sveltejs/kit';
import type { Actions, PageServerLoadEvent } from './$types';
import { msg } from '$lib/msg';
import { hashPassword, isStrongPassword, verifyPasswordHash } from '$lib/server/auth/password';
import { isEmailAvailable } from '$lib/server/auth/email';
import { db } from '$lib/server/db';
import { generateRandomOTP } from '$lib/server/auth/utils';
import { MINUTE } from '$lib/util/time';
import { sendMail } from '$lib/server/sendMail';
import EmailVerification from '$lib/server/email/EmailVerification.svelte';
import { deleteSessionTokenCookie, invalidateSession } from '$lib/server/auth/session';
import { verifyPhone } from '$lib/server/verifyPhone';
import { getUserPasswordHash } from '$lib/server/auth/user';
import { jsonArrayFrom } from 'kysely/helpers/postgres';
import { cancelRequest } from '$lib/server/db/cancelRequest';
import { randomBytes } from 'crypto';
import { v4 as uuidv4 } from 'uuid';

export async function load(event: PageServerLoadEvent) {
	const user = await db
		.selectFrom('user')
		.where('user.id', '=', event.locals.session!.userId)
		.select(['user.email', 'user.phone'])
		.executeTakeFirst();
	if (user === undefined) {
		error(404, { message: 'User not found' });
	}
	return {
		email: user.email,
		phone: user.phone
	};
}

export const actions: Actions = {
	changePassword: async function verifyCode(event: RequestEvent) {
		const userId = event.locals.session!.userId;
		const formData = await event.request.formData();
		const newPassword = formData.get('newPassword');
		const oldPassword = formData.get('oldPassword');
		if (typeof newPassword !== 'string' || newPassword === '') {
			return fail(400, { msg: msg('enterNewPassword') });
		}
		if (typeof oldPassword !== 'string' || oldPassword === '') {
			return fail(400, { msg: msg('enterOldPassword') });
		}
		if (!(await isStrongPassword(newPassword))) {
			return fail(400, { msg: msg('weakPassword') });
		}
		const oldPasswordHash = await getUserPasswordHash(userId);
		if (!(await verifyPasswordHash(oldPasswordHash, oldPassword))) {
			return fail(400, { msg: msg('invalidOldPassword') });
		}
		const passwordHash = await hashPassword(newPassword);
		await db
			.updateTable('user')
			.where('user.id', '=', event.locals.session!.userId!)
			.set({ passwordHash })
			.execute();
		return { msg: msg('passwordChanged', 'success') };
	},

	changeEmail: async function resendEmail(event: RequestEvent) {
		const formData = await event.request.formData();
		const email = formData.get('email');
		if (typeof email !== 'string' || email === '') {
			return fail(400, { msg: msg('enterEmail'), email: '' });
		}
		if (event.locals.session?.email == email) {
			return fail(400, { msg: msg('oldEmail'), email });
		}
		if (!(await isEmailAvailable(email))) {
			return fail(400, { msg: msg('emailAlreadyRegistered'), email });
		}

		// Update e-mail address.
		const user = await db
			.updateTable('user')
			.set({
				email,
				emailVerificationCode: generateRandomOTP(),
				emailVerificationExpiresAt: Date.now() + 10 * MINUTE,
				isEmailVerified: false
			})
			.where('id', '=', event.locals.session!.userId)
			.returningAll()
			.executeTakeFirstOrThrow();

		// Send verification email.
		try {
			await sendMail(EmailVerification, 'Email Verifikation', email, {
				code: user.emailVerificationCode,
				name: user.name
			});
		} catch {
			return fail(500, { msg: msg('failedToSendVerificationEmail'), email });
		}

		return { msg: msg('checkInboxToVerify', 'success') };
	},

	changePhone: async function changePhone(event: RequestEvent) {
		const phone = verifyPhone((await event.request.formData()).get('phone'));
		if (phone != null && typeof phone !== 'string') {
			return phone;
		}
		await db
			.updateTable('user')
			.where('user.id', '=', event.locals.session!.userId!)
			.set({ phone })
			.execute();
		return { msg: msg('phoneChanged', 'success') };
	},

	logout: async (event: RequestEvent) => {
		await invalidateSession(event.locals.session!.id);
		deleteSessionTokenCookie(event);
		return redirect(302, '/');
	},

	deleteAccount: async (event: RequestEvent) => {
		let deleteStatus = DELETE_USER_STATUS.INITIAL as DELETE_USER_STATUS;
		await db.transaction().execute(async (trx) => {
			const userId = event.locals.session!.userId;
			const now = Date.now();
			const user = await trx
				.selectFrom('user')
				.where('user.id', '=', userId)
				.select((eb) => [
					'user.email',
					'user.phone',
					jsonArrayFrom(
						eb
							.selectFrom('request')
							.innerJoin('event', 'event.request', 'request.id')
							.where('request.customer', '=', userId)
							.where('request.cancelled', '=', false)
							.where('request.ticketChecked', '=', false)
							.where('event.communicatedTime', '>=', now)
							.select(['request.id'])
					).as('requests'),
					jsonArrayFrom(
						eb
							.selectFrom('vehicle')
							.whereRef('vehicle.company', '=', 'user.companyId')
							.select((eb) => [
								'vehicle.id',
								jsonArrayFrom(
									eb
										.selectFrom('availability')
										.whereRef('availability.vehicle', '=', 'vehicle.id')
										.where('availability.endTime', '>', now)
										.select(['availability.id'])
								).as('availabilities'),
								jsonArrayFrom(
									eb
										.selectFrom('tour')
										.whereRef('tour.vehicle', '=', 'vehicle.id')
										.where('tour.arrival', '>', now)
										.select(['tour.id'])
								).as('tours')
							])
					).as('vehicles'),
					jsonArrayFrom(
						eb
							.selectFrom('user as user_to_delete')
							.innerJoin('company', 'user.companyId', 'company.id')
							.innerJoin('user', 'user.companyId', 'company.id')
							.where('user_to_delete.id', '=', userId)
							.where('user.isTaxiOwner', '=', true)
							.select(['user.id'])
					).as('entrepreneurs')
				])
				.executeTakeFirst();

			if (!user) {
				deleteStatus = DELETE_USER_STATUS.ERROR_USER_NOT_FOUND;
				return;
			}
			if (user.vehicles.length != 0 && user.entrepreneurs.length !== 1) {
				if (user.vehicles.filter((v) => v.availabilities.length != 0)) {
					deleteStatus = DELETE_USER_STATUS.REMAINING_AVAILBILITIES;
					return;
				}
				// Cannot delete while there are planned tours
				if (user.vehicles.flatMap((v) => v.tours).length != 0) {
					deleteStatus = DELETE_USER_STATUS.REMAINING_TOURS;
					return;
				}
			}
			// Overwrite user data
			let success = false;
			const maxTries = 3;
			let tries = 0;
			while (!success && tries++ < maxTries) {
				const uuid = uuidv4();
				try {
					await trx
						.updateTable('user')
						.where('user.id', '=', event.locals.session!.userId)
						.set({
							name: 'gelöschter Nutzer',
							email: uuid,
							passwordHash: generateSecurePassword(),
							isTaxiOwner: false,
							isAdmin: false,
							isEmailVerified: false,
							passwordResetCode: null,
							emailVerificationCode: null,
							emailVerificationExpiresAt: null,
							passwordResetExpiresAt: null,
							phone: null,
							companyId: null
						})
						.execute();
					// Cancel remaining requests which user booked as a customer
					user.requests.forEach(
						async (r) => await cancelRequest(r.id, event.locals.session!.userId)
					);
				} catch (e) {
					// @ts-expect-error: 'e' is of type 'unknown'
					if (e.constraint == 'user_email_key') {
						console.log(
							'Randomly generated email caused conflict when inserting into database while trying to delete user. Generated email: ',
							uuid
						);
						continue;
					}
					console.log('Database query failed when trying to delete user.');
					deleteStatus = DELETE_USER_STATUS.UNKNOWN_DB_ERROR;
					return;
				}
				success = true;
			}
			deleteStatus = DELETE_USER_STATUS.SUCCESS;
		});
		switch (deleteStatus) {
			case DELETE_USER_STATUS.REMAINING_TOURS:
				return fail(400, { msg: msg('remainingTours') });
			case DELETE_USER_STATUS.ERROR_USER_NOT_FOUND:
				return fail(400, { msg: msg('unknownError') });
			case DELETE_USER_STATUS.REMAINING_AVAILBILITIES:
				return fail(400, { msg: msg('remainingAvailabilities') });
			case DELETE_USER_STATUS.UNKNOWN_DB_ERROR:
				return fail(400, { msg: msg('unknownError') });
			default:
				break;
		}
		await invalidateSession(event.locals.session!.id);
		deleteSessionTokenCookie(event);
		return redirect(302, '/');
	}
};

function generateSecurePassword(length: number = 16): string {
	const charset =
		'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!@#$%^&*()-_=+[];:,.?';
	const bytes = randomBytes(length);
	let password = '';

	for (let i = 0; i < length; i++) {
		const index = bytes[i] % charset.length;
		password += charset[index];
	}

	return password;
}

enum DELETE_USER_STATUS {
	INITIAL,
	REMAINING_TOURS,
	ERROR_USER_NOT_FOUND,
	REMAINING_AVAILBILITIES,
	UNKNOWN_DB_ERROR,
	SUCCESS
}
