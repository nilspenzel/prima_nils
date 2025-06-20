import * as fs from 'fs';
import * as path from 'path';
import { parse } from 'csv-parse/sync';

interface RouteEntry {
  departure: string;
  arrival: string;
  transfers: number;
  first_mile_mode: string;
  first_mile_duration: string;
  last_mile_mode: string;
  last_mile_duration: string;
}

function readCsvFile(filePath: string): RouteEntry[] {
  const content = fs.readFileSync(filePath, 'utf-8');
  const records = parse(content, {
    columns: true,
    skip_empty_lines: true,
    trim: true,
  });

  return records.map((record: any) => ({
    departure: record.departure,
    arrival: record.arrival,
    transfers: parseInt(record.transfers),
    first_mile_mode: record.first_mile_mode,
    first_mile_duration: record.first_mile_duration,
    last_mile_mode: record.last_mile_mode,
    last_mile_duration: record.last_mile_duration,
  }));
}

function getCsvPairs(folderPath: string): [string, string][] {
  const files = fs.readdirSync(folderPath);
  const inFiles = files.filter(f => f.endsWith('_in.csv'));
  const pairs: [string, string][] = [];

  for (const inFile of inFiles) {
    const baseName = inFile.replace('_in.csv', '');
    const outFile = `${baseName}_out.csv`;
    if (files.includes(outFile)) {
      pairs.push([
        path.join(folderPath, inFile),
        path.join(folderPath, outFile),
      ]);
    }
  }

  return pairs;
}

function processFolder(folderPath: string) {
  const pairs = getCsvPairs(folderPath);

  for (const [inFile, outFile] of pairs) {
    console.log(`\nProcessing Pair:\nIN: ${inFile}\nOUT: ${outFile}`);

    const inData = readCsvFile(inFile);
    const outData = readCsvFile(outFile);

    console.log(`  - IN Rows: ${inData.length}`);
    console.log(`  - OUT Rows: ${outData.length}`);

    // Optional: Compare, merge, or analyze here
    // Example:
    // console.log('First in row:', inData[0]);
    // console.log('First out row:', outData[0]);
  }
}

// Run with the folder path as argument
const folder = process.argv[2];
if (!folder) {
  console.error('Usage: ts-node processCsvPairs.ts <folderPath>');
  process.exit(1);
}

processFolder(folder);
