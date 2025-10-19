import type { Coordinates } from '../src/lib/util/Coordinates.js';
import * as fs from 'fs';
import * as readline from 'readline';
import { batchOneToManyCarRouting } from '../src/lib/server/util/batchOneToManyCarRouting.js';
import { MINUTE } from '../src/lib/util/time.js';

async function main() {
    const prevEvent = {lat: 51.5446031, lng: 14.5355952, leeway: 60};
    const nextEvent = {lat: 51.454776, lng: 14.95765, leeway: 3000};

    const coordinatesPromise = processCoordinates([prevEvent, nextEvent]);

    return {
        coordinates: coordinatesPromise
    };
};

async function processCoordinates(t: (Coordinates&{leeway:number})[]): Promise<{coordinates: Coordinates[], pairs: Coordinates[][]}> {
    const coordinates = await readCoordinates();
    const leeways: number[] = [];
    for(let i=0;i!=t.length-1;++i) {
        const prevEvent = t[i];
        const nextEvent = t[i+1];
        const leeway = prevEvent.leeway + nextEvent.leeway - 2*MINUTE / 1000;
        leeways.push(leeway);
    }

    const forwardQueries: Promise<(number | undefined)[]>[] = [];
    const backwardQueries: Promise<(number | undefined)[]>[] = [];

    for(let i=0;i!=t.length-1;++i) {
        const prevEvent = t[i];
        const nextEvent = t[i+1];
        forwardQueries.push(batchOneToManyCarRouting(prevEvent, coordinates, true, leeways[i]));
        backwardQueries.push(batchOneToManyCarRouting(nextEvent, coordinates, true, leeways[i]));
    }
    const forward = await Promise.all(forwardQueries);
    const backward = await Promise.all(backwardQueries);
    console.log("routing from and to events done")
    
    const possible = new Array<boolean>(coordinates.length);
    for(let i=0;i!=t.length-1;++i) {
        for(let j=0;j!=possible.length;++j) {
            const f = forward[i][j];
            const b = backward[i][j];
            if(f !== undefined && b !== undefined && f + b <= leeways[i] * 1000) {
                possible[j] = true;
            }
        }
    }
    const pCoordinates = coordinates.filter((_,idx) => possible[idx]);
   const pForward = forward.filter((_,idx) => possible[idx]);
   const pBackward = backward.filter((_,idx) => possible[idx]);
   const results = await Promise.all(pCoordinates.map((c) => batchOneToManyCarRouting(c, pCoordinates, true)));
   const r: Coordinates[][] = new Array<Coordinates[]>(pCoordinates.length);
   for(let i=0;i!=t.length-1;++i) {
       for(let j=0;j!==pForward.length;++j) {
        r[j] = new Array<Coordinates>();
           const f = pForward[i][j];
           for(let k=0;k!==pBackward.length;++k) {
               const b = pBackward[i][k];
               const pairDuration = results[j][k];
               if(f === undefined || b === undefined || pairDuration === undefined || f + b + pairDuration > leeways[i]*1000) {
                   continue;
               }
               r[j].push(pCoordinates[k]);
           }
       }
   }
   console.log("lengths", pCoordinates.length, r.reduce((acc,curr) => acc+=curr.length,0))
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

// Run the main function
main().catch((error) => {
	console.error('Error in main function:', error);
});