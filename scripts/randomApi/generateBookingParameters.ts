import { BookingParameters } from '../../src/lib/server/booking/bookingApi';
import type { ExpectedConnection } from '../../src/lib/server/booking/bookRide';
import type { Capacities } from '../../src/lib/util/booking/Capacities';
import { Coordinates } from '../../src/lib/util/Coordinates';
import { HOUR, MINUTE, DAY } from '../../src/lib/util/time';
import { randomInt } from './randomInt';

export function generateBookingParameters(coordinates: Coordinates[]): BookingParameters {
    return {
        connection1: generateExpectedConnection(coordinates),
        connection2: null,
        capacities: generateCapacities()
    }
}

function generateExpectedConnection(coordinates: Coordinates[]): ExpectedConnection {
    const r1 = randomInt(0, coordinates.length);
    let r2 = r1;
    while(r2 === r1) {
        r2 = randomInt(0, coordinates.length);
    }

    const rt1 = randomInt(Date.now(), Date.now() + DAY * 14 - 2* HOUR);
    const rt2 = randomInt(rt1 + 15 * MINUTE, rt1 + HOUR)
    
    return {
        start: {...coordinates[r1], address: 'generated'},
        target:{...coordinates[r2], address: 'generated'},
        startTime: rt1,
        targetTime: rt2,
        signature: ''
    }
}

function generateCapacities(): Capacities {
    return {
        passengers: randomInt(1, 3),
        bikes: randomInt(0, 1),
        luggage: randomInt(0, 1),
        wheelchairs: randomInt(0, 1)
    }
}
