import { expect, test, type Page } from '@playwright/test';
import {
	login,
	setCompanyData,
	TAXI_OWNER,
	COMPANY1,
	logout
} from './utils';
import dotenv from 'dotenv';

dotenv.config({ path: '.env' });
test.describe.configure({ mode: 'serial' });

async function getClient() {
	const pg = await import('pg');
	const Client = pg.default.Client; 
  return new Client({
    connectionString: process.env.DATABASE_URL,
  });
}

async function getVehicle(licensePlate: string) {
  const client = await getClient();
  await client.connect();
  return await client.query(
    `SELECT id FROM vehicle WHERE license_plate = $1`, [licensePlate]
  );
}

async function insertAvailability(start: number, end: number, vehicle: number) {
  const client = await getClient();
  await client.connect();
  await client.query(
    `INSERT INTO availability (start_time, end_time, vehicle) VALUES ($1, $2, $3)`,
    [start, end, vehicle]
  );
  await client.end();
}

export async function setAvailable(page: Page) {
	await login(page, TAXI_OWNER);

	const v1 = (await getVehicle('GR-TU-11')).rows[0].id;
	const v2 = (await getVehicle('GR-TU-12')).rows[0].id;

	await insertAvailability(new Date('2025-03-10T04:00:00.000Z').getTime(), new Date('2025-03-10T19:45:00.000Z').getTime(), v1);
	await insertAvailability(new Date('2025-03-10T04:00:00.000Z').getTime(), new Date('2025-03-10T19:45:00.000Z').getTime(), v2);

	await insertAvailability(new Date('2025-03-11T04:00:00.000Z').getTime(), new Date('2025-03-11T19:45:00.000Z').getTime(), v1);
	await insertAvailability(new Date('2025-03-11T04:00:00.000Z').getTime(), new Date('2025-03-11T19:45:00.000Z').getTime(), v2);

	await insertAvailability(new Date('2025-03-12T04:00:00.000Z').getTime(), new Date('2025-03-12T19:45:00.000Z').getTime(), v1);
	await insertAvailability(new Date('2025-03-12T04:00:00.000Z').getTime(), new Date('2025-03-12T19:45:00.000Z').getTime(), v2);

	await insertAvailability(new Date('2025-03-13T04:00:00.000Z').getTime(), new Date('2025-03-13T19:45:00.000Z').getTime(), v1);
	await insertAvailability(new Date('2025-03-13T04:00:00.000Z').getTime(), new Date('2025-03-13T19:45:00.000Z').getTime(), v2);

	await insertAvailability(new Date('2025-03-14T04:00:00.000Z').getTime(), new Date('2025-03-14T19:45:00.000Z').getTime(), v1);
	await insertAvailability(new Date('2025-03-14T04:00:00.000Z').getTime(), new Date('2025-03-14T19:45:00.000Z').getTime(), v2);

	await insertAvailability(new Date('2025-03-15T04:00:00.000Z').getTime(), new Date('2025-03-15T19:45:00.000Z').getTime(), v1);
	await insertAvailability(new Date('2025-03-15T04:00:00.000Z').getTime(), new Date('2025-03-15T19:45:00.000Z').getTime(), v2);

	await insertAvailability(new Date('2025-03-16T04:00:00.000Z').getTime(), new Date('2025-03-16T19:45:00.000Z').getTime(), v1);
	await insertAvailability(new Date('2025-03-16T04:00:00.000Z').getTime(), new Date('2025-03-16T19:45:00.000Z').getTime(), v2);
}

export async function setup(page: Page) {
	await setCompanyData(page, TAXI_OWNER, COMPANY1);
	await logout(page);
	await setAvailable(page);
	await logout(page);
}

/* Requirements
- set environment variable SIMULATION_TIME=2025-03-10T00:00:00+0100
- Motis: Use OSM, GTFS and config.yml from this link:
  https://next.hessenbox.de/index.php/s/pHPpdj3aBNarQg9
*/
test('Booking', async ({ page }) => {
	test.setTimeout(50_000);
	const t = new Date('2025-03-10T00:00:00');
	await fetch('http://localhost:5173/api/sendTime', {
		method: 'POST',
		headers: { 'Content-Type': 'application/json' },
		body: JSON.stringify({ t: t.toISOString() })
	});
	await page.clock.setFixedTime(t);

	await setup(page);
	await login(page, TAXI_OWNER);

	// Schleife --> Görlitz (Fwd)
	await page.goto('http://localhost:5173/routing');
	await page.click('#bits-1');
	await page.locator('input[type="datetime-local"]').fill('2025-03-10T10:00');
	await page.keyboard.press('Escape');
	await page.getByRole('textbox', { name: 'Von' }).click();
	await page
		.getByRole('combobox', { name: 'Von' })
		.pressSequentially('Schleife sac', { delay: 50 });
	await page.getByRole('option', { name: 'Schleife Sachsen' }).first().click();
	await page.getByRole('textbox', { name: 'Nach' }).click();
	await page.getByRole('combobox', { name: 'Nach' }).pressSequentially('klein pr', { delay: 50 });
	await page.getByRole('option', { name: 'Klein Priebus' }).first().click();
	await page.getByRole('button', { name: '36 min 0 Umstiege' }).first().click();
	await page.getByRole('button', { name: 'Kostenpflichtig buchen' }).click();
	await page
		.getByLabel('Kostenpflichtig buchen')
		.getByRole('button', { name: 'Kostenpflichtig buchen' })
		.click();

	await page.goto('http://localhost:5173/taxi/availability?offset=-60&date=2025-03-10');
	await expect(page.getByTestId('GR-TU-11-2025-03-10T08:30:00.000Z').locator('div')).toHaveClass(
		/bg-yellow-100/
	);
	await expect(page.getByTestId('GR-TU-11-2025-03-10T08:45:00.000Z').locator('div')).toHaveClass(
		/bg-orange-400/
	);
	await expect(page.getByTestId('GR-TU-11-2025-03-10T09:00:00.000Z').locator('div')).toHaveClass(
		/bg-orange-400/
	);
	await expect(page.getByTestId('GR-TU-11-2025-03-10T09:15:00.000Z').locator('div')).toHaveClass(
		/bg-orange-400/
	);
	await expect(page.getByTestId('GR-TU-11-2025-03-10T09:30:00.000Z').locator('div')).toHaveClass(
		/bg-orange-400/
	);
	await expect(page.getByTestId('GR-TU-11-2025-03-10T09:45:00.000Z').locator('div')).toHaveClass(
		/bg-orange-400/
	);
	await expect(page.getByTestId('GR-TU-11-2025-03-10T10:00:00.000Z').locator('div')).toHaveClass(
		/bg-orange-400/
	);
	await expect(page.getByTestId('GR-TU-11-2025-03-10T10:15:00.000Z').locator('div')).toHaveClass(
		/bg-yellow-100/
	);

	await page.getByTestId('GR-TU-11-2025-03-10T09:45:00.000Z').click();
	await expect(page.getByRole('dialog', { name: 'Tour Details' })).toBeVisible();

	// Görlitz --> Schleife (Bwd)
	await page.goto('http://localhost:5173/routing');
	await page.getByRole('button', { name: 'Los um 00:00' }).click();
	await page.getByRole('radio', { name: 'Ankunft' }).check();
	await page.locator('input[type="datetime-local"]').click();
	await page.locator('input[type="datetime-local"]').fill('2025-03-11T10:00');
	await page.keyboard.press('Escape');
	await page.getByRole('textbox', { name: 'Von' }).click();
	await page.getByRole('combobox', { name: 'Von' }).pressSequentially('klein pr', { delay: 50 });
	await page.getByRole('option', { name: 'Klein Priebus' }).first().click();
	await page.getByRole('textbox', { name: 'Nach' }).click();
	await page
		.getByRole('combobox', { name: 'Nach' })
		.pressSequentially('Schleife sac', { delay: 50 });
	await page.getByRole('option', { name: 'Schleife Sachsen' }).first().click();
	await page.getByRole('button', { name: '37 min 0 Umstiege' }).first().click();
	await page.getByRole('button', { name: 'Kostenpflichtig buchen' }).click();
	await page
		.getByLabel('Kostenpflichtig buchen')
		.getByRole('button', { name: 'Kostenpflichtig buchen' })
		.click();

	await page.getByRole('link', { name: 'Verfügbarkeit' }).click();
	await expect(page.getByTestId('GR-TU-12-2025-03-10T09:30:00.000Z').locator('div')).toHaveClass(
		/bg-yellow-100/
	);
	await expect(page.getByTestId('GR-TU-12-2025-03-10T09:45:00.000Z').locator('div')).toHaveClass(
		/bg-orange-400/
	);
	await expect(page.getByTestId('GR-TU-12-2025-03-10T10:00:00.000Z').locator('div')).toHaveClass(
		/bg-orange-400/
	);
	await expect(page.getByTestId('GR-TU-12-2025-03-10T10:15:00.000Z').locator('div')).toHaveClass(
		/bg-orange-400/
	);
	await expect(page.getByTestId('GR-TU-12-2025-03-10T10:30:00.000Z').locator('div')).toHaveClass(
		/bg-orange-400/
	);
	await expect(page.getByTestId('GR-TU-12-2025-03-10T10:45:00.000Z').locator('div')).toHaveClass(
		/bg-orange-400/
	);
	await expect(page.getByTestId('GR-TU-12-2025-03-10T11:00:00.000Z').locator('div')).toHaveClass(
		/bg-orange-400/
	);
	await expect(page.getByTestId('GR-TU-12-2025-03-10T11:15:00.000Z').locator('div')).toHaveClass(
		/bg-yellow-100/
	);
	await page.getByTestId('GR-TU-12-2025-03-10T10:00:00.000Z').locator('div').click();
	await expect(page.getByRole('dialog', { name: 'Tour Details' })).toBeVisible();
	await page.getByRole('button', { name: 'Close' }).click();

	// Stornieren: Schleife --> Görlitz
	await page.getByRole('link', { name: 'Abrechnung' }).click();
	await expect(page.locator('#searchmask-container')).toContainText(
		'Fahrzeug Abfahrt Ankunft Kunden erschieneneKunden Taxameterstand Einnahmen Status  GR-TU-1110.03.2025, 09:4810.03.2025, 11:03100,00 €0,00 €geplantGR-TU-1210.03.2025, 10:4610.03.2025, 12:01100,00 €0,00 €geplant'
	);
	await page.getByRole('link', { name: 'Verfügbarkeit' }).click();
	await page.getByTestId('GR-TU-11-2025-03-10T09:30:00.000Z').locator('div').click();
	await page.getByText('Stornieren').click();
	await page.getByRole('textbox').fill('Test23');
	await page.getByRole('button', { name: 'Stornieren bestätigen' }).click();

	await expect(page.getByTestId('GR-TU-11-2025-03-10T08:30:00.000Z').locator('div')).toHaveClass(
		/bg-yellow-100/
	);
	await expect(page.getByTestId('GR-TU-11-2025-03-10T08:45:00.000Z').locator('div')).toHaveClass(
		/bg-yellow-100/
	);
	await expect(page.getByTestId('GR-TU-11-2025-03-10T09:00:00.000Z').locator('div')).toHaveClass(
		/bg-yellow-100/
	);
	await expect(page.getByTestId('GR-TU-11-2025-03-10T09:15:00.000Z').locator('div')).toHaveClass(
		/bg-yellow-100/
	);
	await expect(page.getByTestId('GR-TU-11-2025-03-10T09:30:00.000Z').locator('div')).toHaveClass(
		/bg-yellow-100/
	);
	await expect(page.getByTestId('GR-TU-11-2025-03-10T09:45:00.000Z').locator('div')).toHaveClass(
		/bg-yellow-100/
	);
	await expect(page.getByTestId('GR-TU-11-2025-03-10T10:00:00.000Z').locator('div')).toHaveClass(
		/bg-yellow-100/
	);
	await expect(page.getByTestId('GR-TU-11-2025-03-10T10:15:00.000Z').locator('div')).toHaveClass(
		/bg-yellow-100/
	);

	await page.getByRole('link', { name: 'Abrechnung' }).click();
	await page.getByRole('combobox').nth(4).selectOption('0');
	await expect(page.locator('#searchmask-container')).toContainText(
		'Fahrzeug Abfahrt Ankunft Kunden erschieneneKunden Taxameterstand Einnahmen Status  GR-TU-1110.03.2025, 09:4810.03.2025, 11:03100,00 €0,00 €storniert '
	);
	await page.getByRole('combobox').nth(4).selectOption('1');
	await expect(page.locator('#searchmask-container')).toContainText(
		'Fahrzeug Abfahrt Ankunft Kunden erschieneneKunden Taxameterstand Einnahmen Status  GR-TU-1210.03.2025, 10:4610.03.2025, 12:01100,00 €0,00 €geplant'
	);
});
