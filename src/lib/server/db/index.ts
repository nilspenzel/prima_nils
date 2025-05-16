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
		tour: number;
		customer: number;
		ticketCode: string;
		ticketChecked: boolean;
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
}

export const pool = new pg.Pool({ connectionString: env.DATABASE_URL });
export const dialect = new PostgresDialect({ pool });

// Map int8 to number.
pg.types.setTypeParser(20, (val) => parseInt(val));

const rawDb = new Kysely<Database>({
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

export const db = withRetry(rawDb);
/*
export function withRetry<T extends Kysely<any>>(db: T, maxRetries = 15, baseDelayMs = 1000): T {
	const isQueryBuilder = (obj: any) => obj && typeof obj.execute === 'function';

	const wrapQueryBuilder = (builder: any): any => {
		const handler = {
			get(target: any, prop: string) {
				if (prop === 'execute') {
					return async () => {
						let attempt = 0;
						while (attempt < maxRetries) {
							try {
								return await target.execute();
							} catch (err: any) {
								attempt++;

								const code = err?.code;
								const isRetryable = code === '40P01' || code === '40001';

								if (!isRetryable || attempt >= maxRetries) throw err;

								const delay = baseDelayMs * Math.pow(1.15, attempt);
								console.warn(
									`[RETRY] Query failed with ${code}, retrying in ${delay.toFixed(0)}ms (attempt ${attempt})`
								);
								await new Promise((r) => setTimeout(r, delay));
							}
						}
					};
				}

				const value = target[prop];
				return typeof value === 'function'
					? (...args: any[]) => {
							const result = value.apply(target, args);
							return isQueryBuilder(result) ? wrapQueryBuilder(result) : result;
						}
					: value;
			}
		};
		return new Proxy(builder, handler);
	};

	const dbHandler = {
		get(target: any, prop: string) {
			const value = target[prop];

			if (prop === 'transaction') {
				return (...args: any[]) => {
					const trxBuilder = target.transaction(...args);

					return new Proxy(trxBuilder, {
						get(trxTarget, trxProp) {
							if (trxProp === 'execute') {
								return async (callback: any) => {
									let attempt = 0;
									while (attempt < maxRetries) {
										try {
											return await trxTarget.execute(async (trx: any) => {
												const wrappedTrx = new Proxy(trx, dbHandler);
												return callback(wrappedTrx);
											});
										} catch (err: any) {
											attempt++;
											const code = err?.code;
											const isRetryable = code === '40P01' || code === '40001';
											if (!isRetryable || attempt >= maxRetries) throw err;

											const delay = baseDelayMs * Math.pow(1.5, attempt);
											console.warn(
												`[RETRY] Transaction failed with ${code}, retrying in ${delay.toFixed(0)}ms (attempt ${attempt})`
											);
											await new Promise((r) => setTimeout(r, delay));
										}
									}
								};
							}
							return trxTarget[trxProp];
						}
					});
				};
			}

			return typeof value === 'function'
				? (...args: any[]) => {
						const result = value.apply(target, args);
						return isQueryBuilder(result) ? wrapQueryBuilder(result) : result;
					}
				: value;
		}
	};

	return new Proxy(db, dbHandler);
}*/export async function withRetryTransaction<T>(
  db: Kysely<any>,
  callback: (trx: Kysely.Transaction<any>) => Promise<T>,
  maxRetries = 15,
  baseDelayMs = 1000
): Promise<T> {
  let attempt = 0;

  while (true) {
    try {
      return await db.transaction(callback);
    } catch (err: any) {
      const code = err?.code;
      const isRetryable = code === '40P01' || code === '40001';

      attempt++;
      if (!isRetryable || attempt > maxRetries) {
        throw err;
      }

      const delay = baseDelayMs * Math.pow(1.5, attempt);
      console.warn(`[RETRY] Transaction failed with ${code}, retrying in ${delay.toFixed(0)}ms (attempt ${attempt})`);
      await new Promise((r) => setTimeout(r, delay));
    }
  }
}
