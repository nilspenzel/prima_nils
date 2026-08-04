import { db, type Database } from '$lib/server/db';
import { sendNotifications } from '$lib/server/firebase/notifications';
import type { NotificationData } from '$lib/server/firebase/firebase';
import { generateMail, sendOrThrow, type EmailContent } from '$lib/server/sendMail';
import { MINUTE } from '$lib/util/time';
import { sql, type Transaction } from 'kysely';

type EmailPayload = {
	kind: 'email';
	subject: string;
	email: string;
	content: EmailContent;
};

type PushPayload = {
	kind: 'push';
	companyId: number;
	data: NotificationData;
};

type OutboxPayload = EmailPayload | PushPayload;

async function enqueue(
	trx: Transaction<Database>,
	payload: OutboxPayload,
	deduplicationKey?: string
): Promise<void> {
	const now = Date.now();
	await trx
		.insertInto('notificationOutbox')
		.values({
			kind: payload.kind,
			payload,
			deduplicationKey: deduplicationKey ?? null,
			createdAt: now,
			availableAt: now,
			processedAt: null,
			lastError: null
		})
		.onConflict((conflict) => conflict.column('deduplicationKey').doNothing())
		.execute();
}

export async function enqueueMail(
	trx: Transaction<Database>,
	template: unknown,
	subject: string,
	email: string,
	props: unknown,
	deduplicationKey?: string
): Promise<void> {
	await enqueue(
		trx,
		{
			kind: 'email',
			subject,
			email,
			content: generateMail(template, props)
		},
		deduplicationKey
	);
}

export async function enqueuePushNotification(
	trx: Transaction<Database>,
	companyId: number,
	data: NotificationData,
	deduplicationKey?: string
): Promise<void> {
	await enqueue(trx, { kind: 'push', companyId, data }, deduplicationKey);
}

function parsePayload(payload: unknown): OutboxPayload {
	if (typeof payload !== 'object' || payload === null || !('kind' in payload)) {
		throw new Error('Invalid notification outbox payload');
	}
	return payload as OutboxPayload;
}

async function deliver(payload: OutboxPayload): Promise<void> {
	if (payload.kind === 'email') {
		await sendOrThrow(payload.subject, payload.email, payload.content);
		return;
	}
	await sendNotifications(payload.companyId, payload.data);
}

export async function processNotificationOutbox(limit = 100): Promise<number> {
	const now = Date.now();
	const claimed = await db.transaction().execute(async (trx) => {
		const rows = await trx
			.selectFrom('notificationOutbox')
			.select(['id', 'payload'])
			.where('processedAt', 'is', null)
			.where('availableAt', '<=', now)
			.orderBy('id')
			.limit(limit)
			.forUpdate()
			.skipLocked()
			.execute();
		if (rows.length === 0) return rows;

		await trx
			.updateTable('notificationOutbox')
			.set({
				attempts: sql`attempts + 1`,
				availableAt: now + 5 * MINUTE
			})
			.where(
				'id',
				'in',
				rows.map((row) => row.id)
			)
			.execute();
		return rows;
	});

	for (const row of claimed) {
		try {
			await deliver(parsePayload(row.payload));
			await db
				.updateTable('notificationOutbox')
				.set({ processedAt: Date.now(), lastError: null })
				.where('id', '=', row.id)
				.execute();
		} catch (error) {
			const message = error instanceof Error ? error.message : String(error);
			await db
				.updateTable('notificationOutbox')
				.set({ lastError: message })
				.where('id', '=', row.id)
				.execute();
		}
	}
	return claimed.length;
}
