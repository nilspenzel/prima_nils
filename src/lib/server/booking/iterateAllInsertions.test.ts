import { describe, it, expect } from 'vitest';
import { iterateAllInsertions } from './iterateAllInsertions';
import type { Company, Event } from './getBookingAvailability';
import { Interval } from '$lib/util/interval';
import type { Range } from '$lib/util/booking/getPossibleInsertions';
import { gatherRoutingCoordinates, routing } from './routing';
import { oneToManyCarRouting } from '../util/oneToManyCarRouting';
import type { InsertionInfo } from './insertionTypes';

function createEvent(lng:number,lat:number) {
    return {
            departure: 1,
            arrival: 1,
            directDuration: null,
            id: 1,
            lat,
            lng,
            isPickup: true,
            scheduledTimeStart: 1,
            scheduledTimeEnd: 1,
            communicatedTime: 1,
            prevLegDuration: 1,
            nextLegDuration: 1,
            eventGroup: '1',
            passengers: 1,
            wheelchairs: 0,
            bikes: 0,
            luggage: 0,
            tourId: 1,
            time: new Interval(1,1)
    };
}

describe('Concatenation tests', () => {
    it('create tour concetanation, simple append', async () => {
        expect(true).toBeTruthy();
        const userChosen = {
          lng:14.53630667622113,
          lat:51.545623857809545};
        const busStops = [{
          lng:14.58071087168372,
          lat:51.54578074491525,times:[]}];
        const events: Event[] = [createEvent(
          14.53178239383675,
          51.5465151158171), createEvent(
          14.64059313927038,
          51.50381651732772),
			createEvent(14.715642169397938, 51.550348303864695)];
        const vehicles = [{
            id: 1,
            availabilities: [new Interval(1,1)],
            tours: [{
                arrival: 1,
                departure: 2,
            }],
            events,
            lastEventBefore: undefined,
            firstEventAfter: undefined,
            passengers: 1,
            wheelchairs: 0,
            bikes: 0,
            luggage: 0
        }];
        const companies: Company[] = [{
            id: 1,
          lng:14.529244267543419,
          lat:51.537152978707326,
                      zoneId: 2,
            vehicles
        }];
        const insertions = new Map<number, Range[]>();
        insertions.set(1, [{
	        earliestPickup: 0,
	        latestDropoff: 2
        }]);
        const routingResults = await routing(
            companies,
            gatherRoutingCoordinates(companies, insertions),
            userChosen,
            busStops,
            false
        );
        const rrP: (Promise<(number | undefined)[]>)[] = [];
        const rr2: (number|undefined)[] = [];
        const infos: ({idx:number;userChosen:boolean, })[] = [];
        iterateAllInsertions(companies, insertions, async (info, _) => {
            if(info.idxInEvents !== 0) {
                infos.push({idx:info.idxInEvents,userChosen:true});
                rrP.push(oneToManyCarRouting(info.vehicle.events[info.idxInEvents-1], [userChosen], false));
                rr2.push(routingResults.userChosen.event[info.prevEventIdxInRoutingResults]);
            }
            if(info.idxInEvents !== events.length && info.idxInEvents<=insertions.get(1)![0].latestDropoff) {
                infos.push({idx:info.idxInEvents,userChosen:false});
                rrP.push(oneToManyCarRouting(busStops[0],[info.vehicle.events[info.idxInEvents]], false));
                rr2.push(routingResults.busStops[0].event[info.nextEventIdxInRoutingResults]);
            }
        });
        const rr = (await Promise.all(rrP)).map((r) => r[0]);
        console.log(await oneToManyCarRouting(busStops[0],[events[2]],false))
        console.log("rout",routingResults.busStops[0].event)
        console.log("rout",routingResults.userChosen.event)
        console.log({rr2})
        console.log({rr})
        for(let i=0;i!=rrP.length;++i){
            console.log(infos[i])
            expect(rr[i]).toBe(rr2[i]);
        }
    });
});
