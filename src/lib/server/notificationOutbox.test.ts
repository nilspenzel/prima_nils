import { clearDatabase } from '$lib/testHelpers';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { db } from '$lib/server/db';
import { TourChange } from '$lib/server/firebase/firebase';
import { enqueuePushNotification, processNotificationOutbox } from '$lib/server/notificationOutbox';

const { sendNotifications } = vi.hoisted(() => ({ sendNotifications: vi.fn() }));
vi.mock('$lib/server/firebase/notifications', () => ({ sendNotifications }));

const notification = {
	tourId: 1,
	pickupTime: 2,
	vehicleId: 3,
	wheelchairs: 0,
	change: TourChange.BOOKED
};

beforeEach(async () => {
	await clearDatabase();
	sendNotifications.mockReset();
});

describe('notification outbox', () => {
	it('delivers notifications only after their transaction commits', async () => {
		await db.transaction().execute(async (trx) => {
			await enqueuePushNotification(trx, 4, notification);
			expect(sendNotifications).not.toHaveBeenCalled();
		});

		expect(sendNotifications).not.toHaveBeenCalled();
		expect(await processNotificationOutbox()).toBe(1);
		expect(sendNotifications).toHaveBeenCalledWith(4, notification);

		const entry = await db
			.selectFrom('notificationOutbox')
			.select(['processedAt', 'attempts'])
			.executeTakeFirstOrThrow();
		expect(entry.processedAt).not.toBeNull();
		expect(entry.attempts).toBe(1);
	});

	it('does not deliver notifications from rolled back transactions', async () => {
		await expect(
			db.transaction().execute(async (trx) => {
				await enqueuePushNotification(trx, 4, notification);
				throw new Error('rollback');
			})
		).rejects.toThrow('rollback');

		expect(await processNotificationOutbox()).toBe(0);
		expect(sendNotifications).not.toHaveBeenCalled();
	});

	it('deduplicates notifications with the same key', async () => {
		await db.transaction().execute(async (trx) => {
			await enqueuePushNotification(trx, 4, notification, 'same-notification');
			await enqueuePushNotification(trx, 4, notification, 'same-notification');
		});

		expect(await processNotificationOutbox()).toBe(1);
		expect(sendNotifications).toHaveBeenCalledTimes(1);
	});

	it('keeps failed notifications for a later retry', async () => {
		sendNotifications.mockRejectedValueOnce(new Error('delivery failed'));
		await db.transaction().execute(async (trx) => {
			await enqueuePushNotification(trx, 4, notification);
		});

		expect(await processNotificationOutbox()).toBe(1);
		let entry = await db
			.selectFrom('notificationOutbox')
			.select(['id', 'processedAt', 'attempts', 'lastError'])
			.executeTakeFirstOrThrow();
		expect(entry.processedAt).toBeNull();
		expect(entry.attempts).toBe(1);
		expect(entry.lastError).toBe('delivery failed');

		await db
			.updateTable('notificationOutbox')
			.set({ availableAt: Date.now() })
			.where('id', '=', entry.id)
			.execute();
		expect(await processNotificationOutbox()).toBe(1);

		entry = await db
			.selectFrom('notificationOutbox')
			.select(['id', 'processedAt', 'attempts', 'lastError'])
			.executeTakeFirstOrThrow();
		expect(entry.processedAt).not.toBeNull();
		expect(entry.attempts).toBe(2);
		expect(entry.lastError).toBeNull();
	});
});
