import type { Company, Vehicle } from './types';
import { Coordinates, Location } from './location';
import { MAX_MATCHING_DISTANCE, MAX_TRAVEL_SECONDS, MOTIS_BASE_URL } from './constants';
import { coordinatesToPlace, coordinatesToStr } from './motisUtils';
import { type Duration, type PlanResponse } from './motis/types.gen';
import { oneToMany as oneToManyMotis, plan as planMotis } from './motis/services.gen';
import { secondsToMs } from './time_utils';
import type { Capacities } from './capacities';
import type { BusStop } from './busStop';
import { type RequestEvent } from '@sveltejs/kit';
import type { QuerySerializerOptions } from '@hey-api/client-fetch';
import { samePlace } from './bookingAPI/utils';

export const getCompany = async (id: number): Promise<Company> => {
	const response = await fetch(`/api/company?id=${id}`);
	return await response.json();
};

export const getVehicles = async (company_id: number): Promise<Vehicle[]> => {
	const response = await fetch(`/api/vehicle?company=${company_id}`);
	return await response.json();
};

interface Message {
	message: string;
}

export const addVehicle = async (
	license_plate: string,
	seats: number,
	wheelchair_capacity: number,
	bike_capacity: number,
	storage_space: number
): Promise<[boolean, Message]> => {
	const response = await fetch('/api/vehicle', {
		method: 'POST',
		body: JSON.stringify({
			license_plate,
			seats,
			wheelchair_capacity,
			bike_capacity,
			storage_space
		})
	});
	return [response.ok, await response.json()];
};

export const updateTour = async (tourId: number, vehicleId: number) => {
	return await fetch('/api/tour', {
		method: 'POST',
		body: JSON.stringify({
			tour_id: tourId,
			vehicle_id: vehicleId
		})
	});
};

export const removeAvailability = async (vehicleId: number, from: Date, to: Date) => {
	return await fetch('/api/availability', {
		method: 'DELETE',
		body: JSON.stringify({
			vehicleId,
			from,
			to
		})
	});
};

export const addAvailability = async (vehicleId: number, from: Date, to: Date) => {
	return await fetch('/api/availability', {
		method: 'POST',
		body: JSON.stringify({
			vehicleId,
			from,
			to
		})
	});
};

export const booking = async (
	event: RequestEvent,
	from: Location,
	to: Location,
	startFixed: boolean,
	timeStamp: Date,
	numPassengers: number,
	numWheelchairs: number,
	numBikes: number,
	luggage: number
) => {
	const connection = {
		start: from,
		target: to,
		startTime: timeStamp,
		targetTime: timeStamp
	};
	return await event.fetch('/api/booking', {
		method: 'POST',
		body: JSON.stringify({
			connection1: startFixed ? connection : null,
			connection2: !startFixed ? connection : null,
			capacities: {
				wheelchairs: numWheelchairs,
				bikes: numBikes,
				passengers: numPassengers,
				luggage
			}
		})
	});
};

export const booking2 = async (
	from: Location,
	to: Location,
	startFixed: boolean,
	timeStamp: Date,
	numPassengers: number,
	numWheelchairs: number,
	numBikes: number,
	luggage: number
) => {
	return await fetch('/api/booking', {
		method: 'POST',
		body: JSON.stringify({
			connection1: {
				start: from,
				target: to,
				startTime: timeStamp,
				targetTime: timeStamp
			},
			connection2: null,
			capacities: {
				wheelchairs: numWheelchairs,
				bikes: numBikes,
				passengers: numPassengers,
				luggage
			}
		})
	});
};

export const reassignTour = async (tourId: number) => {
	console.log('TODO: reassign tour:', tourId);
	return false;
};

export const plan = (from: Coordinates, to: Coordinates): Promise<PlanResponse> => {
	return planMotis({
		baseUrl: MOTIS_BASE_URL,
		query: {
			fromPlace: coordinatesToPlace(from),
			toPlace: coordinatesToPlace(to),
			directModes: ['CAR'],
			transitModes: [],
			maxDirectTime: MAX_TRAVEL_SECONDS
		}
	}).then((d) => d.data!);
};

export const oneToMany = async (
	one: Coordinates,
	many: Coordinates[],
	arriveBy: boolean
): Promise<(number | undefined)[]> => {
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
	};/*
	console.log((await oneToManyMotis({
		baseUrl: MOTIS_BASE_URL,
		querySerializer: { array: { explode: false } } as QuerySerializerOptions,
		query: {
			one: coordinatesToStr(one),
			many: many.map(coordinatesToStr),
			max: MAX_TRAVEL_SECONDS,
			maxMatchingDistance: MAX_MATCHING_DISTANCE,
			mode: 'CAR',
			arriveBy
		}
	})).request.url);*/
	return await oneToManyMotis({
		baseUrl: MOTIS_BASE_URL,
		querySerializer: { array: { explode: false } } as QuerySerializerOptions,
		query: {
			one: coordinatesToStr(one),
			many: many.map(coordinatesToStr),
			max: MAX_TRAVEL_SECONDS,
			maxMatchingDistance: MAX_MATCHING_DISTANCE,
			mode: 'CAR',
			arriveBy
		}
	}).then((res) => {
		if (res.data == undefined) {
			console.log('oneToMany data was undefined.');
			return Array(many.length).fill(undefined);
		}
		for(let i=0;i!=many.length;++i){
			//console.log((arriveBy ? ""+getString(many[i])+"->"+getString(one):""+getString(one)+"->"+getString(many[i]))+ "   "+ res.data[i].duration)
		}
		return res.data!.map((d: Duration) => {
			return d.duration != undefined && d.duration != null ? secondsToMs(d.duration) : undefined;
		});
	});
};

export const wl = async (
	event: RequestEvent,
	start: Coordinates,
	target: Coordinates,
	startFixed: boolean,
	times: Date[],
	capacities: Capacities,
	startBusStops: BusStop[],
	targetBusStops: BusStop[]
) => {
	return await event.fetch('/api/whitelist', {
		method: 'POST',
		body: JSON.stringify({
			start,
			target,
			startBusStops,
			targetBusStops,
			times,
			startFixed,
			capacities
		})
	});
};
