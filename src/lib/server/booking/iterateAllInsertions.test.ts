import { describe, it, expect } from 'vitest';
import { iterateAllInsertions } from './iterateAllInsertions';
import { routing } from './routing';
import type { Company, Event, VehicleWithInterval } from './getBookingAvailability';
import { type VehicleId } from './VehicleId';
import type { Range } from '$lib/util/booking/getPossibleInsertions';
import { oneToManyCarRouting } from '../util/oneToManyCarRouting';
import { Interval } from '$lib/util/interval';

const inRothenburg1 = { lng: 14.962964035976825, lat: 51.34030696433544 };
const inRothenburg2 = { lng: 14.96375266477358, lat: 51.335866895211666 };
const inHorka1 = { lng: 14.89811075304624, lat: 51.30115190837412 };
const inGehege = { lng: 14.944479873593451, lat: 51.32191394274318 };

function eventFromCoord(coord: { lat: number; lng: number; tourId: number }, id: number): Event {
	return {
		lat: coord.lat,
		lng: coord.lng,
		departure: 0,
		arrival: 0,
		directDuration: 0,
		id,
		isPickup: true,
		scheduledTimeStart: 0,
		scheduledTimeEnd: 0,
		communicatedTime: 0,
		prevLegDuration: 0,
		nextLegDuration: 0,
		eventGroup: '',
		passengers: 1,
		wheelchairs: 0,
		bikes: 0,
		luggage: 0,
		tourId: coord.tourId,
		time: new Interval(0, 1)
	};
}

function vehicleFromEvents(events: Event[], id: number): VehicleWithInterval {
	return {
		events,
		availabilities: [],
		tours: [],
		passengers: 1,
		wheelchairs: 0,
		bikes: 0,
		luggage: 0,
		lastEventBefore: undefined,
		firstEventAfter: undefined,
		id
	};
}

function companyFromVehicles(vehicles: VehicleWithInterval[]): Company {
	return {
		id: 1,
		vehicles,
		lat: inHorka1.lat,
		lng: inHorka1.lng,
		zoneId: 1
	};
}

describe('IterateAllInsertions tests', () => {
	it('test IterateAllInsertions', async () => {
		const events: Event[] = [{ ...inRothenburg1, tourId: 1 }].map((e, i) => eventFromCoord(e, i));
		const vehicles: VehicleWithInterval[] = [events].map((e, i) => vehicleFromEvents(e, i));
		const companies: Company[] = [companyFromVehicles(vehicles)];
		const insertions = new Map<VehicleId, Range[]>();
		insertions.set(0, [{ earliestPickup: 0, latestDropoff: 1 }]);
		const userChosen = inRothenburg2;
		const busStops = [{ ...inGehege, times: [] }];
		const routingResults = await routing(companies, userChosen, busStops, insertions);
		const toUserChosenEvent: Promise<(number | undefined)[]>[] = [];
		const toUserChosenCompany: Promise<(number | undefined)[]>[] = [];
		const toUserChosenPredEvent: Promise<(number | undefined)[]>[] = [];
		const fromUserChosenEvent: Promise<(number | undefined)[]>[] = [];
		const fromUserChosenCompany: Promise<(number | undefined)[]>[] = [];
		const fromUserChosenPostEvent: Promise<(number | undefined)[]>[] = [];
		const toBusStopEvent = new Array<Promise<(number | undefined)[]>[]>(busStops.length);
		const toBusStopCompany = new Array<Promise<(number | undefined)[]>[]>(busStops.length);
		const toBusStopPredEvent = new Array<Promise<(number | undefined)[]>[]>(busStops.length);
		const fromBusStopEvent = new Array<Promise<(number | undefined)[]>[]>(busStops.length);
		const fromBusStopCompany = new Array<Promise<(number | undefined)[]>[]>(busStops.length);
		const fromBusStopPostEvent = new Array<Promise<(number | undefined)[]>[]>(busStops.length);
		const toUserChosenEventRR: (number | undefined)[] = [];
		const toUserChosenCompanyRR: (number | undefined)[] = [];
		const toUserChosenPredEventRR: (number | undefined)[] = [];
		const fromUserChosenEventRR: (number | undefined)[] = [];
		const fromUserChosenCompanyRR: (number | undefined)[] = [];
		const fromUserChosenPostEventRR: (number | undefined)[] = [];
		const toBusStopEventRR = new Array<(number | undefined)[]>(busStops.length);
		const toBusStopCompanyRR = new Array<(number | undefined)[]>(busStops.length);
		const toBusStopPredEventRR = new Array<(number | undefined)[]>(busStops.length);
		const fromBusStopEventRR = new Array<(number | undefined)[]>(busStops.length);
		const fromBusStopCompanyRR = new Array<(number | undefined)[]>(busStops.length);
		const fromBusStopPostEventRR = new Array<(number | undefined)[]>(busStops.length);

		for (let i = 0; i != busStops.length; ++i) {
			toBusStopEvent[i] = new Array<Promise<(number | undefined)[]>>();
			toBusStopCompany[i] = new Array<Promise<(number | undefined)[]>>();
			toBusStopPredEvent[i] = new Array<Promise<(number | undefined)[]>>();
			fromBusStopEvent[i] = new Array<Promise<(number | undefined)[]>>();
			fromBusStopCompany[i] = new Array<Promise<(number | undefined)[]>>();
			fromBusStopPostEvent[i] = new Array<Promise<(number | undefined)[]>>();

			toBusStopEventRR[i] = new Array<number | undefined>();
			toBusStopCompanyRR[i] = new Array<number | undefined>();
			toBusStopPredEventRR[i] = new Array<number | undefined>();
			fromBusStopEventRR[i] = new Array<number | undefined>();
			fromBusStopCompanyRR[i] = new Array<number | undefined>();
			fromBusStopPostEventRR[i] = new Array<number | undefined>();
		}
		iterateAllInsertions(companies, insertions, (info, _) => {
			const idx = info.idxInEvents;
			const event = info.vehicle.events[idx];
			const prevEvent = info.vehicle.events[idx];
			const predEvent = info.vehicle.lastEventBefore;
			const postEvent = info.vehicle.firstEventAfter;
			const company = companies[info.companyIdx];
			if (info.idxInEvents === 0) {
				if (predEvent) {
					//toUserChosenPredEvent.push(oneToManyCarRouting(predEvent, [userChosen] , false))
					//for(let i=0;i!=busStops.length;++i){
					//	toBusStopPredEvent[i].push(oneToManyCarRouting(predEvent, [busStops[i]] , false))
					//}
				}
				fromUserChosenEvent.push(oneToManyCarRouting(userChosen, [event], false));
				fromUserChosenEventRR.push(routingResults.userChosen.from.event[idx]);
				for (let i = 0; i != busStops.length; ++i) {
					fromBusStopEvent[i].push(oneToManyCarRouting(busStops[i], [event], false));
					fromBusStopEventRR[i].push(routingResults.busStops.from[i].event[idx]);
				}
			} else if (info.idxInEvents === info.vehicle.events.length) {
				if (postEvent) {
					//fromUserChosenPostEvent.push(oneToManyCarRouting(userChosen , [postEvent] , false))
					//for(let i=0;i!=busStops.length;++i){
					//	fromBusStopPostEvent[i].push(oneToManyCarRouting(busStops[i], [postEvent], false))
					//}
					toUserChosenEvent.push(oneToManyCarRouting(prevEvent, [userChosen], false));
					toUserChosenEventRR.push(routingResults.userChosen.to.event[idx - 1]);
					for (let i = 0; i != busStops.length; ++i) {
						toBusStopEvent[i].push(oneToManyCarRouting(prevEvent, [busStops[i]], false));
						toBusStopEventRR[i].push(routingResults.busStops.to[i].event[idx - 1]);
					}
				}
			} else {
				toUserChosenEvent.push(oneToManyCarRouting(prevEvent, [userChosen], false));
				toUserChosenEventRR.push(routingResults.userChosen.to.event[idx]);

				toUserChosenCompany.push(oneToManyCarRouting(company, [userChosen], false));
				toUserChosenCompanyRR.push(routingResults.userChosen.to.company[info.companyIdx]);

				fromUserChosenEvent.push(oneToManyCarRouting(userChosen, [event], false));
				fromUserChosenEventRR.push(routingResults.userChosen.from.event[idx]);

				fromUserChosenCompany.push(oneToManyCarRouting(userChosen, [company], false));
				fromUserChosenCompanyRR.push(routingResults.userChosen.from.company[info.companyIdx]);

				for (let i = 0; i != busStops.length; ++i) {
					toBusStopEvent[i].push(oneToManyCarRouting(prevEvent, [busStops[i]], false));
					toBusStopEventRR[i].push(routingResults.busStops.to[i].event[idx]);

					toBusStopCompany[i].push(oneToManyCarRouting(company, [busStops[i]], false));
					toBusStopCompanyRR[i].push(routingResults.busStops.to[i].company[info.companyIdx]);

					fromBusStopEvent[i].push(oneToManyCarRouting(busStops[i], [event], false));
					fromBusStopEventRR[i].push(routingResults.busStops.from[i].event[idx]);

					fromBusStopCompany[i].push(oneToManyCarRouting(busStops[i], [company], false));
					fromBusStopCompanyRR[i].push(routingResults.busStops.from[i].company[info.companyIdx]);
				}
			}
		});
		let oneToManyResults: (number | undefined)[] = [];
		let rr: (number | undefined)[] = [];
		oneToManyResults = oneToManyResults.concat(
			toUserChosenEvent.length === 0 ? [] : (await Promise.all(toUserChosenEvent))[0]
		);
		oneToManyResults = oneToManyResults.concat(
			toUserChosenCompany.length === 0 ? [] : (await Promise.all(toUserChosenCompany))[0]
		);
		oneToManyResults = oneToManyResults.concat(
			toUserChosenPredEvent.length === 0 ? [] : (await Promise.all(toUserChosenPredEvent))[0]
		);
		oneToManyResults = oneToManyResults.concat(
			fromUserChosenEvent.length === 0 ? [] : (await Promise.all(fromUserChosenEvent))[0]
		);
		oneToManyResults = oneToManyResults.concat(
			fromUserChosenCompany.length === 0 ? [] : (await Promise.all(fromUserChosenCompany))[0]
		);
		oneToManyResults = oneToManyResults.concat(
			fromUserChosenPostEvent.length === 0 ? [] : (await Promise.all(fromUserChosenPostEvent))[0]
		);
		rr = rr.concat(toUserChosenEventRR);
		rr = rr.concat(toUserChosenCompanyRR);
		rr = rr.concat(toUserChosenPredEventRR);
		rr = rr.concat(fromUserChosenEventRR);
		rr = rr.concat(fromUserChosenCompanyRR);
		rr = rr.concat(fromUserChosenPostEventRR);
		for (let i = 0; i != busStops.length; ++i) {
			oneToManyResults = oneToManyResults.concat(
				toBusStopEvent[i].length === 0 ? [] : (await Promise.all(toBusStopEvent[i]))[0]
			);
			oneToManyResults = oneToManyResults.concat(
				toBusStopCompany[i].length === 0 ? [] : (await Promise.all(toBusStopCompany[i]))[0]
			);
			oneToManyResults = oneToManyResults.concat(
				toBusStopPredEvent[i].length === 0 ? [] : (await Promise.all(toBusStopPredEvent[i]))[0]
			);
			oneToManyResults = oneToManyResults.concat(
				fromBusStopEvent[i].length === 0 ? [] : (await Promise.all(fromBusStopEvent[i]))[0]
			);
			oneToManyResults = oneToManyResults.concat(
				fromBusStopCompany[i].length === 0 ? [] : (await Promise.all(fromBusStopCompany[i]))[0]
			);
			oneToManyResults = oneToManyResults.concat(
				fromBusStopPostEvent[i].length === 0 ? [] : (await Promise.all(fromBusStopPostEvent[i]))[0]
			);

			rr = rr.concat(toBusStopEventRR[i]);
			rr = rr.concat(toBusStopCompanyRR[i]);
			rr = rr.concat(toBusStopPredEventRR[i]);
			rr = rr.concat(fromBusStopEventRR[i]);
			rr = rr.concat(fromBusStopCompanyRR[i]);
			rr = rr.concat(fromBusStopPostEventRR[i]);
		}
		expect(rr.length).toBe(oneToManyResults.length);
		for (let i = 0; i != rr.length; ++i) {
			expect(rr[i]).toBe(oneToManyResults[i]);
		}
	});
});
