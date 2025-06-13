import { exec } from 'child_process';
import fs from 'fs';
import path from 'path';
import dotenv from 'dotenv';
import { healthCheck } from './healthCheck/healthCheck';

const sleep = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));

dotenv.config();

const __dirname = new URL('.', import.meta.url).pathname;

const BACKUP_FOLDER = path.join(__dirname, '..', 'db_backups');

const DATABASE_URL = process.env.DATABASE_URL;
const PGPASSWORD = process.env.PGPASSWORD;

const executeCommand = (command: string): Promise<void> => {
	return new Promise((resolve, reject) => {
		exec(command, (error, stdout, stderr) => {
			if (error) {
				reject(`Error: ${stderr || stdout}`);
			} else {
				resolve();
			}
		});
	});
};

const restoreFullBackup = async (fullBackupFile: string) => {
	await sleep(1000);

	console.log('Dropping and recreating the database...');
	await executeCommand(`echo "DROP DATABASE prima;" | psql ${DATABASE_URL}`);
	await executeCommand(`echo "CREATE DATABASE prima;" | psql ${DATABASE_URL}`);

	console.log('Running latest migrations...');
	await executeCommand('pnpm run kysely migrate:latest');

	const fullBackupPath = path.join(BACKUP_FOLDER, fullBackupFile);
	const restoreCommand = `PGPASSWORD=${PGPASSWORD} psql ${DATABASE_URL} -f ${fullBackupPath}`;
	console.log(`Restoring full backup from ${fullBackupFile}...`);
	await executeCommand(restoreCommand);
	console.log(`Full backup restored from ${fullBackupFile}`);
};

const findLastCorrectBackup = async () => {
	try {
		const files = fs.readdirSync(BACKUP_FOLDER);

		const fullBackupFiles = files.filter(
			(file) => file.startsWith('full_backup') && file.endsWith('.sql')
		);

		if (fullBackupFiles.length === 0) {
			console.log('No full backup found. Exiting...');
			return;
		}
		fullBackupFiles.sort((f1, f2) => (f1 < f2 ? -1 : 1));
		let minBuFileIdx = 0;
		let maxBuFileIdx = fullBackupFiles.length - 1;
		let searchedIdx = -1;
		let updateMin = false;
		let updateMax = false;
		while (minBuFileIdx != maxBuFileIdx) {
			const middle = Math.floor((minBuFileIdx + maxBuFileIdx) / 2);
			console.log({ minBuFileIdx }, { maxBuFileIdx }, { middle });
			const backupFile = fullBackupFiles[middle];
			await restoreFullBackup(backupFile);
			if (await healthCheck()) {
				await restoreFullBackup(fullBackupFiles[middle - 1]);
				if (!(await healthCheck())) {
					searchedIdx = middle - 1;
					console.log({ searchedIdx }, { file: fullBackupFiles[middle - 1] });
					return;
				} else {
					maxBuFileIdx = middle;
					updateMax = true;
				}
			} else {
				await restoreFullBackup(fullBackupFiles[middle + 1]);
				if (await healthCheck()) {
					searchedIdx = middle;
					console.log({ searchedIdx }, { file: fullBackupFiles[middle + 1] });
					return;
				} else {
					minBuFileIdx = middle + 1;
					updateMin = true;
				}
			}
		}
		console.log('no error found', { updateMax }, { updateMin });
	} catch (error) {
		console.error('Error during restore:', error);
	}
};

findLastCorrectBackup();
