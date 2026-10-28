import { defineConfig } from 'vitest/config';
import { sveltekit } from '@sveltejs/kit/vite';

export default defineConfig({
	plugins: [sveltekit()],

	server: {
		watch: {
			ignored: process.env.SIMULATION === 'true' ? ['**/*'] : []
		}
	},

	test: {
		include: ['src/**/*.{test,spec}.{js,ts}'],
		testTimeout: 70_000,
		poolOptions: {
			threads: {
				maxThreads: 1,
				minThreads: 1
			}
		}
	}
});
