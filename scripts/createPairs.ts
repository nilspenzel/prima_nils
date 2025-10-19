import type { Coordinates } from '../src/lib/util/Coordinates.js';
import * as fs from 'fs';
import * as readline from 'readline';
import { batchOneToManyCarRouting } from '../src/lib/server/util/batchOneToManyCarRouting.js';
import { HOUR, MINUTE } from '../src/lib/util/time.js';

async function main() {
    const prevEvent = {lat: 51.5446031, lng: 14.5355952, leeway: 60};
    const nextEvent = {lat: 51.454776, lng: 14.95765, leeway: 4000};

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
    const results = await Promise.all(pCoordinates.map((c, idx) => batchOneToManyCarRouting(c, pCoordinates.filter((c2, idx2) => airDistanceCheck(pForward[0][idx]!,pBackward[0][idx2]!,leeways[0],c,c2)), true)));
   const r: Coordinates[][] = new Array<Coordinates[]>(pCoordinates.length);
   for(let i=0;i!=r.length;++i) {
        r[i] = new Array<Coordinates>();
   }
   for(let i=0;i!=t.length-1;++i) {
       for(let j=0;j!==pForward[i].length;++j) {
           const f = pForward[i][j]!;
           let pos = -1;
           for(let k=0;k!==pBackward[i].length;++k) {
               if(airDistanceCheck(pForward[i][j]!,pBackward[i][k]!,leeways[0],pCoordinates[j],pCoordinates[k])){
                   ++pos;
               }else{
                continue;
               }
               const b = pBackward[i][k]!;
               const pairDuration = results[j][pos];
               if(pairDuration === undefined || f + b + pairDuration > leeways[i]*1000) {
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

function airDistanceCheck(prevLeg: number, nextLeg: number, leeway: number, c: Coordinates, c2: Coordinates){
        const dLat = c.lat - c2.lat;
        const dLon = c.lng - c2.lng;
        const metersPerDegLat = 111320;
        const metersPerDegLon = 70000;
        const distance = Math.sqrt(
          (dLat * metersPerDegLat) ** 2 +
          (dLon * metersPerDegLon) ** 2
        );
        const kmh = 80;
        const travelTime = distance * HOUR/ 1000  / kmh;
        return travelTime + prevLeg + nextLeg <= leeway * 1000
}

main().catch((error) => {
	console.error('Error in main function:', error);
});