import { healthCheck } from '../src/lib/server/util/healthCheck';

async function main(): Promise<void> {
	await healthCheck(undefined, undefined, {
		checkJourneyCycles: process.argv.includes('--journey-cycles')
	});
}

// Run the main function
main().catch((error) => {
	console.error('Error in main function:', error);
});
