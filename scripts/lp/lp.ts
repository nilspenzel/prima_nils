import * as fs from 'fs';
import * as path from 'path';
import { parse } from 'csv-parse/sync';

const M = Number.MAX_SAFE_INTEGER / 1000;

interface JourneyEntry {
	departure: number;
	arrival: number;
	transfers: number;
	isFirstMileTaxi: boolean;
	first_mile_duration: number;
	isLastMileTaxi: boolean;
	last_mile_duration: number;
}

type JourneyDerivedEntry = JourneyEntry & {
	fullDuration: number;
	taxiDuration: number;
	ptDuration: number;
};

function equals(j1: JourneyDerivedEntry, j2: JourneyDerivedEntry) {
	return (
		j1.departure === j2.departure &&
		j1.arrival == j2.arrival &&
		j1.transfers === j2.transfers &&
		j1.isFirstMileTaxi === j2.isFirstMileTaxi &&
		j1.first_mile_duration === j2.first_mile_duration &&
		j1.isLastMileTaxi === j2.isLastMileTaxi &&
		j1.last_mile_duration === j2.last_mile_duration
	);
}

function readCsvFile(filePath: string) {
	const content = fs.readFileSync(filePath, 'utf-8');
	const records = parse(content, {
		columns: true,
		skip_empty_lines: true,
		trim: true
	});

	const entries: JourneyEntry[] = records.map((record: any) => ({
		departure: new Date(record.departure).getTime() / 60000,
		arrival: new Date(record.arrival).getTime() / 60000,
		transfers: parseInt(record.transfers),
		isFirstMileTaxi: record.first_mile_mode === 'taxi',
		first_mile_duration: parseInt(record.first_mile_duration),
		isLastMileTaxi: record.last_mile_mode === 'taxi',
		last_mile_duration: parseInt(record.last_mile_duration)
	}));
	return entries;
}

function derive(entries: JourneyEntry[]) {
	return entries.map((e) => {
		const fullDuration = e.arrival - e.departure;
		const taxiDuration =
			(e.isLastMileTaxi ? e.last_mile_duration : 0) +
			(e.isFirstMileTaxi ? e.first_mile_duration : 0);
		return {
			...e,
			fullDuration,
			taxiDuration,
			ptDuration: fullDuration - taxiDuration
		};
	});
}

function getDistance(j1: JourneyEntry, j2: JourneyEntry) {
	if((j1.arrival>=j2.arrival && j1.departure<=j2.departure) && (j1.arrival<=j2.arrival && j1.departure>=j2.departure)) {
		return 0;
	}
	return Math.min(Math.abs(j1.arrival - j2.arrival), Math.abs(j1.departure - j2.departure));
}

function getCostDominanceAlphaTerm(j1: JourneyDerivedEntry, j2: JourneyDerivedEntry) {
	return (getDistance(j1, j2) * j1.fullDuration) / j2.fullDuration;
}

function getProductivityDominanceBetaTerm(j1: JourneyDerivedEntry, j2: JourneyDerivedEntry) {
	return j1.taxiDuration * getDistance(j1, j2);
}

type Constants = {
	penaltyDirect: number;
	m: number;
	b: number;
	alpha: number;
	beta: number;
	transfercostCostDominance: number;
	transfercostProductivityDominance: number;
};

function getConstants(j1: JourneyDerivedEntry, j2: JourneyDerivedEntry): Constants {
	function toTaxiMileCount(j: JourneyDerivedEntry) {
		return (j.isFirstMileTaxi || j.isLastMileTaxi ? 1 : 0);
	}
	return {
		penaltyDirect: j2.taxiDuration === j2.fullDuration ? 1 : 0,
		alpha: getCostDominanceAlphaTerm(j1, j2),
		transfercostCostDominance: j1.transfers - j2.transfers,
		transfercostProductivityDominance:
			j1.transfers * j1.taxiDuration - j2.transfers * j2.taxiDuration,
		beta: getProductivityDominanceBetaTerm(j1, j2),
		m: j1.taxiDuration - j2.taxiDuration,
		b: toTaxiMileCount(j1) - toTaxiMileCount(j2)
	};
}

function writeMIP(inEntries: JourneyDerivedEntry[], out: JourneyDerivedEntry[]) {
	let mip = 'Minimize\n';
	mip += '1\n';
	mip += 'Subject To\n';

	const p_penaltyDirect: string = 'p_penaltyDirect';
	const p_m: string = 'p_m';
	const p_b: string = 'p_b';
	const p_alpha: string = 'p_alpha';
	const p_beta: string = 'p_beta';
	const p_maxDistance: string = 'p_maxDistance';
	const p_transfercostCostDominance: string = 'p_transfercostCostDominance';
	const p_transfercostProductivityDominance: string = 'p_transfercostProductivityDominance';

	// create inequalities for non-dominance
	for (let i = 0; i != inEntries.length; ++i) {
		for (let j = 0; j != out.length; ++j) {
			if (equals(inEntries[i], out[j])) {
				continue;
			}
			const j1 = inEntries[i];
			const j2 = out[j];
			const constants = getConstants(j1,j2);
			mip += `${i} is not cost dominated by ${j}        : ${constants.alpha}${p_alpha} + ${constants.penaltyDirect}${p_penaltyDirect} + ${constants.transfercostCostDominance}${p_transfercostCostDominance} + ${constants.m}${p_m} + ${constants.b}${p_b} >= ${j1.ptDuration -j2.ptDuration}\n`;
			mip += `${i} is not productivity dominated by ${j}: ${constants.beta}${p_beta} + ${constants.transfercostProductivityDominance}${p_transfercostProductivityDominance} >= ${j1.fullDuration*j1.taxiDuration - j2.fullDuration*j2.taxiDuration}\n`;
			mip += `${i} and ${j} are at least maxDist        : ${p_maxDistance} <= ${getDistance(j1,j2)}\n`
		}
	}

	const binaries: string[] = [];
	// create inequalities for dominance
	for (let i = 0; i != inEntries.length; ++i) {
		const activityVars: string[] = [];
		for (let j = 0; j != inEntries.length; ++j) {
			if (i === j || out.some((e) => equals(e, inEntries[i]))) {
				continue;
			}
			const j1 = inEntries[j];
			const j2 = inEntries[i];
			const constants = getConstants(j1,j2);
			const costDomBin = `z${i}_${j}cost`;
			const prodDomBin = `z${i}_${j}prod`;
			binaries.push(costDomBin);
			activityVars.push(costDomBin);
			binaries.push(prodDomBin);
			activityVars.push(prodDomBin);
			mip += `${i} is cost dom by ${j}           : ${constants.alpha}${p_alpha} + ${constants.penaltyDirect}${p_penaltyDirect} + ${constants.transfercostCostDominance}${p_transfercostCostDominance} + ${constants.m}${p_m} + ${constants.b}${p_b} - ${M}${costDomBin} < ${j1.ptDuration -j2.ptDuration}\n`;
			mip += `${i} is prod dom by ${j}           : ${constants.beta}${p_beta} + ${constants.transfercostProductivityDominance}${p_transfercostProductivityDominance} -${M}${prodDomBin} < ${j1.fullDuration*j1.taxiDuration - j2.fullDuration*j2.taxiDuration}\n`;
			mip += `${i} and ${j} are less than maxDist: ${p_maxDistance} > ${getDistance(j1,j2)} - ${M}(${costDomBin} + ${prodDomBin})\n`
		}
		mip += `at least one dominator: ${activityVars.join(' + ')}>= 1\n`;
	}

	if (binaries.length > 0) {
		mip += 'Binary\n';
		mip += binaries.map((b) => ` ${b}`).join('\n') + '\n';
	}
	mip += 'End\n';
	console.log({ mip });
	const outputPath = path.join(__dirname, 'model.lp');
	fs.writeFileSync(outputPath, mip, 'utf-8');
}

function getCsvPairs(folderPath: string): [string, string][] {
	const files = fs.readdirSync(folderPath);
	const inFiles = files.filter((f) => f.endsWith('_in.csv'));
	const pairs: [string, string][] = [];

	for (const inFile of inFiles) {
		const baseName = inFile.replace('_in.csv', '');
		const outFile = `${baseName}_out.csv`;
		if (files.includes(outFile)) {
			pairs.push([path.join(folderPath, inFile), path.join(folderPath, outFile)]);
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
		writeMIP(derive(inData), derive(outData));
	}
}

const folder = 'scripts/lp';
processFolder(folder);
