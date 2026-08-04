import { processNotificationOutbox } from '$lib/server/notificationOutbox';
import { json, type RequestEvent } from '@sveltejs/kit';

export const POST = async (_: RequestEvent) => {
	return json({ processed: await processNotificationOutbox() });
};
