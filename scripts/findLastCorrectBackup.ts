import { exec } from 'child_process';
import fs from 'fs';
import path from 'path';
import dotenv from 'dotenv';
import { healthCheck } from './healthCheck/healthCheck';

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
	const fullBackupPath = path.join(BACKUP_FOLDER, fullBackupFile);
	const restoreCommand = `PGPASSWORD=${PGPASSWORD} psql ${DATABASE_URL} -f ${fullBackupPath}`;
	console.log(`Restoring full backup from ${fullBackupFile}...`);
	await executeCommand(restoreCommand);
	console.log(`Full backup restored from ${fullBackupFile}`);
};

const restoreDatabase = async () => {
	try {
		const files = fs.readdirSync(BACKUP_FOLDER);

		const fullBackupFiles = files.filter(
			(file) => file.startsWith('full_backup') && file.endsWith('.sql')
		);

		if (fullBackupFiles.length === 0) {
			console.log('No full backup found. Exiting...');
			return;
		}
		let minBuFileIdx = 0;
		let maxBuFileIdx = fullBackupFiles.length - 1;
		let searchedIdx = -1;
		while (minBuFileIdx != maxBuFileIdx) {
			const middle = (minBuFileIdx + maxBuFileIdx) / 2;
			const backupFile = fullBackupFiles[middle];
			await restoreFullBackup(backupFile);
			if (await healthCheck()) {
				await restoreFullBackup(fullBackupFiles[middle - 1]);
				if (await healthCheck()) {
					searchedIdx = middle - 1;
				} else {
					maxBuFileIdx = middle;
				}
			} else {
				await restoreFullBackup(fullBackupFiles[middle + 1]);
				if (await healthCheck()) {
					searchedIdx = middle;
				} else {
					minBuFileIdx = middle;
				}
			}
		}
		console.log({ searchedIdx });
	} catch (error) {
		console.error('Error during restore:', error);
	}
};

restoreDatabase();
