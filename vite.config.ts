import { sveltekit } from '@sveltejs/kit/vite';
import { defineConfig } from 'vitest/config';
import { viteStaticCopy } from 'vite-plugin-static-copy';

export default defineConfig({
	plugins: [
		viteStaticCopy({
			targets: [
				{
					src: 'migrations',
					dest: '../'
				}
			]
		}),
		sveltekit()
	],
	test: {
		include: ['src/**/*.{test,spec}.{js,ts}'],
		poolOptions: {
			threads: {
				maxThreads: 1,
				minThreads: 1
			}
		} // Disable parallel threads
	}
});
