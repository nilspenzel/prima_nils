import { oneToMany } from '$lib/api';
import type { BusStop } from '$lib/busStop';
import type { Company } from '$lib/compositionTypes';
import { Coordinates } from '$lib/location';
import type { Range } from './capacitySimulation';
import { iterateAllInsertions, samePlace } from './utils';

export type InsertionRoutingResult = {
	company: (number | undefined)[];
	event: (number | undefined)[];
};

export type RoutingResults = {
	busStops: InsertionRoutingResult[];
	userChosen: InsertionRoutingResult;
};

export function gatherRoutingCoordinates(
	companies: Company[],
	insertionsByVehicle: Map<number, Range[]>
) {
	if (companies.length == 0) {
		return { forward: [], backward: [] };
	}
	const backward = new Array<Coordinates>();
	const forward = new Array<Coordinates>();
	companies.forEach((company) => {
		forward.push(company.coordinates);
		backward.push(company.coordinates);
	});
	iterateAllInsertions(companies, insertionsByVehicle, (insertionInfo, _insertionCounter) => {
		const vehicle = insertionInfo.vehicle;
		const idxInEvents = insertionInfo.idxInEvents;
		if (idxInEvents != 0) {
			backward.push(vehicle.events[idxInEvents - 1].coordinates);
		} else if (vehicle.lastEventBefore != undefined) {
			backward.push(vehicle.lastEventBefore.coordinates);
		}
		if (idxInEvents != vehicle.events.length) {
			forward.push(vehicle.events[idxInEvents].coordinates);
		} else if (vehicle.firstEventAfter != undefined) {
			forward.push(vehicle.firstEventAfter.coordinates);
		}
	});
	return { forward, backward };
}

export async function routing(
	companies: Company[],
	many: { forward: Coordinates[]; backward: Coordinates[] },
	userChosen: Coordinates,
	busStops: BusStop[],
	startFixed: boolean
): Promise<RoutingResults> {
	const findMatchingPlaces = (
		coordinates: Coordinates,
		many: Coordinates[],
		routingResult: (number | undefined)[]
	) => {
		console.assert(many.length == routingResult.length);
		for (let i = 0; i != many.length; ++i) {
			if (samePlace(coordinates, many[i])) {
				routingResult[i] = 0;
			}
		}
	}; //startFixed == many to one
	const userChosenMany = startFixed ? many.backward : many.forward;
	const busStopMany = !startFixed ? many.backward : many.forward;
	const userChosenResult = await oneToMany(userChosen, userChosenMany, !startFixed);
	findMatchingPlaces(userChosen, userChosenMany, userChosenResult);
	const ret = {
		userChosen: {
			company: userChosenResult.slice(0, companies.length),
			event: userChosenResult.slice(companies.length)
		},
		busStops: new Array<InsertionRoutingResult>(busStops.length)
	};
	const busStopQueries = new Array<Promise<(number | undefined)[]>>(busStops.length);
	for (let busStopIdx = 0; busStopIdx != busStops.length; ++busStopIdx) {
		busStopQueries[busStopIdx] = oneToMany(
			busStops[busStopIdx].coordinates,
			busStopMany,
			startFixed
		);
	}
	const busStopResults = await Promise.all(busStopQueries);
	for (let busStopIdx = 0; busStopIdx != busStops.length; ++busStopIdx) {
		findMatchingPlaces(busStops[busStopIdx].coordinates, busStopMany, busStopResults[busStopIdx]);
		ret.busStops[busStopIdx] = {
			company: busStopResults[busStopIdx].slice(0, companies.length),
			event: busStopResults[busStopIdx].slice(companies.length)
		};
	}
	const inNiesky1 = new Coordinates(51.29468377345111, 14.833542206420248);
	const inNiesky2 = new Coordinates(51.29544187321241, 14.820560314788537);
	const inNiesky3 = new Coordinates(51.294046423258095, 14.820774891510126);
	const nieskies = [inNiesky1, inNiesky2, inNiesky3];
	const getString=(c:Coordinates)=>{
		const n = nieskies.map((nn) => samePlace(nn, c));
		const n2 = ["inNiesky1", "inNiesky2", "inNiesky3"];
		console.assert(n.filter((nn) => nn).length < 2);
		const m = n.indexOf(true);
		if(m==undefined){
			return "undef";
		}
		return n2[m];
	};
	//console.log(getString(userChosen), " user company ", ret.userChosen.company);
	//console.log(getString(busStops[0].coordinates), " bus company ", ret.userChosen.company);
	//console.log("USER: ", getString(userChosen), startFixed);
	//for(let i=0;i!=userChosenMany.length;++i){
	//	console.log(getString(userChosenMany[i]), " ",i==0?ret.userChosen.company:ret.userChosen.event[i-1]);
	//}
	//console.log("BUS: ", getString(busStops[0].coordinates), !startFixed);
	//for(let i=0;i!=busStopMany.length;++i){
	//	console.log(getString(busStopMany[i]), " ",i==0?ret.busStops[0].company:ret.busStops[0].event[i-1]);
	//}
	return ret;
}
