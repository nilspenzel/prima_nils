import { getToursWithRequests } from '../../src/lib/server/db/getTours';
import type { ToursWithRequests, TourWithRequestsEvent } from '../../src/lib/util/getToursTypes';
import { groupBy } from '../../src/lib/util/groupBy';
import { Interval } from '../../src/lib/util/interval';
import { HOUR } from '../../src/lib/util/time';
import { isSamePlace } from '../../src/lib/server/booking/isSamePlace';

function validateRequestHas2Events(tours: ToursWithRequests): boolean {
	let fail = false;
	for (const tour of tours) {
		for (const request of tour.requests) {
			const events = request.events;
			const requestId = request.requestId;
			if (events.length !== 2) {
				console.log(
					`Invalid tour: ${tour.tourId} - Request ID: ${requestId} does not have 2 events.`
				);
				for (const event of events) {
					console.log(`  Invalid Event ID: ${event.id}`);
				}
				fail = true;
				break;
			}

			let isPickupFound = false;
			let isDropoffFound = false;

			for (const event of events) {
				if (event.isPickup) {
					isPickupFound = true;
				} else {
					isDropoffFound = true;
				}
			}

			if (!(isPickupFound && isDropoffFound)) {
				console.log(
					`Invalid tour: ${tour.tourId} - Request ID: ${requestId} does not have both pickup and dropoff.`
				);
				for (const event of events) {
					console.log(`  Invalid Event ID: ${event.id}`);
				}
				fail = true;
				break;
			}
		}
	}
	return fail;
}

function validateRequestsWithNoEvents(tours: ToursWithRequests): boolean {
	let fail = false;
	console.log('Validating tours with no events...');
	for (const request of tours.flatMap((t) => t.requests)) {
		if (request.events.length === 0) {
			console.log(`Request ${request.requestId} has no associated events.`);
			fail = true;
		}
	}
	return fail;
}

function validateTourAndRequestCancelled(tours: ToursWithRequests): boolean {
	let fail = false;
	console.log('Validating tour and request cancellation consistency...');
	for (const tour of tours) {
		let allRequestsCancelled = true;
		for (const event of tour.requests.flatMap((r) => r.events)) {
			if (
				(event.cancelled && !event.requestCancelled) ||
				(!event.cancelled && event.requestCancelled)
			) {
				console.log(`event and request cancelled fields do not match for event_id ${event.id}`);
				fail = true;
			}
			if (!event.requestCancelled) {
				allRequestsCancelled = false;
				if (tour.cancelled) {
					console.log(
						`tour was cancelled but associated request isn't for request_id ${event.requestId}`
					);
					fail = true;
				}
			}
		}
		if (allRequestsCancelled && !tour.cancelled && tour.requests.length > 0) {
			console.log(
				`all requests are cancelled but associated tour isn't for tour_id ${tour.tourId}`
			);
			fail = true;
		}
	}
	return fail;
}

function validateEventParameters(tours: ToursWithRequests): boolean {
	let fail = false;
	console.log('Validating event parameters...');
	for (const tour of tours) {
		for (const request of tour.requests) {
			const passengers = request.passengers || 0;
			const wheelchairs = request.wheelchairs || 0;
			const bikes = request.bikes || 0;
			const luggage = request.luggage || 0;

			if (passengers <= 0) {
				console.log(
					`Invalid passengers value for requestId ${request.requestId}: ${passengers}. It should be positive.`
				);
				fail = true;
			}

			if (wheelchairs < 0) {
				console.log(
					`Invalid wheelchairs value for requestId ${request.requestId}: ${wheelchairs}. It should be non-negative.`
				);
				fail = true;
			}
			if (bikes < 0) {
				console.log(
					`Invalid bikes value for requestId ${request.requestId}: ${bikes}. It should be non-negative.`
				);
				fail = true;
			}
			if (luggage < 0) {
				console.log(
					`Invalid luggage value for requestId ${request.requestId}: ${luggage}. It should be non-negative.`
				);
				fail = true;
			}
		}
	}
	return fail;
}

function validateEventTimeNoOverlap(tours: ToursWithRequests): boolean {
	let fail = false;
	console.log('Validating that events do not overlap more than a single point...');
	function overlaps(event1: TourWithRequestsEvent, event2: TourWithRequestsEvent): boolean {
		const start1 = event1.scheduledTimeStart;
		const end1 = event1.scheduledTimeEnd;
		const start2 = event2.scheduledTimeStart;
		const end2 = event2.scheduledTimeEnd;
		return start1 < end2 && start2 < end1;
	}

	const uncancelledTours = tours.filter((t) => !t.cancelled);
	for (const [tourId1, tour] of uncancelledTours.entries()) {
		const events = tour.requests.flatMap((r) => r.events.filter((e) => !e.requestCancelled));
		for (let i = 0; i < events.length; i++) {
			for (let j = i + 1; j < events.length; j++) {
				const event1 = events[i];
				const event2 = events[j];

				if (overlaps(event1, event2)) {
					console.log(
						`Overlap detected between eventId ${event1.id} and eventId ${event2.id}, ${new Interval(event1.scheduledTimeStart, event1.scheduledTimeEnd).toString()} and ${new Interval(event2.scheduledTimeStart, event2.scheduledTimeEnd).toString()}`
					);
					fail = true;
				}
			}
		}
		for (let tourId2 = tourId1 + 1; tourId2 != uncancelledTours.length; ++tourId2) {
			const tour2 = uncancelledTours[tourId2];
			const i1 = new Interval(tour.startTime, tour.endTime);
			const i2 = new Interval(tour2.startTime, tour2.endTime);
			if (i1.overlaps(i2) && tour.vehicleId === tour2.vehicleId) {
				console.log(
					`tour overlap detected between tourId ${tour.tourId} and tourId ${tour2.tourId}`
				);
				fail = true;
			}
		}
	}
	return fail;
}

function validateEventsAreInsideTours(tours: ToursWithRequests): boolean {
	let fail = false;
	console.log('Validating that all events of a tour happen inside of departure-arrival...');
	for (const tour of tours) {
		const tourInterval = new Interval(tour.startTime, tour.endTime);
		for (const event of tour.requests.flatMap((r) => r.events)) {
			if (!tourInterval.overlaps(new Interval(event.scheduledTimeStart, event.scheduledTimeEnd))) {
				console.log(`event with id: ${event.id} is outside of its' tour.`);
				fail = true;
			}
		}
	}
	return fail;
}

async function oneToMany(
	fromLat: number,
	fromLng: number,
	toLat: number,
	toLng: number,
	arriveBy?: boolean
): Promise<number | null> {
	const baseUrl = 'http://localhost:6499';
	const params = new URLSearchParams({
		arriveBy: arriveBy ? 'true' : 'false',
		many: `${toLat};${toLng}`,
		max: '3600',
		maxMatchingDistance: '250',
		mode: 'CAR',
		one: `${fromLat};${fromLng}`
	});

	try {
		const response = await fetch(`${baseUrl}/api/v1/one-to-many?${params.toString()}`);

		if (!response.ok) {
			throw new Error(`HTTP error! status: ${response.status}`);
		}

		const data = await response.json();
		return data[0].duration;
	} catch (error) {
		console.error(`Error with one-to-many API: ${error}`);
		return null;
	}
}

async function validateDirectDurations(tours: ToursWithRequests): Promise<boolean> {
	let fail = false;
	console.log('Validating direct durations...');
	const uncancelledTours = groupBy(
		tours.filter((t) => !t.cancelled).sort((a, b) => a.startTime - b.startTime),
		(t) => t.vehicleId,
		(t) => t
	);
	for (const [_, companyTours] of uncancelledTours) {
		for (let tourIdx = 1; tourIdx != companyTours.length; tourIdx++) {
			const earlierTour = companyTours[tourIdx - 1];
			const laterTour = companyTours[tourIdx];
			const earlierEvents = earlierTour.requests
				.flatMap((r) => r.events)
				.sort((e1, e2) => e1.scheduledTimeStart - e2.scheduledTimeStart);
			const laterEvents = laterTour.requests
				.flatMap((r) => r.events)
				.sort((e1, e2) => e1.scheduledTimeStart - e2.scheduledTimeStart);
			if (laterTour.vehicleId === earlierTour.vehicleId) {
				if (earlierTour.requests.length === 0) {
					console.log(`earlier tour has no requests`);
					fail = true;
					continue;
				}
				const e1 = earlierEvents[earlierEvents.length - 1];
				if (laterEvents.length === 0) {
					continue;
				}
				const e2 = laterEvents[0];
				const earlierTourEnd = earlierTour.endTime;
				const laterTourStart = laterTour.startTime;
				if (0 < laterTourStart - earlierTourEnd && laterTourStart - earlierTourEnd <= 3 * HOUR) {
					const expectedDuration = await oneToMany(e1.lat, e1.lng, e2.lat, e2.lng);
					const expectedDuration2 = await oneToMany(e2.lat, e2.lng, e1.lat, e1.lng, true);
					if (expectedDuration === null || expectedDuration2 === null) {
						console.log(
							`Found unexpected null in direct Duration for earlier tour: ${earlierTour.tourId} and later tour: ${laterTour.tourId}`
						);
						fail = true;
					}
					if (!laterTour.directDuration && !expectedDuration && !expectedDuration2) {
						console.log(
							`direct duration is null unexpectedly for earlier tour: ${earlierTour.tourId} and later tour: ${laterTour.tourId}, expected ${expectedDuration} or ${expectedDuration2} seconds`
						);
						fail = true;
					} else {
						if (
							expectedDuration !== null &&
							expectedDuration2 !== null &&
							Math.abs(expectedDuration - laterTour.directDuration / 1000) > 2 &&
							Math.abs(expectedDuration2 - laterTour.directDuration / 1000) > 2
						) {
							console.log(`Direct duration mismatch for earlier tour ${earlierTour.tourId} and later tour ${laterTour.tourId}: \
                  Expected ${expectedDuration} or ${expectedDuration2} seconds, Found ${laterTour.directDuration / 1000} seconds, lat1: ${e1.lat} lng1:${e1.lng}, lat2: ${e2.lat} lng:${e2.lng} time difference: ${new Date(laterTourStart - earlierTourEnd).toISOString()}`);
							fail = true;
						}
					}
				}
			}
		}
	}
	return fail;
}

async function validateLegDurations(tours: ToursWithRequests): Promise<boolean> {
	let fail = false;
	console.log('Validating leg durations...');
	const uncancelledTours = tours.filter((t) => !t.cancelled);
	for (const tour of uncancelledTours) {
		const events = [...tour.requests.flatMap((r) => r.events)].sort((a, b) => {
			const startDiff = a.scheduledTimeStart - b.scheduledTimeStart;
			if (startDiff !== 0) {
				return startDiff;
			}
			return a.scheduledTimeEnd - b.scheduledTimeEnd;
		});
		for (let i = 0; i < events.length - 1; i++) {
			const earlierEvent = events[i];
			const laterEvent = events[i + 1];
			if (earlierEvent.nextLegDuration !== laterEvent.prevLegDuration) {
				console.log(`Leg duration mismatch between events ${earlierEvent.id} and ${laterEvent.id}`);
				fail = true;
			}
			const expectedDuration = await oneToMany(
				earlierEvent.lat,
				earlierEvent.lng,
				laterEvent.lat,
				laterEvent.lng
			);
			const expectedDuration2 = await oneToMany(
				laterEvent.lat,
				laterEvent.lng,
				earlierEvent.lat,
				earlierEvent.lng,
				true
			);
			if (
				expectedDuration !== null &&
				(isSamePlace(earlierEvent, laterEvent) ? 0 : expectedDuration + 60) >
					earlierEvent.nextLegDuration / 1000 &&
				expectedDuration2 !== null &&
				(isSamePlace(earlierEvent, laterEvent) ? 0 : expectedDuration2 + 60) >
					earlierEvent.nextLegDuration / 1000
			) {
				console.log(
					`Direct duration mismatch for events ${earlierEvent.id} -> ${laterEvent.id}: \
              Expected ${expectedDuration + 60} or ${expectedDuration2 + 60} seconds, Found ${earlierEvent.nextLegDuration / 1000} seconds`,
					{
						startTimes: events.map(
							(e) => `id: ${e.id} ${new Date(e.scheduledTimeStart).toISOString()}`
						)
					},
					{
						endTimes: events.map((e) => `id: ${e.id} ${new Date(e.scheduledTimeEnd).toISOString()}`)
					},
					{
						idsStart: events
							.sort((e1, e2) => {
								const startDiff = e1.scheduledTimeStart - e2.scheduledTimeStart;
								if (startDiff !== 0) {
									return startDiff;
								}
								return e1.scheduledTimeEnd - e2.scheduledTimeEnd;
							})
							.map((e) => e.id)
					},
					{
						idsEnd: events
							.sort((e1, e2) => {
								const startDiff = e1.scheduledTimeEnd - e2.scheduledTimeEnd;
								if (startDiff !== 0) {
									return startDiff;
								}
								return e1.scheduledTimeStart - e2.scheduledTimeStart;
							})
							.map((e) => e.id)
					}
				);
				fail = true;
			}
			const earlierEventStart = earlierEvent.scheduledTimeStart;
			const laterEventEnd = laterEvent.scheduledTimeEnd;
			const timeDiff = (laterEventEnd - earlierEventStart) / 1000;
			if (
				expectedDuration !== null &&
				timeDiff < expectedDuration + 60 &&
				expectedDuration2 !== null &&
				timeDiff < expectedDuration2 + 60
			) {
				console.log(
					`Time difference expected duration ${expectedDuration + 60} seconds exceeds difference in event times ${timeDiff} seconds for event_id ${earlierEvent.id} and event_id ${laterEvent.id}`
				);
				fail = true;
			}
		}
	}
	return fail;
}

async function validateCompanyDurations(tours: ToursWithRequests): Promise<boolean> {
	let fail = false;
	console.log('Validating leg durations from/to company...');
	const uncancelledTours = tours.filter((t) => !t.cancelled);
	for (const tour of uncancelledTours) {
		if (tour.requests.length === 0) continue;

		const events = [...tour.requests.flatMap((r) => r.events)].sort(
			(a, b) => a.scheduledTimeStart - b.scheduledTimeStart
		);
		const fromCompanyFwd = await oneToMany(
			tour.companyLat!,
			tour.companyLng!,
			events[0].lat,
			events[0].lng
		);
		const fromCompanyBwd = await oneToMany(
			events[0].lat,
			events[0].lng,
			tour.companyLat!,
			tour.companyLng!
		);

		if (
			fromCompanyFwd !== null &&
			fromCompanyBwd !== null &&
			Math.abs(fromCompanyFwd - events[0].prevLegDuration / 1000) > 5 &&
			Math.abs(fromCompanyBwd - events[0].prevLegDuration / 1000) > 5
		) {
			console.log(
				`Duration from company to first event does not match in tour with id: ${tour.tourId}, duration in db: ${events[0].prevLegDuration / 1000} duration: ${fromCompanyFwd}`
			);
			fail = true;
		}

		const toCompany = await oneToMany(
			events[events.length - 1].lat,
			events[events.length - 1].lng,
			tour.companyLat!,
			tour.companyLng!
		);
		if (
			toCompany !== null &&
			Math.abs(toCompany + 60 - events[events.length - 1].nextLegDuration / 1000) > 1
		) {
			console.log(
				`Duration to company from last event does not match in tour with id: ${tour.tourId}, duration in db: ${events[events.length - 1].nextLegDuration / 1000} duration: ${toCompany + 60}`
			);
			fail = true;
		}
	}
	return fail;
}

export async function healthCheck() {
	const tours = await getToursWithRequests(true);
	let fail = false;
	if (tours) {
		console.log('Validating tours...');
		fail = validateRequestHas2Events(tours) ? true : fail;
		fail = validateRequestsWithNoEvents(tours) ? true : fail;
		fail = validateTourAndRequestCancelled(tours) ? true : fail;
		fail = validateEventParameters(tours) ? true : fail;
		fail = validateEventTimeNoOverlap(tours) ? true : fail;
		fail = validateEventsAreInsideTours(tours) ? true : fail;
		fail = (await validateDirectDurations(tours)) ? true : fail;
		fail = (await validateLegDurations(tours)) ? true : fail;
		fail = (await validateCompanyDurations(tours)) ? true : fail;
	} else {
		console.log('No tours found or there was an error fetching the data.');
	}
	return fail;
}
