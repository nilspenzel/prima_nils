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
import { LATEST_VALID_TIME } from '$lib/constants';
import { v4 as uuidv4 } from 'uuid';
import { cancelRequest } from '$lib/server/db/cancelRequest';

export async function load(event: PageServerLoadEvent) {
	const user = await db
		.selectFrom('user')
		.where('user.id', '=', event.locals.session!.userId)
		.select((eb) => [
			'user.email',
			'user.phone'
		])
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
		await db.transaction().execute(async (trx) => {
			const user = await trx
			.selectFrom('user')
			.where('user.id', '=', event.locals.session!.userId)
			.leftJoin('company', 'company.id', 'user.companyId')
			.select((eb) => [
				jsonArrayFrom(
					eb.selectFrom('request')
					.innerJoin('event', 'event.request', 'request.id')
					.whereRef('request.customer', '=', 'user.id')
					.where('request.cancelled', '=', false)
					.where('request.ticketChecked', '=', false)
					.where('event.communicatedTime', '>=', Date.now())
					.select([
						'event.address'
					])
				).as('events'),
				'user.email',
				'user.phone',
				jsonArrayFrom(
					eb.selectFrom('vehicle')
					.innerJoin('company', 'company.id', 'vehicle.company')
					.select((eb) => [
						'vehicle.id',
						jsonArrayFrom(
							eb.selectFrom('availability')
							.whereRef('availability.vehicle', '=', 'vehicle.id')
							.where('availability.endTime', '>', Date.now())
							.select(['availability.id'])
						).as('availabilities'),
						jsonArrayFrom(
							eb.selectFrom('tour')
							.whereRef('tour.vehicle', '=', 'vehicle.id')
							.where('tour.arrival', '>', Date.now())
							.select(['tour.id'])
						).as('tours')
					])
				).as('vehicles'),
				jsonArrayFrom(
					eb.selectFrom('request')
					.innerJoin('tour', 'request.tour', 'tour.id')
					.whereRef('request.customer', '=', 'user.id')
					.where('request.cancelled', '=', false)
					.where('tour.departure', '>', Date.now())
					.select(['request.id'])
				).as('requests')
			])
			.executeTakeFirst();

			if(!user) {
				return;
			}

			for(const v of user.vehicles?.filter((v) => v.availabilities.length != 0)){
				await event.fetch('/taxi/availability/api/availability', {
					method: 'DELETE',
					body: JSON.stringify({ vehicleId: v.id, from: Date.now(), to: LATEST_VALID_TIME })
				})
			};
			if(user.vehicles) {
				if(user.vehicles.flatMap((v) => v.tours).length != 0) {
					return;
				}
			}
			let success = false;
			const maxTries = 100;
			let tries = 0;
			while(!success && tries++ < maxTries) {
				const uuid = uuidv4();
				try {
					await trx.updateTable('user')
					.where('user.id', '=', event.locals.session!.userId)
					.set({
						name: 'gelöschter Nutzer',
						email: uuid,
						passwordHash: uuid,
						isTaxiOwner: false,
						isAdmin: false,
						isEmailVerified: false,
						passwordResetCode: null,
						emailVerificationCode: null,
						emailVerificationExpiresAt: null,
						passwordResetExpiresAt: null,
						phone: null,
						companyId: null
					}).execute();
					await Promise.all(user.requests.map((r) => cancelRequest(r.id, event.locals.session!.userId)));
				} catch(e) {
					continue;
				}
				success = true;
			}
		})
		await invalidateSession(event.locals.session!.id);
		deleteSessionTokenCookie(event);
		return redirect(302, '/');
	}
};
