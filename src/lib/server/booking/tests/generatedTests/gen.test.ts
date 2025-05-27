import { describe, expect, it } from 'vitest';
import { prepareTest, white } from '../util';
import { addCompany, addTaxi, getTours, setAvailability, Zone } from '$lib/testHelpers';
import type { ExpectedConnection } from '$lib/server/booking/bookRide';
import { bookingApi } from '$lib/server/booking/bookingApi';
import { tests } from './testJsons';
import { db } from '$lib/server/db';

describe('Concatenation tests', () => {
	it('generated tests', async () => {
		console.log({ testparams: JSON.stringify(tests, null, '\t') });
		for (const test of tests) {
			expect(test.process.starts.length).toBe(test.process.destinations.length);
			expect(test.process.starts.length).toBe(test.process.isDepartures.length);
			expect(test.process.starts.length).toBe(test.process.times.length);
			const mockUserId = await prepareTest();
			for (const company of test.process.companies) {
				const c = await addCompany(Zone.WEIßWASSER, company);
				for (let taxiIdx = 0; taxiIdx != 10; ++taxiIdx) {
					const taxi = await addTaxi(c, { passengers: 3, luggage: 0, wheelchairs: 0, bikes: 0 });
					await setAvailability(taxi, 0, 8640000000000000);
				}
			}
			for (let requestIdx = 0; requestIdx != test.process.starts.length; ++requestIdx) {
				const body = JSON.stringify({
					start: test.process.starts[requestIdx],
					target: test.process.destinations[requestIdx],
					startBusStops: [],
					targetBusStops: [],
					directTimes: [test.process.times[requestIdx]],
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
				const tours = await getTours();
				for (const condition of test.conditions.filter((c) => c.evalAfterStep === requestIdx)) {
					try {
						switch (condition.entity) {
							case 'requestCount':
								expect(tours.flatMap((t) => t.requests).length).toBe(condition.requestCount);
								break;
							case 'tourCount':
								expect(tours.length).toBe(condition.tourCount);
								break;
							case 'startPosition':
								break;
							case 'destinationPosition':
								break;
							case 'requestCompanyMatch': {
								const toursWithCorrectRequest = tours.filter((t) =>
									t.requests.some(
										(r) =>
											!r.events.some(
												(e) =>
													(e.lat !== condition.start?.lat || e.lng !== condition.start.lng) &&
													(e.lat !== condition.destination?.lat ||
														e.lng !== condition.destination.lng)
											)
									)
								);
								const companiesWithCorrectRequest = await db
									.selectFrom('tour')
									.innerJoin('vehicle', 'vehicle.id', 'tour.vehicle')
									.innerJoin('company', 'company.id', 'vehicle.company')
									.where(
										'tour.id',
										'in',
										toursWithCorrectRequest.map((r) => r.id)
									)
									.select(['company.lat', 'company.lng'])
									.execute();
								expect(
									companiesWithCorrectRequest.filter(
										(c) =>
											(c.lat !== condition.company?.lat || c.lng !== condition.company.lng) &&
											(c.lat !== condition.company?.lat || c.lng !== condition.company.lng)
									).length
								).not.toBe(0);
								break;
							}
							default:
								expect(false).toBeTruthy();
						}
					} catch (err) {
						console.error(`❌ Condition failed:`, { condition }, { uuid: test.uuid });
						throw err;
					}
				}
			}
		}
		console.log(
			`Successfully ran ${tests.length} tests with a total of ${tests.flatMap((t) => t.conditions).length} conditions.`
		);
	});
});
