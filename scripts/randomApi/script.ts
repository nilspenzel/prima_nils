#!/usr/bin/env ts-node

import 'dotenv/config';
import { bookingApi } from '../../src/lib/server/booking/bookingApi';
import { cancelRequest } from '../../src/lib/server/db/cancelRequest';
import { cancelTour } from '../../src/lib/cancelTour';
//import { moveTour } from '../../src/lib/server/moveTour';
import { addAvailability } from '../../src/lib/server/addAvailability';
//import { removeAvailability } from '../../src/lib/server/removeAvailability';
//import { addVehicle } from '../../src/lib/server/addVehicle';
import { type Coordinates } from '../../src/lib/util/Coordinates';
import { Interval } from '../../src/lib/util/interval';
import { generateBookingParameters } from './generateBookingParameters';
import { randomInt } from './randomInt';
import * as fs from 'fs';
import * as readline from 'readline';
import { DAY } from '../../src/lib/util/time';

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
}

const actionPropabilities: ActionT[] = [
    {action: Action.BOOKING, probability: 0.9, text: 'booking'},
    {action: Action.CANCEL_REQUEST, probability: 0.001, text: 'cancel request'},
    {action: Action.CANCEL_TOUR, probability: 0.001, text: 'cancel tour'},
    {action: Action.MOVE_TOUR, probability: 0.04, text: 'move tour'},
    {action: Action.ADD_AVAILABILITY, probability: 0.04, text: 'add availability'},
    {action: Action.REMOVE_AVAILBILITY, probability: 0.01, text: 'remove availability'},
    {action: Action.ADD_VEHICLE, probability: 0.008, text: 'add vehicle'},
];

async function readCoordinates(): Promise<Coordinates[]> {
    const coordinates: Coordinates[] = [];
    const filepath = './scripts/randomApi/preparedCoords.csv';

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
        throw new Error("No valid coordinates found in the CSV file");
    }

    return coordinates;
}

async function addInitialAvailabilities(company: number, vehicle: number) {
    const interval = new Interval(Date.now(), Date.now() + DAY * 14);
    await addAvailability(interval, company, vehicle);
}


const isActionChosen = (r: number, a: ActionT) => {
    if(r<=a.probability) {
        return true;
    }
    return false;
}

const getAction = (r: number) => {
    let current = r;
    for(const [i, a] of actionPropabilities.entries()){
        if(isActionChosen(current, a)) {
           return i;
        }
        current -= a.probability
    };
    return undefined;
}

async function booking(coordinates: Coordinates[]) {
    const parameters = generateBookingParameters(coordinates);
    const potentialKids = parameters.capacities.passengers - 1;
    const kidsZeroToTwo = randomInt(0, potentialKids);
    const kidsThreeToFour = randomInt(0, potentialKids - kidsZeroToTwo);
    const kidsFiveToSix = randomInt(0, potentialKids - kidsThreeToFour);
    const response = await bookingApi(parameters, 1, true, kidsThreeToFour, kidsThreeToFour, kidsFiveToSix);
    console.log(response.status === 200 ? 'succesful booking' : 'failed to book');
}

async function cancelRequestLocal() {
    //await cancelRequest(0,0);
}

async function cancelTourLocal() {
    //await cancelTour(0,"a");
}

async function moveTourLocal() {
}

async function addAvailabilityLocal() {

}

async function removeAvailabilityLocal() {

}

async function addVehicleLocal() {

}

async function main() {
    const coordinates = await readCoordinates();
    await addInitialAvailabilities(1,1);
    await addInitialAvailabilities(1,2);
    const chosen = Array.from({length: actionPropabilities.length}, (_, i) => 0);
    let errors = 0;
    for(let i=0;i!=500;++i) {
        const r = Math.random();
        console.log("RANDOM API ITERATION: ", i, ' with random value: ', r);
        const actionIdx = getAction(r);
        if(actionIdx === undefined || actionIdx<0 || actionIdx>= actionPropabilities.length) {
            console.log('chose: nothing', {actionIdx}, {r});
            errors++;
            continue;
        }
        const action = actionPropabilities[actionIdx];
        chosen[actionIdx] += 1;
        console.log('Chose:', action.text);
        switch(action.action) {
          case Action.BOOKING: await booking(coordinates); break;
          case Action.CANCEL_REQUEST: await cancelRequestLocal(); break;
          case Action.CANCEL_TOUR: await cancelTourLocal(); break;
          case Action.MOVE_TOUR: await moveTourLocal(); break;
          case Action.ADD_AVAILABILITY: await addAvailabilityLocal(); break;
          case Action.REMOVE_AVAILBILITY: await removeAvailabilityLocal(); break;
          case Action.ADD_VEHICLE: await addVehicleLocal(); break;
        }
        console.log('');
    }
    for(const [i, a] of actionPropabilities.entries()) {
        console.log("action ", a.text, " was chosen ", chosen[i], " times.");
    }
    console.log("There were ", errors, " errors.");
    console.log("RANDOM API END");
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
