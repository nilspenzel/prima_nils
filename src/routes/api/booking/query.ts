import { sql } from 'kysely';
import { db } from '$lib/database';

export const bookingApiQuery22 = async () => {
	const requestData = {
		passengers: 3,
		wheelchairs: 0,
		bikes: 1,
		luggage: 2
	};

	const event1Data = {
		is_pickup: true,
		lat: 1.0,
		lon: 1.0,
		scheduled_time: new Date('2023-10-15T10:00:00Z'),
		communicated_time: new Date('2023-10-15T09:45:00Z'),
		address: {
			street: 'Baker St',
			house_number: '221B',
			postal_code: 'NW1',
			city: 'London'
		},
		customer: 'egfrfme3qe0er5y',
		approach_duration: 15,
		return_duration: 10
	};

	const event2Data = {
		is_pickup: false,
		lat: 1.0,
		lon: 1.0,
		scheduled_time: new Date('2023-10-15T12:00:00Z'),
		communicated_time: new Date('2023-10-15T11:30:00Z'),
		address: {
			street: 'Oxford St',
			house_number: '47A',
			postal_code: 'W1D',
			city: 'London'
		},
		customer: 'egfrfme3qe0er5y',
		approach_duration: 20,
		return_duration: 15
	};

	const mergeTourList: number[] = [1, 2];
	const tourId = null;

	const departure = new Date('2023-10-15T10:00:00Z');
	const arrival = new Date('2023-10-15T12:00:00Z');
	const vehicleId = 1;

	await sql`
        CALL create_and_merge_tours(
            ROW(${requestData.passengers}, ${requestData.wheelchairs}, ${requestData.bikes}, ${requestData.luggage}),
            ROW(${event1Data.is_pickup}, ${event1Data.lat}, ${event1Data.lon}, ${event1Data.scheduled_time}, ${event1Data.communicated_time}, ${event1Data.customer}, ${event1Data.approach_duration}, ${event1Data.return_duration}),
            ROW(${event1Data.address.street}, ${event1Data.address.house_number}, ${event1Data.address.postal_code}, ${event1Data.address.city}),
            ROW(${event2Data.is_pickup}, ${event2Data.lat}, ${event2Data.lon}, ${event2Data.scheduled_time}, ${event2Data.communicated_time}, ${event2Data.customer}, ${event2Data.approach_duration}, ${event2Data.return_duration}),
            ROW(${event2Data.address.street}, ${event2Data.address.house_number}, ${event2Data.address.postal_code}, ${event2Data.address.city}),
            ${mergeTourList},
            ${departure},
            ${arrival},
            ${tourId},
            ${vehicleId}
        )`.execute(db);
};
