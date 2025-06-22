import * as fs from 'fs';
import * as path from 'path';
import { parse } from 'csv-parse/sync';

const M = Math.sqrt(Math.floor(Number.MAX_SAFE_INTEGER / 1000));

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
	if (
		j1.arrival >= j2.arrival &&
		j1.departure <= j2.departure &&
		j1.arrival <= j2.arrival &&
		j1.departure >= j2.departure
	) {
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
		return j.isFirstMileTaxi || j.isLastMileTaxi ? 1 : 0;
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

function createCondition(
	name: string,
	factors: number[],
	parameters: string[],
	rhs: number,
	sense: string
) {
	let condition = name + ':\n';
	for (let i = 0; i != factors.length; ++i) {
		condition +=
			(i === 0 ? factors[i].toString() : Math.abs(factors[i]).toString()) +
			parameters[i] +
			(factors[i + 1] !== undefined ? (factors[i + 1] < 0 ? ' - ' : ' + ') : '');
	}
	condition += ' ' + sense + ' ' + rhs + '\n';
	return condition;
}

function writeMIP(inEntries: JourneyDerivedEntry[][], out: JourneyDerivedEntry[][]) {
	const p_penaltyDirect: string = 'p_penaltyDirect';
	const p_m: string = 'p_m';
	const p_b: string = 'p_b';
	const p_alpha: string = 'p_alpha';
	const p_beta: string = 'p_beta';
	const p_maxDistance: string = 'p_maxDistance';
	const p_transfercostCostDominance: string = 'p_transfercostCostDominance';
	//const p_transfercostProductivityDominance: string = 'p_transfercostProductivityDominance';

	let mip = 'Minimize\n';
	mip += `obj: 0 ${p_alpha}\n`;
	mip += 'Subject To\n';

	const epsilon = 0.000000001;
	const objectiveParameters = [
		p_penaltyDirect,
		p_m,
		p_b,
		p_alpha,
		p_beta,
		p_maxDistance,
		p_transfercostCostDominance
	]; //, p_transfercostProductivityDominance];
	const objectiveBinaries: string[] = [];
	for (let k = 0; k != inEntries.length; ++k) {
		// create inequalities for non-dominance
		const ins = inEntries[k];
		const outs = out[k];
		for (let i = 0; i != ins.length; ++i) {
			for (let j = 0; j != outs.length; ++j) {
				if (equals(ins[i], outs[j])) {
					continue;
				}
				const activityVar = `ndz${j}_${i}`;
				objectiveBinaries.push(activityVar);
				const j1 = ins[i];
				const j2 = outs[j];
				const constants = getConstants(j1, j2);

				mip += createCondition(
					`nb_${k}_${j}_is_not_cost_dominated_by_${i}________`,
					[
						constants.alpha,
						constants.penaltyDirect,
						constants.transfercostCostDominance,
						constants.m,
						constants.b,
						M
					],
					[p_alpha, p_penaltyDirect, p_transfercostCostDominance, p_m, p_b, activityVar],
					j1.ptDuration - j2.ptDuration,
					'>='
				);
				mip += createCondition(
					`nb_${k}_${j}_is_not_productivity_dominated_by_${i}`,
					[constants.beta, constants.transfercostProductivityDominance, M],
					[p_beta, p_transfercostCostDominance, activityVar],
					j1.fullDuration * j1.taxiDuration - j2.fullDuration * j2.taxiDuration,
					'>='
				);
				mip += createCondition(
					`nb_${k}_${j}_and_${i}_are_at_least_maxDist________`,
					[1, -M],
					[p_maxDistance, activityVar],
					M + getDistance(j1, j2),
					'<='
				);
			}
		}

		// create inequalities for dominance
		for (let i = 0; i != ins.length; ++i) {
			const activityVars: string[] = [];
			let skip = false;
			for (let j = 0; j != ins.length; ++j) {
				if (i === j || outs.some((e) => equals(e, ins[i]))) {
					skip = true;
					continue;
				}
				const j1 = ins[j];
				const j2 = ins[i];
				const constants = getConstants(j1, j2);
				const costDomBin = `z${i}_${j}cost`;
				const prodDomBin = `z${i}_${j}prod`;
				objectiveBinaries.push(costDomBin);
				activityVars.push(costDomBin);
				objectiveBinaries.push(prodDomBin);
				activityVars.push(prodDomBin);
				mip += createCondition(
					`nb_${k}_${i}_is_cost_dom_by_${j}___________`,
					[
						constants.alpha,
						constants.penaltyDirect,
						constants.transfercostCostDominance,
						constants.m,
						constants.b,
						-M
					],
					[p_alpha, p_penaltyDirect, p_transfercostCostDominance, p_m, p_b, costDomBin],
					j1.ptDuration - j2.ptDuration - epsilon,
					'<='
				);
				mip += createCondition(
					`nb_${k}_${i}_is_prod_dom_by_${j}___________`,
					[constants.beta, constants.transfercostProductivityDominance, -M],
					[p_beta, p_transfercostCostDominance, prodDomBin],
					j1.fullDuration * j1.taxiDuration - j2.fullDuration * j2.taxiDuration - epsilon,
					'<='
				);
				mip += createCondition(
					`nb_${k}_${i}_and_${j}_are_less_than_maxDist`,
					[1, M, M],
					[p_maxDistance, costDomBin, prodDomBin],
					getDistance(j1, j2) + epsilon,
					'>='
				);
			}
			if (!skip) {
				mip += `nb_${k}_at_least_one_dominator: ${activityVars.join(' + ')} >= 1\n`;
			}
		}
	}
	mip += 'BOUNDS\n';
	mip += '0 <= ' + objectiveParameters.join('\n0 <= ') + '\n';
	if (objectiveBinaries.length > 0) {
		mip += 'Binary\n';
		mip += objectiveBinaries.map((b) => ` ${b}`).join('\n') + '\n';
	}
	mip += 'End\n';
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
	const ins: JourneyEntry[][] = [];
	const outs: JourneyEntry[][] = [];
	for (const [inFile, outFile] of pairs) {
		ins.push(readCsvFile(inFile));
		outs.push(readCsvFile(outFile));
	}
	writeMIP(
		ins.map((d) => derive(d)),
		outs.map((d) => derive(d))
	);
}

const folder = 'scripts/lp';
processFolder(folder);
