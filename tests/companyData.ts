import { expect, test, type Page } from '@playwright/test';
import { login, ENTREPENEUR } from './utils';

test.describe.configure({ mode: 'serial' });

const textFields = ['Name', 'Straße', 'Hausnummer', 'Postleitzahl', 'Stadt'];
const selectFields = ['Geminde', 'Pflichtfahrgebiet'];

const setCompanyData = async (page: Page, textData: string[], selectData: string[]) => {
	const enterData = async (field: string, data: string | undefined, isTextField: boolean) => {
		if (data != undefined) {
			if (isTextField) {
				await page.getByLabel(field).fill(data);
			} else {
				await page.getByLabel(field).selectOption({ label: data });
			}
		}
	};

	await login(page, ENTREPENEUR);
	await expect(page.getByRole('heading', { name: 'Stammdaten Ihres Unternehmens' })).toBeVisible();
	textData.forEach((d, i) => enterData(textFields[i], d, true));
	await page.waitForTimeout(250);
	selectData.forEach((d, i) => enterData(selectFields[i], d, false));
	await page.getByRole('button', { name: 'Übernehmen' }).click();
};

test('Set company data, incomplete 1', async ({ page }) => {
	setCompanyData(page, ['Test'], []);

	await expect(page.getByText('Straße zu kurz.')).toBeVisible();
});

test('Set company data, incomplete 2', async ({ page }) => {
	setCompanyData(page, ['Test', 'Werner-Seelenbinder-Straße'], []);

	await expect(page.getByText('Hausnummer zu kurz.')).toBeVisible();
});

test('Set company data, incomplete 3', async ({ page }) => {
	setCompanyData(page, ['Test', 'Werner-Seelenbinder-Straße', '70A'], []);

	await expect(page.getByText('Postleitzahl zu kurz.')).toBeVisible();
});

test('Set company data, incomplete 4', async ({ page }) => {
	setCompanyData(page, ['Test', 'Werner-Seelenbinder-Straße', '70A', '02943'], []);

	await expect(page.getByText('Stadt zu kurz.')).toBeVisible();
});

test('Set company data, incomplete 5', async ({ page }) => {
	setCompanyData(
		page,
		['Test', 'Werner-Seelenbinder-Straße', '70A', '02943', 'Weißwasser/Oberlausitz'],
		[]
	);

	await expect(page.getByText('Gemeinde nicht gesetzt.')).toBeVisible();
});

test('Set company data, incomplete 6', async ({ page }) => {
	setCompanyData(
		page,
		['Test', 'Werner-Seelenbinder-Straße', '70A', '02943', 'Weißwasser/Oberlausitz'],
		[]
	);
	await page.getByLabel('Pflichtfahrgebiet').selectOption({ label: 'Görlitz' });

	await expect(page.getByText('Gemeinde nicht gesetzt.')).toBeVisible();
});

test('Set company data, address not in community', async ({ page }) => {
	setCompanyData(
		page,
		['Taxi Weißwasser', 'Plantagenweg', '3', '02827', 'Görlitz'],
		['Weißwasser/O.L.']
	);

	await expect(
		page.getByText('Die Addresse liegt nicht in der ausgewählten Gemeinde.')
	).toBeVisible();
});

test('Set company data, complete and consistent', async ({ page }) => {
	setCompanyData(
		page,
		['Test', 'Werner-Seelenbinder-Straße', '70A', '02943', 'Weißwasser/Oberlausitz'],
		['Weißwasser/O.L.']
	);

	const checkData = async () => {
		await expect(page.getByLabel('Name')).toHaveValue('Taxi Weißwasser');
		await expect(page.getByLabel('Unternehmenssitz')).toHaveValue(
			'Werner-Seelenbinder-Strasse 70A, 02943 Weißwasser/Oberlausitz'
		);
		await expect(page.getByLabel('Pflichtfahrgebiet')).toHaveValue('2' /* Görlitz */);
		await expect(page.getByLabel('Gemeinde')).toHaveValue('85' /* Weißwasser */);
	};

	await checkData();
	await page.reload();
	await checkData();
});
