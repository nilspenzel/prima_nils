import { db } from '$lib/server/db/index.js';
import { jsonArrayFrom } from 'kysely/helpers/postgres';
import type { PageServerLoad, RequestEvent } from './$types.js';
import type { Coordinates } from '$lib/util/Coordinates.js';
import * as fs from 'fs';
import * as readline from 'readline';
import { batchOneToManyCarRouting } from '$lib/server/util/batchOneToManyCarRouting.js';

export const load: PageServerLoad = async (event: RequestEvent) => {
	const url = event.url;
	const tour = "1"//url.searchParams.get('tour');
    let t = undefined;
    let tourId = tour === null ? null : parseInt(tour);
    if(!(tourId !== null && !Number.isNaN(tourId))) {
        return undefined;
    }
    t = await db.selectFrom('tour')
        .innerJoin('vehicle', 'vehicle.id', 'tour.vehicle')
        .innerJoin('company', 'company.id', 'vehicle.company')
        .where('tour.id', '=', tourId)
        .select((eb) => [
            'company.lat as companyLat',
            'company.lng as companyLng',
            jsonArrayFrom(eb.selectFrom('request')
                .innerJoin('event', 'event.request', 'request.id')
                .innerJoin('eventGroup', 'event.eventGroupId', 'eventGroup.id')
                .whereRef('request.tour', '=', 'tour.id')
                .select(['eventGroup.address', 'eventGroup.lat', 'eventGroup.lng', 'eventGroup.scheduledTimeStart', 'eventGroup.scheduledTimeEnd'])
            ).as('events'),
            (eb.selectFrom('tour as earlierTour').whereRef('earlierTour.vehicle', '=', 'tour.vehicle')
            .whereRef('earlierTour.arrival', '<=', 'tour.departure')
            .orderBy('earlierTour.arrival', 'desc')
            .limit(1)
            .select('earlierTour.arrival')).as('lastArrival'),
            (eb.selectFrom('tour as laterTour').whereRef('laterTour.vehicle', '=', 'tour.vehicle')
            .whereRef('laterTour.departure', '>=', 'tour.arrival')
            .orderBy('laterTour.departure', 'desc')
            .limit(1)
            .select('laterTour.departure')).as('firstDeparture')
        ])
        .executeTakeFirst();
        console.log("query done")
    if(t === undefined) {
        return undefined;
    }

    // Return the coordinates promise immediately for streaming
    const coordinatesPromise = processCoordinates(t);

    return {
        coordinates: coordinatesPromise
    };
};

async function processCoordinates(t: any): Promise<{coordinates: Coordinates[], pairs: Coordinates[][]}> {
    const coordinates = await readCoordinates();
    const leeways: number[] = [];
    for(let i=0;i!=t.events.length-1;++i) {
        const prevEvent = t.events[i];
        const nextEvent = t.events[i+1];
        const leeway = prevEvent.scheduledTimeEnd - prevEvent.scheduledTimeStart + nextEvent.scheduledTimeEnd - nextEvent.scheduledTimeStart;
        leeways.push(leeway);
    }
    const maxLeeway = leeways.reduce((acc, curr) => acc = acc < curr ? curr : acc, leeways[0]);

    const forwardQueries: Promise<(number | undefined)[]>[] = [];
    const backwardQueries: Promise<(number | undefined)[]>[] = [];

    for(let i=0;i!=t.events.length-1;++i) {
        const prevEvent = t.events[i];
        const nextEvent = t.events[i+1];
        forwardQueries.push(batchOneToManyCarRouting(prevEvent, coordinates, true, leeways[i]));
        backwardQueries.push(batchOneToManyCarRouting(nextEvent, coordinates, true, leeways[i]));
    }
    const forward = await Promise.all(forwardQueries);
    const backward = await Promise.all(backwardQueries);
    console.log("routing from and to events done")
    
    const possible = new Array<boolean>(coordinates.length);
    for(let i=0;i!=t.events.length-1;++i) {
        for(let j=0;j!=possible.length;++j) {
            const f = forward[i][j];
            const b = backward[i][j];
            if(f !== undefined && b !== undefined && f + b <= leeways[i]) {
                possible[j] = true;
            }
        }
    }
    const pCoordinates = coordinates.filter((_,idx) => possible[idx]);
   const pForward = forward.filter((_,idx) => possible[idx]);
   const pBackward = backward.filter((_,idx) => possible[idx]);
   const results = await Promise.all(pCoordinates.map((c) => batchOneToManyCarRouting(c, pCoordinates, true)));
   const r: Coordinates[][] = new Array<Coordinates[]>(pCoordinates.length);
   for(let i=0;i!=t.events.length-1;++i) {
       for(let j=0;j!==pCoordinates.length;++j) {
        r[j] = new Array<Coordinates>();
           if(!possible[j]) {
               continue;
           }
           const f = pForward[i][j];
           const b = pBackward[i][j];
           if(f === undefined || b === undefined || f + b > leeways[i]) {
               continue;
           }
           for(let k=0;k!==pCoordinates.length;++k) {
               if(!possible[k]) {
                   continue;
               }
               const f2 = pForward[i][k];
               const b2 = pBackward[i][k];
               if(f2 === undefined || b2 === undefined || f + b2 > leeways[i]) {
                   continue;
               }
               const pairDuration = results[j][k];
               if(pairDuration === undefined || f + b2 + pairDuration > leeways[i]) {
                   continue;
               }
               r[j].push(pCoordinates[k]);
           }
       }
   }
    return {coordinates: pCoordinates, pairs: r};
}

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
			isFirstLine = false;
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