import { expect, test, type Page } from '@playwright/test';
import { sql } from 'kysely';
import { hashPassword } from '../src/lib/server/auth/password';
import germanTranslations from '../src/lib/i18n/de';
import { HOUR } from '../src/lib/util/time';
import { dayString, execSQL, in6Days, login, RIDE_SHARE_CUSTOMER } from './utils';
import {
	clearE2EData,
	seedAvailability,
	seedUser,
	seedVehicle,
	seedWeisswasserCompany
} from './testData';

let vehicleId: number;

test.beforeEach(async () => {
	await clearE2EData();
	const passwordHash = await hashPassword(RIDE_SHARE_CUSTOMER.password);
	const companyId = await seedWeisswasserCompany();
	await seedUser({
		email: RIDE_SHARE_CUSTOMER.email,
		passwordHash
	});
	vehicleId = await seedVehicle({
		licensePlate: 'GR-RT-11',
		companyId
	});
	await seedAvailability({
		startTime: in6Days.getTime() + HOUR * 3,
		endTime: in6Days.getTime() + HOUR * 23,
		vehicleId
	});
});

async function chooseRoutingLocation(page: Page, label: string, search: string, result: RegExp) {
	await page.getByRole('textbox', { name: label }).click();
	await page.getByRole('combobox', { name: label }).fill(search);
	await page.getByRole('option', { name: result }).first().click();
}

test('retries routing once after a booking error and keeps the notice visible', async ({
	page
}) => {
	let routingRequests = 0;
	page.on('request', (request) => {
		if (new URL(request.url()).pathname === '/api/planAndSign') {
			routingRequests++;
		}
	});

	await login(page, RIDE_SHARE_CUSTOMER);
	await page.goto('/routing');
	await chooseRoutingLocation(page, 'Von', 'schleife', /^\s*Schleife Bahnhof/i);
	await chooseRoutingLocation(page, 'Nach', 'klein prie', /^\s*Klein Priebus/i);
	await page.getByRole('button', { name: /^Los um/ }).click();
	await page.locator('input[type="datetime-local"]').fill(`${dayString}T08:30`);
	await page.keyboard.press('Escape');

	const taxiItinerary = page
		.getByRole('button')
		.filter({ hasText: germanTranslations.booking.bookHere })
		.first();
	await expect(taxiItinerary).toBeVisible({ timeout: 60_000 });
	await taxiItinerary.click();

	const routingRequestsBeforeBooking = routingRequests;
	await execSQL(sql`DELETE FROM availability WHERE vehicle = ${vehicleId}`);

	await page.getByRole('button', { name: germanTranslations.booking.header, exact: true }).click();
	await page
		.getByRole('dialog')
		.getByRole('button', { name: germanTranslations.booking.header, exact: true })
		.click();

	const retryMessage = page.getByText(germanTranslations.bookingRetryMessage, { exact: true });
	await expect(retryMessage).toBeVisible({ timeout: 60_000 });
	await expect.poll(() => routingRequests).toBe(routingRequestsBeforeBooking + 1);
	await expect.poll(() => new URL(page.url()).searchParams.has('bookingError')).toBe(false);

	await page.waitForTimeout(600);
	await expect.poll(() => routingRequests).toBe(routingRequestsBeforeBooking + 1);
	await expect(retryMessage).toBeVisible();

	await page.reload();
	await expect.poll(() => routingRequests).toBe(routingRequestsBeforeBooking + 2);
	await expect(retryMessage).not.toBeVisible();
});
