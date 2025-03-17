import { describe, it, expect, beforeEach } from 'vitest';
import { getViableBusStops } from './viableBusStops';
import {
	addCompany,
	addTaxi,
	clearDatabase,
	setAvailability,
	setTour,
	Zone
} from '$lib/testHelpers';
import type { UnixtimeMs } from '$lib/util/UnixtimeMs';
import { MINUTE } from '$lib/util/time';
import type { Capacities } from '$lib/server/booking/Capacities';

const inNiesky = { lat: 51.292260904642916, lng: 14.822263713757678 };
const inZittau = { lat: 50.89857713197384, lng: 14.8098212004343 };

const BASE_DATE_MS = new Date('2050-09-23T17:00Z').getTime();
const dateInXMinutes = (x: number): UnixtimeMs => {
	return BASE_DATE_MS + x * MINUTE;
};
const dateInXMinutesYMs = (x: number, y: number): UnixtimeMs => {
	return BASE_DATE_MS + x * MINUTE + y;
};

describe('blacklisting test', () => {
	beforeEach(async () => await clearDatabase());

	it('1 availability', async () => {
		const capacities: Capacities = {
			passengers: 3,
			bikes: 0,
			wheelchairs: 0,
			luggage: 0
		};
		const company = await addCompany(Zone.NIESKY);
		const taxi = await addTaxi(company, capacities);

		await setAvailability(taxi, dateInXMinutes(0), dateInXMinutes(90));

		const r = {
			userChosen: inNiesky,
			busStops: [inNiesky],
			startFixed: true,
			capacities: { passengers: 1, bikes: 0, wheelchairs: 0, luggage: 0 }
		};
		const res = await getViableBusStops(r.userChosen, r.busStops, r.capacities, dateInXMinutes(-100), dateInXMinutes(6000));
		expect(res).toHaveLength(1);
		expect(res[0].busStopIndex).toBe(0);
		expect(res[0].intervals.length).toBe(1);
		expect(res[0].intervals[0].startTime).toBe(dateInXMinutes(0));
		expect(res[0].intervals[0].endTime).toBe(dateInXMinutes(90));
	});

	it('2 busstops 1 availability', async () => {
		const capacities: Capacities = {
			passengers: 3,
			bikes: 3,
			wheelchairs: 3,
			luggage: 3
		};
		const company = await addCompany(Zone.NIESKY);
		const taxi = await addTaxi(company, capacities);
		await setAvailability(taxi, dateInXMinutes(0), dateInXMinutes(90));

		const r = {
			userChosen: inNiesky,
			busStops: [
				inNiesky,
				inNiesky
			],
			startFixed: true,
			capacities: { passengers: 1, bikes: 0, wheelchairs: 0, luggage: 0 }
		};
		const res = await getViableBusStops(r.userChosen, r.busStops, r.capacities, dateInXMinutes(-100), dateInXMinutes(6000));
		expect(res).toHaveLength(2);
		expect(res[0].busStopIndex).toBe(0);
		expect(res[0].intervals.length).toBe(1);
		expect(res[0].intervals[0].startTime).toBe(dateInXMinutes(0));
		expect(res[0].intervals[0].endTime).toBe(dateInXMinutes(90));
		expect(res[1].busStopIndex).toBe(1);
		expect(res[1].intervals.length).toBe(1);
		expect(res[1].intervals[0].startTime).toBe(dateInXMinutes(0));
		expect(res[1].intervals[0].endTime).toBe(dateInXMinutes(90));
	});

	it('luggage on seats', async () => {
		const capacities: Capacities = {
			passengers: 3,
			bikes: 3,
			wheelchairs: 3,
			luggage: 0
		};
		const company = await addCompany(Zone.NIESKY);
		const taxi = await addTaxi(company, capacities);
		await setAvailability(taxi, dateInXMinutes(0), dateInXMinutes(90));

		const r = {
			userChosen: inNiesky,
			busStops: [inNiesky],
			capacities: { passengers: 1, bikes: 0, wheelchairs: 0, luggage: 2 }
		};
		const res = await getViableBusStops(r.userChosen, r.busStops, r.capacities, dateInXMinutes(-100), dateInXMinutes(6000));
		expect(res[0].busStopIndex).toBe(0);
		expect(res[0].intervals.length).toBe(1);
		expect(res[0].intervals[0].startTime).toBe(dateInXMinutes(0));
		expect(res[0].intervals[0].endTime).toBe(dateInXMinutes(90));
	});

	it('wrong busStop Zone', async () => {
		const capacities: Capacities = {
			passengers: 3,
			bikes: 3,
			wheelchairs: 3,
			luggage: 3
		};
		const company = await addCompany(Zone.NIESKY);
		const taxi = await addTaxi(company, capacities);
		await setAvailability(taxi, dateInXMinutes(0), dateInXMinutes(90));

		const r = {
			userChosen: inNiesky,
			busStops: [inZittau],
			capacities: { passengers: 1, bikes: 0, wheelchairs: 0, luggage: 0 }
		};
		const res = await getViableBusStops(r.userChosen, r.busStops, r.capacities, dateInXMinutes(-100), dateInXMinutes(6000));
		expect(res).toHaveLength(0);
	});

	it('wrong user chosen Zone', async () => {
		const capacities: Capacities = {
			passengers: 3,
			bikes: 3,
			wheelchairs: 3,
			luggage: 3
		};
		const company = await addCompany(Zone.NIESKY);
		const taxi = await addTaxi(company, capacities);
		await setAvailability(taxi, dateInXMinutes(0), dateInXMinutes(90));

		const r = {
			userChosen: inZittau,
			busStops: [inNiesky],
			startFixed: true,
			capacities: { passengers: 1, bikes: 0, wheelchairs: 0, luggage: 0 }
		};
		const res = await getViableBusStops(r.userChosen, r.busStops, r.capacities, dateInXMinutes(-100), dateInXMinutes(6000));
		expect(res).toHaveLength(0);
	});

	it('too many passengers', async () => {
		const capacities: Capacities = {
			passengers: 3,
			bikes: 3,
			wheelchairs: 3,
			luggage: 3
		};
		const company = await addCompany(Zone.NIESKY);
		const taxi = await addTaxi(company, capacities);
		await setAvailability(taxi, dateInXMinutes(0), dateInXMinutes(90));

		const r = {
			userChosen: inNiesky,
			busStops: [inNiesky],
			startFixed: true,
			capacities: { passengers: 4, bikes: 0, wheelchairs: 0, luggage: 0 }
		};
		const res = await getViableBusStops(r.userChosen, r.busStops, r.capacities, dateInXMinutes(-100), dateInXMinutes(6000));
		expect(res).toHaveLength(1);
		expect(res[0].intervals).toHaveLength(0);
	});

	it('too many bikes', async () => {
		const capacities: Capacities = {
			passengers: 3,
			bikes: 3,
			wheelchairs: 3,
			luggage: 3
		};
		const company = await addCompany(Zone.NIESKY);
		const taxi = await addTaxi(company, capacities);
		await setAvailability(taxi, dateInXMinutes(0), dateInXMinutes(90));

		const r = {
			userChosen: inNiesky,
			busStops: [inNiesky],
			startFixed: true,
			capacities: { passengers: 0, bikes: 4, wheelchairs: 0, luggage: 0 }
		};
		const res = await getViableBusStops(r.userChosen, r.busStops, r.capacities, dateInXMinutes(-100), dateInXMinutes(6000));
		expect(res).toHaveLength(1);
		expect(res[0].intervals).toHaveLength(0);
	});

	it('too many wheelchairs', async () => {
		const capacities: Capacities = {
			passengers: 3,
			bikes: 3,
			wheelchairs: 3,
			luggage: 3
		};
		const company = await addCompany(Zone.NIESKY);
		const taxi = await addTaxi(company, capacities);
		await setAvailability(taxi, dateInXMinutes(0), dateInXMinutes(90));

		const r = {
			userChosen: inNiesky,
			busStops: [inNiesky],
			startFixed: true,
			capacities: { passengers: 0, bikes: 0, wheelchairs: 4, luggage: 0 }
		};
		const res = await getViableBusStops(r.userChosen, r.busStops, r.capacities, dateInXMinutes(-100), dateInXMinutes(6000));
		expect(res).toHaveLength(1);
		expect(res[0].intervals).toHaveLength(0);
	});

	it('too much luggage', async () => {
		const capacities: Capacities = {
			passengers: 3,
			bikes: 3,
			wheelchairs: 3,
			luggage: 3
		};
		const company = await addCompany(Zone.NIESKY);
		const taxi = await addTaxi(company, capacities);
		await setAvailability(taxi, dateInXMinutes(0), dateInXMinutes(90));

		const r = {
			userChosen: inNiesky,
			busStops: [inNiesky],
			startFixed: true,
			capacities: { passengers: 0, bikes: 0, wheelchairs: 0, luggage: 7 }
		};
		const res = await getViableBusStops(r.userChosen, r.busStops, r.capacities, dateInXMinutes(-100), dateInXMinutes(6000));
		expect(res).toHaveLength(1);
		expect(res[0].intervals).toHaveLength(0);
	});

	it('no vehicle', async () => {
		await addCompany(Zone.NIESKY);

		const r = {
			userChosen: inNiesky,
			busStops: [inNiesky],
			startFixed: true,
			capacities: { passengers: 0, bikes: 0, wheelchairs: 0, luggage: 0 }
		};
		const res = await getViableBusStops(r.userChosen, r.busStops, r.capacities, dateInXMinutes(-100), dateInXMinutes(6000));
		expect(res).toHaveLength(1);
		expect(res[0].intervals).toHaveLength(0);
	});

	it('no company', async () => {
		const r = {
			userChosen: inNiesky,
			busStops: [inNiesky],
			startFixed: true,
			capacities: { passengers: 0, bikes: 0, wheelchairs: 0, luggage: 0 }
		};
		const res = await getViableBusStops(r.userChosen, r.busStops, r.capacities, dateInXMinutes(-100), dateInXMinutes(6000));
		expect(res).toHaveLength(1);
		expect(res[0].intervals).toHaveLength(0);
	});

	it('no availability or tour', async () => {
		const capacities: Capacities = {
			passengers: 3,
			bikes: 3,
			wheelchairs: 3,
			luggage: 3
		};
		const company = await addCompany(Zone.NIESKY);
		await addTaxi(company, capacities);
		const r = {
			userChosen: inNiesky,
			busStops: [inNiesky],
			startFixed: true,
			capacities: { passengers: 0, bikes: 0, wheelchairs: 0, luggage: 0 }
		};
		const res = await getViableBusStops(r.userChosen, r.busStops, r.capacities, dateInXMinutes(-100), dateInXMinutes(6000));
		expect(res).toHaveLength(1);
		expect(res[0].intervals).toHaveLength(0);
	});

	it('1 busStop fails, other is succesful', async () => {
		const capacities: Capacities = {
			passengers: 3,
			bikes: 3,
			wheelchairs: 3,
			luggage: 3
		};
		const company = await addCompany(Zone.NIESKY);
		const taxi = await addTaxi(company, capacities);
		await setAvailability(taxi, dateInXMinutes(0), dateInXMinutes(90));

		const r = {
			userChosen: inNiesky,
			busStops: [inZittau, inNiesky],
			startFixed: true,
			capacities: { passengers: 0, bikes: 0, wheelchairs: 0, luggage: 0 }
		};
		const res = await getViableBusStops(r.userChosen, r.busStops, r.capacities, dateInXMinutes(-100), dateInXMinutes(6000));
		expect(res).toHaveLength(1);
		expect(res[0].busStopIndex).toBe(1);
		expect(res[0].intervals.length).toBe(1);
		expect(res[0].intervals[0].startTime).toBe(dateInXMinutes(0));
		expect(res[0].intervals[0].endTime).toBe(dateInXMinutes(90));
	});

	it('blacklisting, no busStops', async () => {
		const r = {
			userChosen: inNiesky,
			busStops: [],
			startFixed: true,
			capacities: { passengers: 0, bikes: 0, wheelchairs: 0, luggage: 0 }
		};
		const res = await getViableBusStops(r.userChosen, r.busStops, r.capacities, dateInXMinutes(-100), dateInXMinutes(6000));
		expect(res).toHaveLength(0);
	});

	it('availability barely overlaps', async () => {
		const capacities: Capacities = {
			passengers: 3,
			bikes: 0,
			wheelchairs: 0,
			luggage: 0
		};
		const company = await addCompany(Zone.NIESKY);
		const taxi = await addTaxi(company, capacities);

		await setAvailability(taxi, dateInXMinutes(0), dateInXMinutes(90));

		const r = {
			userChosen: inNiesky,
			busStops: [inNiesky],
			startFixed: false,
			capacities: { passengers: 1, bikes: 0, wheelchairs: 0, luggage: 0 }
		};
		const res = await getViableBusStops(r.userChosen, r.busStops, r.capacities, dateInXMinutes(-100), dateInXMinutes(6000));
		expect(res).toHaveLength(1);
		expect(res[0].intervals).toHaveLength(1);
	});
});
