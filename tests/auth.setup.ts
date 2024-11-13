import { test as setup } from '@playwright/test';
import { ENTREPENEUR, login } from './utils';

setup('authenticate', async ({ page }) => {
	await page.goto('/login');
	await login(page, ENTREPENEUR);
	await page.context().storageState({ path: './tests/auth/user.json' });
});
