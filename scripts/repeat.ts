import { exec, spawn } from 'child_process';
import { promisify } from 'util';

const execAsync = promisify(exec);

async function runScriptsInOrder() {
	try {
		console.log('Resetting DB...');
		await execAsync('bash ./scripts/reset-db.sh');
		console.log('DB Reset complete.');

		console.log('Restoring DB...');
		await execAsync('npm run restore');
		console.log('Restore complete.');

		await new Promise((resolve, reject) => {
			const child = spawn('npm', ['run', 'call'], {
				stdio: 'inherit',
				shell: true
			});

			child.on('exit', (code) => {
				if (code === 0) {
					console.log('API Call complete.');
					resolve(undefined);
				} else {
					reject(new Error(`callBookingApi.ts exited with code ${code}`));
				}
			});
		});
	} catch (error) {
		console.error('Error during script execution:', error.stderr || error.message);
		process.exit(1);
	}
}

runScriptsInOrder();
