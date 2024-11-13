import { test, expect } from '@playwright/test';

test('should create a booking and validate database state', async ({ request }) => {
	const bookingData = {
		connection1: {
			start: {
				coordinates: { lat: 51.49738604451025, lng: 14.632990222164722 },
				address: 'Start Address'
			},
			target: {
				coordinates: { lat: 51.50955906457665, lng: 14.615381302548428 },
				address: 'Target Address'
			},
			startAddress: 'Start Address',
			targetAddress: 'Target Address'
		},
		connection2: null,
		capacities: {
			passengers: 1,
			wheelchairs: 0,
			bikes: 0,
			luggage: 0
		}
	};
	const response = await request.post('/api/booking', { data: bookingData });
	expect(response.status()).toBe(200);
});
