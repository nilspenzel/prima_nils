#!/usr/bin/env ts-node

import 'dotenv/config';
import { bookingApi } from '../../src/lib/server/booking/bookingApi';
import { cancelRequest } from '../../src/lib/server/db/cancelRequest';
import { moveTour } from '../../src/lib/server/moveTour';
import { addAvailability } from '../../src/lib/server/addAvailability';
//import { removeAvailability } from '../../src/lib/server/removeAvailability';
//import { addVehicle } from '../../src/lib/server/addVehicle';
import { getToursWithRequests } from '../../src/lib/server/db/getTours';
import { cancelTour } from '../../src/lib/server/cancelTour';
import { type Coordinates } from '../../src/lib/util/Coordinates';
import { Interval } from '../../src/lib/util/interval';
import { generateBookingParameters } from './generateBookingParameters';
import { randomInt } from './randomInt';
import * as fs from 'fs';
import * as readline from 'readline';
import { DAY } from '../../src/lib/util/time';
import { healthCheck } from '../healthCheck/healthCheck';

enum Action {
	BOOKING,
	CANCEL_REQUEST,
	CANCEL_TOUR,
	MOVE_TOUR,
	ADD_AVAILABILITY,
	REMOVE_AVAILBILITY,
	ADD_VEHICLE
}

type ActionT = {
	action: Action;
	probability: number;
	text: string;
};

const actionProbabilities: ActionT[] = [
	{ action: Action.BOOKING, probability: 0.86, text: 'booking' },
	{ action: Action.CANCEL_REQUEST, probability: 0.02, text: 'cancel request' },
	{ action: Action.CANCEL_TOUR, probability: 0.02, text: 'cancel tour' },
	{ action: Action.MOVE_TOUR, probability: 0.1, text: 'move tour' },
	{ action: Action.ADD_AVAILABILITY, probability: 0, text: 'add availability' },
	{ action: Action.REMOVE_AVAILBILITY, probability: 0, text: 'remove availability' },
	{ action: Action.ADD_VEHICLE, probability: 0, text: 'add vehicle' }
];

async function readCoordinates(): Promise<Coordinates[]> {
	const coordinates: Coordinates[] = [];
	const filepath = './scripts/simulation/preparedCoords.csv';

	const fileStream = fs.createReadStream(filepath);
	const rl = readline.createInterface({
		input: fileStream,
		crlfDelay: Infinity
	});

	let isFirstLine = true;

	for await (const line of rl) {
		if (isFirstLine) {
			isFirstLine = false; // skip header
			continue;
		}

		const parts = line.split(',');
		if (parts.length >= 2) {
			try {
				const lng = parseFloat(parts[0]);
				const lat = parseFloat(parts[1]);

				if (isNaN(lng) || isNaN(lat)) {
					throw new Error('Invalid number');
				}

				coordinates.push({ lng, lat });
			} catch {
				console.warn(`Skipping row due to conversion error: ${line}`);
			}
		}
	}

	if (coordinates.length === 0) {
		throw new Error('No valid coordinates found in the CSV file');
	}

	return coordinates;
}

async function addInitialAvailabilities(company: number, vehicle: number) {
	const interval = new Interval(Date.now(), Date.now() + DAY * 14);
	await addAvailability(interval, company, vehicle);
}

const isActionChosen = (r: number, a: ActionT) => {
	if (r <= a.probability) {
		return true;
	}
	return false;
};

const getAction = (r: number) => {
	let current = r;
	for (const [i, a] of actionProbabilities.entries()) {
		if (isActionChosen(current, a)) {
			return i;
		}
		current -= a.probability;
	}
	return undefined;
};

async function booking(coordinates: Coordinates[]) {
	const parameters = generateBookingParameters(coordinates);
	const potentialKids = parameters.capacities.passengers - 1;
	const kidsZeroToTwo = randomInt(0, potentialKids);
	const kidsThreeToFour = randomInt(0, potentialKids - kidsZeroToTwo);
	const kidsFiveToSix = randomInt(0, potentialKids - kidsThreeToFour);
	const response = await bookingApi(
		parameters,
		1,
		true,
		kidsThreeToFour,
		kidsThreeToFour,
		kidsFiveToSix
	);
	console.log(response.status === 200 ? 'succesful booking' : 'failed to book');
}

async function cancelRequestLocal() {
	const requests = (await getToursWithRequests(false)).flatMap((t) => t.requests.map((r)=> {return{...t, ...r}}));
	if (requests.length === 0) {
		return;
	}
	const r = randomInt(0, requests.length);
	await cancelRequest(requests[r].requestId, requests[r].companyId);
}

async function cancelTourLocal() {
	const tours = await getToursWithRequests(false);
	if (tours.length === 0) {
		return;
	}
	const r = randomInt(0, tours.length);
	await cancelTour(tours[r].tourId, 'message', tours[r].companyId);
}

async function moveTourLocal() {
	const tours = await getToursWithRequests(false);
	if (tours.length === 0) {
		return;
	}
	const r = randomInt(0, tours.length);
	const tour = tours[r];
	await moveTour(tour.tourId, tour.vehicleId, tour.companyId);
}

async function addAvailabilityLocal() {}

async function removeAvailabilityLocal() {}

async function addVehicleLocal() {}

async function main() {
	async function mainLoop(i: number) {
		const r = Math.random();
		console.log('RANDOM API ITERATION: ', i, ' with random value: ', r);
		const actionIdx = getAction(r);
		if (actionIdx === undefined || actionIdx < 0 || actionIdx >= actionProbabilities.length) {
			console.log('chose: nothing', { actionIdx }, { r });
			errors++;
			return;
		}
		const action = actionProbabilities[actionIdx];
		chosen[actionIdx] += 1;
		console.log('Chose:', action.text);
		switch (action.action) {
			case Action.BOOKING:
				await booking(coordinates);
				break;
			case Action.CANCEL_REQUEST:
				await cancelRequestLocal();
				break;
			case Action.CANCEL_TOUR:
				await cancelTourLocal();
				break;
			case Action.MOVE_TOUR:
				await moveTourLocal();
				break;
			case Action.ADD_AVAILABILITY:
				await addAvailabilityLocal();
				break;
			case Action.REMOVE_AVAILBILITY:
				await removeAvailabilityLocal();
				break;
			case Action.ADD_VEHICLE:
				await addVehicleLocal();
				break;
		}
		console.log('');
		if (healthChecks && (await healthCheck())) {
			process.exit(0);
		}
	}

	const probabilitySum = actionProbabilities.reduce((sum, curr) => sum + curr.probability, 0);
	if (probabilitySum !== 1) {
		console.log('The probabilities in actionProbabilies must add to 1 exactly. ', {
			probabilitySum
		});
		process.exit(1);
	}
	let healthChecks = false;
	let runs: number | undefined = undefined;
	let finishTime: number | undefined = undefined;
	let ongoing = false;
	let help = false;

	for (const arg of process.argv) {
		if (arg === '--health') {
			healthChecks = true;
		} else if (arg.startsWith('--runs=')) {
			const value = parseInt(arg.split('=')[1], 10);
			if (isNaN(value) || value <= 0) {
				console.error('Invalid value for --runs. Must be a positive integer.');
				process.exit(1);
			}
			runs = value;
		} else if (arg.startsWith('--seconds=')) {
			const value = parseInt(arg.split('=')[1], 10);
			if (isNaN(value) || value <= 0) {
				console.error('Invalid value for --runs. Must be a positive integer.');
				process.exit(1);
			}
			finishTime = Date.now() + 1000 * value;
		} else if (arg === '--ongoing') {
			ongoing = true;
		} else if (arg === '--help') {
			help = true;
		}
	}
	if (help) {
		console.log('This script simulates possible user actions in the motis-prima-project.');
		console.log(
			'The script will NOT create any companies or vehicles. It will however set all relevant availabilities at the start of the script.'
		);
		console.log(
			'You can adjust the probability of choosing each available action in /scripts/simulation/script.ts. Look for actionProbabilities to do so'
		);
		console.log('The following is a list of currently available simulated user actions:');
		console.log(
			'bookRide:   attempts to book a taxi, you can adjust the random parameters in /scripts/simulation/generateBookingParameters.ts'
		);
		console.log(
			'cancelTour: if there is at least one uncancelled tour, choose a random uncancelled tour and cancel it'
		);
		console.log();
		console.log('The script accepts the following flags:');
		console.log(
			'--health: performs some necessary checks for the database state to be healthy after each simulation action. Will stop if any errors are found. Be aware: the checks take a lot longer than the simulation actions.'
		);
		console.log('--runs=x: Sets the amount of simulation actions to perform');
		console.log('--second=x: Sets the amount of seconds after which the script is terminated');
		console.log(
			'--ongoing: Will run the script indefinitely (or if the health flag is set until there is an error)'
		);
		console.log();
		console.log(
			'If you set more than one of the three flags runs/seconds/ongoing only one of these will be considered with the importance order being ongoing>seconds>runs'
		);
		console.log(
			'If none of these three flags is chosen, the scripts will only perform one simulation action'
		);
		console.log();
		console.log(
			'The lat/lng-pairs used for the bookRide simulation action are derived as follows:'
		);
		console.log(
			'Take the set of all lat/lng-pairs of an osm.pbf file, restrict to those points inside of the Weisswasser multipolygon,'
		);
		console.log(
			'divide the multipolygon into squares with fixed side length, randomly choose at most one lat/lng-pair from each such square'
		);
		process.exit(0);
	}
	const coordinates = await readCoordinates();
	await addInitialAvailabilities(1, 1);
	await addInitialAvailabilities(1, 2);
	const chosen = Array.from({ length: actionProbabilities.length }, (_) => 0);
	let errors = 0;
	if (ongoing) {
		let idx = 0;
		while (true) {
			await mainLoop(idx++);
		}
	} else if (finishTime) {
		let idx = 0;
		while (Date.now() < finishTime) {
			await mainLoop(idx++);
		}
	} else if (runs) {
		for (let i = 0; i != runs; ++i) {
			await mainLoop(i);
		}
	} else {
		await mainLoop(0);
	}
	for (const [i, a] of actionProbabilities.entries()) {
		console.log('action ', a.text, ' was chosen ', chosen[i], ' times.');
	}
	console.log('There were ', errors, ' errors.');
	console.log('RANDOM API END');
}

main().catch((err) => {
	console.error(err);
	process.exit(1);
});
