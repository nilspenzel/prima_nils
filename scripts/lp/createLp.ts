import { getNextWednesday, prepareTest, white } from '../../src/lib/server/booking/tests/util';
import {
    addCompany,
    addTaxi,
    bookingLogs,
    setAvailability,
    Zone,
    type BookingLogs
} from '../../src/lib/testHelpers';
import type { ExpectedConnection } from '../../src/lib/server/booking/bookRide';
import { bookingApi } from '../../src/lib/server/booking/bookingApi';
import { tests } from '../../src/lib/server/booking/tests/generatedTests/testJsons';

import fs from 'fs/promises';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const logFilePath = path.join(__dirname, 'logs.txt');
await fs.writeFile(logFilePath, '');

async function runGeneratedTests() {
    for (const test of tests) {
        const mockUserId = await prepareTest();
        for (const company of test.process.companies) {
            const c = await addCompany(Zone.WEIßWASSER, company);
            for (let taxiIdx = 0; taxiIdx != 10; ++taxiIdx) {
                const taxi = await addTaxi(c, { passengers: 3, luggage: 0, wheelchairs: 0, bikes: 0 });
                await setAvailability(taxi, 0, 8640000000000000);
            }
        }
        const times = test.process.times.map((t) =>
            getNextWednesday(new Date(t), new Date(Date.now()))
        );
        for (let requestIdx = 0; requestIdx != test.process.starts.length; ++requestIdx) {
            const body = JSON.stringify({
                start: test.process.starts[requestIdx],
                target: test.process.destinations[requestIdx],
                startBusStops: [],
                targetBusStops: [],
                directTimes: [times[requestIdx]],
                startFixed: test.process.isDepartures[requestIdx],
                capacities: { passengers: 1, luggage: 0, wheelchairs: 0, bikes: 0 }
            });
            const whiteResponse = await white(body).then((r) => r.json());

            const connection1: ExpectedConnection = {
                start: { ...test.process.starts[requestIdx], address: 'start address' },
                target: { ...test.process.destinations[requestIdx], address: 'target address' },
                startTime: whiteResponse.direct[0].pickupTime,
                targetTime: whiteResponse.direct[0].dropoffTime,
                signature: '',
                startFixed: false
            };

            const bookingBody = {
                connection1,
                connection2: null,
                capacities: { passengers: 1, luggage: 0, wheelchairs: 0, bikes: 0 }
            };

            await bookingApi(bookingBody, mockUserId, true, 0, 0, 0, true);
        }
        bookingLogs.push({iter:-2})
    }

    // Write booking logs for this test
    const logsPerTest = split(bookingLogs, -2);
    for (const [i,testLogs] of logsPerTest.entries()) {
        const logsPerRequest = split(testLogs, -1);
        for(const [j,requestLogs] of logsPerRequest.entries()) {
            requestLogs.sort(
                (log1, log2) =>
                    (log1.cost ?? Number.MAX_SAFE_INTEGER) - (log2.cost ?? Number.MAX_SAFE_INTEGER)
            );
            const logContent = `Test UUID: ${tests[i].uuid}\nrequest index: ${j}\nBooking Logs:\n${JSON.stringify(requestLogs, null, 2)}\n\n`;
            await fs.appendFile(logFilePath, logContent, 'utf8');
        }
    }
}

type Stuff = {
    pickupType: string;
    dropoffType: string, weightedPassengerDuration: number;
    taxiWaitingTime: number;
    taxiDrivingTime: number;
};

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

function writeLp (tests: any) {
    const passenger: string = 'p_passenger';
    const taxi_wait: string = 'p_taxi_wait';
    const taxi_drive: string = 'p_taxi_drive';

    let mip = 'Minimize\n';
    mip += `obj: 0 ${taxi_drive}\n`;
    mip += 'Subject To\n';

    const epsilon = 0.0000001;
    const objectiveParameters = [
        passenger,
        taxi_wait,
        taxi_drive
    ];
    for (const test of tests) {
        const winner: Stuff |undefined= undefined;
        for(const request of test.requests){
            const stuff: Stuff = request.stuff;
            mip += createCondition(
                test.uuid,
                [
                    winner!.weightedPassengerDuration - stuff.weightedPassengerDuration,
                    winner!.taxiDrivingTime - stuff.taxiDrivingTime,
                    winner!.taxiWaitingTime - stuff.taxiWaitingTime
                ],
                [passenger, taxi_wait, taxi_drive],
                -epsilon,
                '<='
            );
        }
    }
}

function split(arr: BookingLogs[], splitVal: number) {
    const result: BookingLogs[][] = [];
    let temp: BookingLogs[] = [];

    for (const item of arr) {
        if (item.iter === splitVal) {
            if (temp.length > 0) {
                result.push(temp);
                temp = [];
            }
        } else {
            temp.push(item);
        }
    }

    if (temp.length > 0) {
        result.push(temp);
    }

    return result;
}

// Run the function and handle errors
runGeneratedTests().catch((err) => {
    console.error('❌ Error during generated test run:', err);
    process.exit(1);
});

//writeLp();
