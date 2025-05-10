import { getToursWithRequests } from '../src/lib/server/db/getTours';
import type { ToursWithRequests, TourWithRequestsEvent } from '../src/lib/util/getToursTypes';

function validateRequestHas2Events(tours: ToursWithRequests): void {
	for (const tour of tours) {
		const eventGroups: { [key: number]: TourWithRequestsEvent[] } = {};

		for (const event of tour.requests.flatMap((r) => r.events)) {
			if (!eventGroups[event.requestId]) {
				eventGroups[event.requestId] = [];
			}

			eventGroups[event.requestId].push(event);
		}

		for (const [requestId, events] of Object.entries(eventGroups)) {
			if (events.length !== 2) {
				console.log(
					`Invalid tour: ${tour.tourId} - Request ID: ${requestId} does not have 2 events.`
				);
				for (const event of events) {
					console.log(`  Invalid Event ID: ${event.id}`);
				}
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
				break;
			}
		}
	}
}

function validateRequestsWithNoEvents(tours: ToursWithRequests): void {
	console.log('Validating tours with no events...');
	for (const request of tours.flatMap((t) => t.requests)) {
		if (request.events.length === 0) {
			console.log(`Request ${request.requestId} has no associated events.`);
		}
	}
}

function validateTourAndRequestCancelled(tours: ToursWithRequests): void {
	console.log('Validating tour and request cancellation consistency...');
	for (const tour of tours) {
		let allRequestsCancelled = true;
		for (const event of tour.requests.flatMap((r) => r.events)) {
			if (
				(event.cancelled && !event.requestCancelled) ||
				(!event.cancelled && event.requestCancelled)
			) {
				console.log(`event and request cancelled fields do not match for event_id ${event.id}`);
			}
			if (!event.requestCancelled) {
				allRequestsCancelled = false;
				if (tour.cancelled) {
					console.log(
						`tour was cancelled but associated request isn't for request_id ${event.requestId}`
					);
				}
			}
		}
		if (allRequestsCancelled && !tour.cancelled && tour.requests.length > 0) {
			console.log(
				`all requests are cancelled but associated tour isn't for tour_id ${tour.tourId}`
			);
		}
	}
}

function validateEventParameters(tours: ToursWithRequests): void {
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
			}

			if (wheelchairs < 0) {
				console.log(
					`Invalid wheelchairs value for requestId ${request.requestId}: ${wheelchairs}. It should be non-negative.`
				);
			}
			if (bikes < 0) {
				console.log(
					`Invalid bikes value for requestId ${request.requestId}: ${bikes}. It should be non-negative.`
				);
			}
			if (luggage < 0) {
				console.log(
					`Invalid luggage value for requestId ${request.requestId}: ${luggage}. It should be non-negative.`
				);
			}
		}
	}
}

function validateEventTimeNoOverlap(tours: ToursWithRequests): void {
	console.log('Validating that events do not overlap more than a single point...');
	function overlaps(event1: TourWithRequestsEvent, event2: TourWithRequestsEvent): boolean {
		const start1 = event1.scheduledTimeStart;
		const end1 = event1.scheduledTimeEnd;
		const start2 = event2.scheduledTimeStart;
		const end2 = event2.scheduledTimeEnd;
		return start1 < end2 && start2 < end1;
	}

	for (const tour of tours) {
		const events = tour.requests.flatMap((r) => r.events.filter((e) => !e.requestCancelled));
		for (let i = 0; i < events.length; i++) {
			for (let j = i + 1; j < events.length; j++) {
				const event1 = events[i];
				const event2 = events[j];

				if (overlaps(event1, event2)) {
					console.log(`Overlap detected between eventId ${event1.id} and eventId ${event2.id}`);
				}
			}
		}
	}
}

async function oneToMany(
	fromLat: number,
	fromLng: number,
	toLat: number,
	toLng: number
): Promise<number | null> {
	const baseUrl = 'http://localhost:6499';
	const params = new URLSearchParams({
		arriveBy: 'false',
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

async function validateDirectDurations(tours: ToursWithRequests): Promise<void> {
	console.log('Validating direct durations...');
	const uncancelledTours = tours.filter((t) => !t.cancelled);
	for (let tourIdx = 1; tourIdx < uncancelledTours.length; tourIdx++) {
		const earlierTour = uncancelledTours[tourIdx - 1];
		const laterTour = uncancelledTours[tourIdx];
		const earlierEvents = earlierTour.requests.flatMap((r) => r.events);
		const laterEvents = laterTour.requests.flatMap((r) => r.events);
		if (laterTour.vehicleId === earlierTour.vehicleId) {
			if (earlierTour.requests.length === 0) {
				console.log(`earlier tour has no requests`);
				continue;
			}
			const e1 = earlierEvents[earlierEvents.length - 1];
			if (laterEvents.length === 0) {
				continue;
			}
			const e2 = laterEvents[0];
			const earlierTourEnd = e1.scheduledTimeEnd;
			const laterTourStart = e2.scheduledTimeStart;
			if (
				0 < laterTourStart - earlierTourEnd &&
				laterTourStart - earlierTourEnd <= 3 * 3600 * 1000
			) {
				const expectedDuration = await oneToMany(e1.lat, e1.lng, e2.lat, e2.lng);
				if (expectedDuration === null) {
					console.log(
						`Found unexpected null in direct Duration for earlier tour: ${earlierTour.tourId} and later tour: ${laterTour.tourId}`
					);
				}
				if (laterTour.directDuration === null || laterTour.directDuration === undefined) {
					console.log(
						`direct duration is null unexpectedly for earlier tour: ${earlierTour.tourId} and later tour: ${laterTour.tourId}`
					);
				} else {
					if (
						expectedDuration !== null &&
						Math.abs(expectedDuration - laterTour.directDuration / 1000) > 5
					) {
						console.log(`Direct duration mismatch for earlier tour ${earlierTour.tourId} and later tour ${laterTour.tourId}: \
                  Expected ${expectedDuration} seconds, Found ${laterTour.directDuration / 1000} seconds`);
					}
				}
			}
		}
	}
}

async function validateLegDurations(tours: ToursWithRequests): Promise<void> {
	console.log('Validating leg durations...');
	const uncancelledTours = tours.filter((t) => !t.cancelled);
	for (const tour of uncancelledTours) {
		const events = [...tour.requests.flatMap((r) => r.events)].sort(
			(a, b) => a.scheduledTimeStart - b.scheduledTimeStart
		);
		for (let i = 0; i < events.length - 1; i++) {
			const earlierEvent = events[i];
			const laterEvent = events[i + 1];
			if (earlierEvent.nextLegDuration !== laterEvent.prevLegDuration) {
				console.log(`Leg duration mismatch between events ${earlierEvent.id} and ${laterEvent.id}`);
			}
			const expectedDuration = await oneToMany(
				earlierEvent.lat,
				earlierEvent.lng,
				laterEvent.lat,
				laterEvent.lng
			);
			if (
				expectedDuration !== null &&
				expectedDuration + 58 > earlierEvent.nextLegDuration / 1000
			) {
				console.log(`Direct duration mismatch for events ${earlierEvent.id} -> ${laterEvent.id}: \
              Expected ${expectedDuration + 60} seconds, Found ${earlierEvent.nextLegDuration / 1000} seconds`);
			}
			const earlierEventStart = earlierEvent.scheduledTimeStart;
			const laterEventEnd = laterEvent.scheduledTimeEnd;
			const timeDiff = (laterEventEnd - earlierEventStart) / 1000;
			if (expectedDuration !== null && timeDiff < expectedDuration + 58) {
				console.log(
					`Time difference expected duration ${expectedDuration + 58} seconds exceeds difference in event times ${timeDiff} seconds for event_id ${earlierEvent.id} and event_id ${laterEvent.id}`
				);
			}
		}
	}
}

async function validateCompanyDurations(tours: ToursWithRequests): Promise<void> {
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
		}

		const toCompany = await oneToMany(
			events[events.length - 1].lat,
			events[events.length - 1].lng,
			tour.companyLat!,
			tour.companyLng!
		);
		if (
			toCompany !== null &&
			Math.abs(toCompany + 60 - events[events.length - 1].nextLegDuration / 1000) > 5
		) {
			console.log(
				`Duration to company from last event does not match in tour with id: ${tour.tourId}, duration in db: ${events[events.length - 1].nextLegDuration / 1000} duration: ${toCompany + 60}`
			);
		}
	}
}

async function main(): Promise<void> {
	const tours = await getToursWithRequests(true);

	if (tours) {
		console.log('Validating tours...');
		validateRequestHas2Events(tours);
		validateRequestsWithNoEvents(tours);
		validateTourAndRequestCancelled(tours);
		validateEventParameters(tours);
		validateEventTimeNoOverlap(tours);
		await validateDirectDurations(tours);
		await validateLegDurations(tours);
		await validateCompanyDurations(tours);
	} else {
		console.log('No tours found or there was an error fetching the data.');
	}
}

// Run the main function
main().catch((error) => {
	console.error('Error in main function:', error);
});
