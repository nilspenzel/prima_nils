import { type Generated, CamelCasePlugin, PostgresDialect, Kysely } from 'kysely';
import { env } from '$env/dynamic/private';
import pg from 'pg';
import type { SignedItinerary } from '$lib/planAndSign';

export interface Database {
	user: {
		id: Generated<number>;
		email: string;
		name: string;
		passwordHash: string;
		isEmailVerified: boolean;
		emailVerificationCode: string | null;
		emailVerificationExpiresAt: number | null;
		passwordResetCode: string | null;
		passwordResetExpiresAt: number | null;
		isTaxiOwner: boolean;
		isAdmin: boolean;
		phone: string | null;
		companyId: number | null;
	};
	session: {
		id: string;
		expiresAt: number;
		userId: number;
	};
	zone: {
		id: Generated<number>;
		name: string;
		isCommunity: boolean;
		rates: number;
	};
	company: {
		id: Generated<number>;
		lat: number | null;
		lng: number | null;
		name: string | null;
		address: string | null;
		zone: number | null;
	};
	vehicle: {
		id: Generated<number>;
		licensePlate: string;
		company: number;
		passengers: number;
		wheelchairs: number;
		bikes: number;
		luggage: number;
	};
	tour: {
		id: Generated<number>;
		departure: number;
		arrival: number;
		vehicle: number;
		fare: number | null;
		directDuration: number | null;
		cancelled: boolean;
		message: string | null;
	};
	availability: {
		id: Generated<number>;
		startTime: number;
		endTime: number;
		vehicle: number;
	};
	event: {
		id: Generated<number>;
		isPickup: boolean;
		lat: number;
		lng: number;
		scheduledTimeStart: number;
		scheduledTimeEnd: number;
		communicatedTime: number;
		prevLegDuration: number;
		nextLegDuration: number;
		eventGroup: string;
		address: string;
		request: number;
		cancelled: boolean;
	};
	request: {
		id: Generated<number>;
		passengers: number;
		kidsZeroToTwo: number;
		kidsThreeToFour: number;
		kidsFiveToSix: number;
		wheelchairs: number;
		bikes: number;
		luggage: number;
		tour: number | null;
		rideShareTour: number | null;
		customer: number;
		ticketCode: string;
		ticketChecked: boolean;
		ticketPrice: number;
		cancelled: boolean;
	};
	journey: {
		id: Generated<number>;
		json: SignedItinerary;
		user: number;
		request1: number | null;
		request2: number | null;
		rating: number | null;
		comment: string | null;
	};
	fcmToken: {
		deviceId: string;
		company: number;
		fcmToken: string;
	};
	bookingApiParameters: {
		id: Generated<number>;
		startLat1: number | null;
		startLng1: number | null;
		targetLat1: number | null;
		targetLng1: number | null;
		startTime1: number | null;
		targetTime1: number | null;
		startAddress1: string | null;
		targetAddress1: string | null;
		startFixed1: boolean | null;
		startLat2: number | null;
		startLng2: number | null;
		targetLat2: number | null;
		targetLng2: number | null;
		startTime2: number | null;
		targetTime2: number | null;
		startAddress2: string | null;
		targetAddress2: string | null;
		startFixed2: boolean | null;
		kidsZeroToTwo: number;
		kidsThreeToFour: number;
		kidsFiveToSix: number;
		passengers: number;
		wheelchairs: number;
		bikes: number;
		luggage: number;
	};
	rideShareTour: {
		id: Generated<number>;
		passengers: number;
		luggage: number;
		fare: number | null;
		cancelled: boolean;
		message: string | null;
		provider: number;
	};
}

export const pool = new pg.Pool({ connectionString: env.DATABASE_URL });
export const dialect = new PostgresDialect({ pool });

// Map int8 to number.
pg.types.setTypeParser(20, (val) => parseInt(val));

export const db = new Kysely<Database>({
	dialect,
	plugins: [new CamelCasePlugin()],
	log(event) {
		if (event.level === 'error') {
			console.error('Query failed : ', {
				durationMs: event.queryDurationMillis,
				error: event.error,
				sql: event.query.sql,
				params: event.query.parameters
			});
		} else {
			console.log('Query executed : ', {
				durationMs: event.queryDurationMillis,
				sql: event.query.sql,
				params: event.query.parameters
			});
		}
	}
});
