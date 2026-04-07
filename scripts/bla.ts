import fs from 'fs/promises';
import path from 'path';
import { createRequire } from 'node:module';
import {
	FileMigrationProvider,
	Kysely,
	Migrator,
	PostgresDialect,
	sql,
} from 'kysely';

const require = createRequire(import.meta.url);
const { Pool } = require('pg') as typeof import('pg');

// =====================
// Hard-coded variables
// =====================
const ZONE_ID = 1;

const EXPANDED_DISTANCE_METERS = 10_000; // 10 km
const TWICE_EXPANDED_DISTANCE_METERS = 100_000; // 100 km

const CONE_COUNT = 8;
const CONE_ARC_SEGMENTS = 64;

const PAIRS_PER_CONE = 10;
const MAX_ATTEMPTS_PER_CONE = 1_000;

const MIGRATIONS_PATH = path.join(process.cwd(), 'migrations');
const RESULTS_FILE_PATH = path.join(process.cwd(), 'results.txt');

// validation endpoint
const BASE_URL = 'http://localhost:5173/api/planAndSign';

// throttling / stability
const REQUEST_TIMEOUT_MS = 15_000;
const DELAY_BETWEEN_VALIDATION_REQUESTS_MS = 50;
const LOG_EVERY_N_ATTEMPTS = 50;

// blacklist
const FAILURE_SQUARE_HALF_SIZE_METERS = 500;

// query template values
const QUERY_ARRIVE_BY = false;
const QUERY_PRE_TRANSIT_MODES = ['WALK', 'ODM', 'RIDE_SHARING'];
const QUERY_POST_TRANSIT_MODES = ['WALK', 'ODM', 'RIDE_SHARING'];
const QUERY_DIRECT_MODES = ['WALK', 'ODM', 'RIDE_SHARING'];
const QUERY_PEDESTRIAN_PROFILE = 'FOOT';
const QUERY_LUGGAGE = 0;
const QUERY_FASTEST_DIRECT_FACTOR = 1.6;
const QUERY_MAX_MATCHING_DISTANCE = 250;
const QUERY_MAX_TRAVEL_TIME = 1440;
const QUERY_PASSENGERS = 1;

type DB = {
	zone: {
		id: number;
		area: unknown;
		name: string;
		expanded: unknown | null;
		twiceExpanded: unknown | null;
	};
};

type Point3857Bounds = {
	minX: number;
	minY: number;
	maxX: number;
	maxY: number;
};

type CandidatePoint = {
	lat: number;
	lng: number;
	x: number;
	y: number;
};

type CoordinatePair = {
	first: CandidatePoint; // target / toPlace: inside (twice_expanded ∩ current_cone) \ zone.area
	second: CandidatePoint; // start / fromPlace: inside zone.area
	attemptNumber: number;
	queryTimeIso: string;
};

type FailureSquare = {
	centerX: number;
	centerY: number;
};

type PlanQuery = {
	time: string;
	arriveBy: boolean;
	fromPlace: string;
	toPlace: string;
	preTransitModes: string[];
	postTransitModes: string[];
	directModes: string[];
	pedestrianProfile: string;
	luggage: number;
	fastestDirectFactor: number;
	maxMatchingDistance: number;
	maxTravelTime: number;
	passengers: number;
};

type PlanAndSignResponse = {
	itineraries?: unknown[];
};

type ZoneMetadata = {
	id: number;
	name: string;
	centerLat: number;
	centerLng: number;
	coneRadiusMeters: number;
	areaBounds3857: Point3857Bounds;
};

type ConeStats = {
	totalAttempts: number;
	rejectedByTargetFailureSquare: number;
	rejectedByStartFailureSquare: number;
	endpointFailures: number;
	accepted: number;
	preSamplingFirstGeometryMisses: number;
	preSamplingSecondGeometryMisses: number;
};

type ConeResult = {
	coneIndex: number;
	startAngleDeg: number;
	endAngleDeg: number;
	pairs: CoordinatePair[];
	attemptsUsed: number;
	stoppedBecauseAttemptLimit: boolean;
	stats: ConeStats;
};

function createDb() {
	const pool = new Pool({
		connectionString: process.env.DATABASE_URL,
	});

	return new Kysely<DB>({
		dialect: new PostgresDialect({
			pool,
		}),
	});
}

function randomBetween(min: number, max: number): number {
	return min + Math.random() * (max - min);
}

function sleep(ms: number): Promise<void> {
	return new Promise((resolve) => setTimeout(resolve, ms));
}

function formatPlace(lat: number, lng: number): string {
	return `${lat},${lng},0`;
}

function randomQueryTimeIso(): string {
	const now = new Date();

	const minDaysAhead = 3;
	const maxDaysAhead = 28;
	const dayOffset =
		minDaysAhead + Math.floor(Math.random() * (maxDaysAhead - minDaysAhead + 1));

	const targetDate = new Date(
		Date.UTC(
			now.getUTCFullYear(),
			now.getUTCMonth(),
			now.getUTCDate() + dayOffset,
			0,
			0,
			0,
			0
		)
	);

	const minSeconds = 8 * 60 * 60; // 08:00:00 UTC
	const maxSeconds = 20 * 60 * 60; // 20:00:00 UTC
	const secondOfDay =
		minSeconds + Math.floor(Math.random() * (maxSeconds - minSeconds + 1));

	const hours = Math.floor(secondOfDay / 3600);
	const minutes = Math.floor((secondOfDay % 3600) / 60);
	const seconds = secondOfDay % 60;

	targetDate.setUTCHours(hours, minutes, seconds, 0);

	return targetDate.toISOString();
}

function buildPlanQueryFromPoints(
	from: CandidatePoint,
	to: CandidatePoint,
	timeIso: string
): PlanQuery {
	return {
		time: timeIso,
		arriveBy: QUERY_ARRIVE_BY,
		fromPlace: formatPlace(from.lat, from.lng),
		toPlace: formatPlace(to.lat, to.lng),
		preTransitModes: [...QUERY_PRE_TRANSIT_MODES],
		postTransitModes: [...QUERY_POST_TRANSIT_MODES],
		directModes: [...QUERY_DIRECT_MODES],
		pedestrianProfile: QUERY_PEDESTRIAN_PROFILE,
		luggage: QUERY_LUGGAGE,
		fastestDirectFactor: QUERY_FASTEST_DIRECT_FACTOR,
		maxMatchingDistance: QUERY_MAX_MATCHING_DISTANCE,
		maxTravelTime: QUERY_MAX_TRAVEL_TIME,
		passengers: QUERY_PASSENGERS,
	};
}

function buildPlanQuery(pair: CoordinatePair): PlanQuery {
	return buildPlanQueryFromPoints(pair.second, pair.first, pair.queryTimeIso);
}

function buildPlanQueries(results: ConeResult[]): PlanQuery[] {
	const queries: PlanQuery[] = [];

	for (const coneResult of results) {
		for (const pair of coneResult.pairs) {
			queries.push(buildPlanQuery(pair));
		}
	}

	return queries;
}

function shellEscapeSingleQuoted(value: string): string {
	return value.replace(/'/g, `'\\''`);
}

function buildCurlCommands(queries: PlanQuery[]): string[] {
	return queries.map((query) => {
		const jsonBody = JSON.stringify(query);
		return `curl -X POST '${BASE_URL}' -H 'Content-Type: application/json' --data-raw '${shellEscapeSingleQuoted(jsonBody)}'`;
	});
}

async function writeCommandsToResultsFile(commands: string[]): Promise<void> {
	await fs.writeFile(RESULTS_FILE_PATH, commands.join('\n\n'), 'utf8');
}

async function validatePlanQuery(query: PlanQuery): Promise<boolean> {
	const controller = new AbortController();
	const timeout = setTimeout(() => controller.abort(), REQUEST_TIMEOUT_MS);

	try {
		const response = await fetch(BASE_URL, {
			method: 'POST',
			headers: {
				'Content-Type': 'application/json',
			},
			body: JSON.stringify(query),
			signal: controller.signal,
		});

		if (!response.ok) {
			return false;
		}

		const json = (await response.json()) as PlanAndSignResponse;
		return Array.isArray(json.itineraries) && json.itineraries.length > 0;
	} catch {
		return false;
	} finally {
		clearTimeout(timeout);
	}
}

async function validatePairWithPlanAndSign(pair: CoordinatePair): Promise<boolean> {
	return validatePlanQuery(buildPlanQuery(pair));
}

function isInsideFailureSquare(
	point: { x: number; y: number },
	squares: FailureSquare[]
): boolean {
	return squares.some(
		(square) =>
			Math.abs(point.x - square.centerX) <= FAILURE_SQUARE_HALF_SIZE_METERS &&
			Math.abs(point.y - square.centerY) <= FAILURE_SQUARE_HALF_SIZE_METERS
	);
}

function addFailureSquare(
	point: { x: number; y: number },
	squares: FailureSquare[]
) {
	squares.push({
		centerX: point.x,
		centerY: point.y,
	});
}

async function columnExists(
	db: Kysely<DB>,
	tableName: string,
	columnName: string
): Promise<boolean> {
	const result = await sql<{ exists: boolean }>`
		SELECT EXISTS (
			SELECT 1
			FROM information_schema.columns
			WHERE table_schema = 'public'
				AND table_name = ${tableName}
				AND column_name = ${columnName}
		) AS exists
	`.execute(db);

	return Boolean(result.rows[0]?.exists);
}

async function ensureTwiceExpandedColumn(db: Kysely<DB>) {
	const hasColumn = await columnExists(db, 'zone', 'twice_expanded');

	if (hasColumn) {
		console.log('twice_expanded already exists, skipping migration.');
		return;
	}

	console.log('twice_expanded missing, running migrations...');

	const migrator = new Migrator({
		db,
		provider: new FileMigrationProvider({
			fs,
			path,
			migrationFolder: MIGRATIONS_PATH,
		}),
	});

	const { error, results } = await migrator.migrateToLatest();

	if (results) {
		for (const result of results) {
			console.log(`${result.status}: ${result.migrationName}`);
		}
	}

	if (error) {
		throw error;
	}

	const existsAfter = await columnExists(db, 'zone', 'twice_expanded');
	if (!existsAfter) {
		throw new Error(
			'Migration ran, but twice_expanded still does not exist.'
		);
	}
}

async function updateZoneExpansions(db: Kysely<DB>) {
	const zone = await db
		.selectFrom('zone')
		.select(['id', 'name'])
		.where('id', '=', ZONE_ID)
		.executeTakeFirst();

	if (!zone) {
		throw new Error(`Zone with id ${ZONE_ID} does not exist.`);
	}

	await db.transaction().execute(async (trx) => {
		await sql`
			UPDATE zone
			SET expanded = ST_Multi(
				ST_Buffer(area, ${EXPANDED_DISTANCE_METERS})::geometry
			)::geography
			WHERE id = ${ZONE_ID}
		`.execute(trx);

		await sql`
			UPDATE zone
			SET twice_expanded = ST_Multi(
				ST_Buffer(area, ${TWICE_EXPANDED_DISTANCE_METERS})::geometry
			)::geography
			WHERE id = ${ZONE_ID}
		`.execute(trx);
	});

	console.log(
		`Updated zone ${zone.id} (${zone.name}) → expanded=${EXPANDED_DISTANCE_METERS}m, twice_expanded=${TWICE_EXPANDED_DISTANCE_METERS}m`
	);
}

async function getZoneMetadata(db: Kysely<DB>): Promise<ZoneMetadata> {
	const result = await sql<{
		id: number;
		name: string;
		center_lat: number;
		center_lng: number;
		cone_radius_meters: number;
		area_min_x: number;
		area_min_y: number;
		area_max_x: number;
		area_max_y: number;
	}>`
		WITH zone_data AS (
			SELECT
				id,
				name,
				ST_Centroid(area::geometry) AS center_geom_4326,
				ST_Transform(ST_Centroid(area::geometry), 3857) AS center_geom_3857,
				ST_Transform(area::geometry, 3857) AS area_geom_3857,
				ST_Transform(twice_expanded::geometry, 3857) AS twice_expanded_geom_3857
			FROM zone
			WHERE id = ${ZONE_ID}
		)
		SELECT
			id,
			name,
			ST_Y(center_geom_4326) AS center_lat,
			ST_X(center_geom_4326) AS center_lng,
			(
				ST_MaxDistance(center_geom_3857, twice_expanded_geom_3857) + 1000
			) AS cone_radius_meters,
			ST_XMin(area_geom_3857) AS area_min_x,
			ST_YMin(area_geom_3857) AS area_min_y,
			ST_XMax(area_geom_3857) AS area_max_x,
			ST_YMax(area_geom_3857) AS area_max_y
		FROM zone_data
	`.execute(db);

	const row = result.rows[0];

	if (!row) {
		throw new Error(`Zone with id ${ZONE_ID} does not exist.`);
	}

	if (row.cone_radius_meters == null) {
		throw new Error(
			`Zone ${ZONE_ID} has no twice_expanded geometry. Could not compute cone radius.`
		);
	}

	return {
		id: row.id,
		name: row.name,
		centerLat: row.center_lat,
		centerLng: row.center_lng,
		coneRadiusMeters: row.cone_radius_meters,
		areaBounds3857: {
			minX: row.area_min_x,
			minY: row.area_min_y,
			maxX: row.area_max_x,
			maxY: row.area_max_y,
		},
	};
}

async function getConeIntersectionBounds(
	db: Kysely<DB>,
	startAngleDeg: number,
	endAngleDeg: number,
	radiusMeters: number
): Promise<Point3857Bounds | null> {
	const result = await sql<{
		has_area: boolean;
		min_x: number | null;
		min_y: number | null;
		max_x: number | null;
		max_y: number | null;
	}>`
		WITH zone_data AS (
			SELECT
				ST_Transform(ST_Centroid(area::geometry), 3857) AS center_3857,
				ST_Transform(twice_expanded::geometry, 3857) AS twice_expanded_3857,
				ST_Transform(area::geometry, 3857) AS area_3857
			FROM zone
			WHERE id = ${ZONE_ID}
		),
		params AS (
			SELECT
				center_3857,
				${radiusMeters}::double precision AS radius_m,
				radians(${startAngleDeg}) AS start_rad,
				radians(${endAngleDeg}) AS end_rad,
				${CONE_ARC_SEGMENTS}::integer AS arc_segments
			FROM zone_data
		),
		arc_points AS (
			SELECT
				step,
				ST_SetSRID(
					ST_MakePoint(
						ST_X(center_3857) + radius_m * COS(
							start_rad + ((end_rad - start_rad) * step / arc_segments::double precision)
						),
						ST_Y(center_3857) + radius_m * SIN(
							start_rad + ((end_rad - start_rad) * step / arc_segments::double precision)
						)
					),
					3857
				) AS geom
			FROM params
			CROSS JOIN generate_series(0, ${CONE_ARC_SEGMENTS}) AS step
		),
		ring_points AS (
			SELECT 0 AS ord, center_3857 AS geom
			FROM params

			UNION ALL

			SELECT step + 1 AS ord, geom
			FROM arc_points

			UNION ALL

			SELECT ${CONE_ARC_SEGMENTS + 2} AS ord, center_3857 AS geom
			FROM params
		),
		cone AS (
			SELECT ST_MakePolygon(ST_MakeLine(geom ORDER BY ord)) AS cone_3857
			FROM ring_points
		),
		valid_geom AS (
			SELECT ST_CollectionExtract(
				ST_Difference(
					ST_Intersection(z.twice_expanded_3857, c.cone_3857),
					z.area_3857
				),
				3
			) AS geom
			FROM zone_data z
			CROSS JOIN cone c
		)
		SELECT
			NOT ST_IsEmpty(geom) AS has_area,
			ST_XMin(geom) AS min_x,
			ST_YMin(geom) AS min_y,
			ST_XMax(geom) AS max_x,
			ST_YMax(geom) AS max_y
		FROM valid_geom
	`.execute(db);

	const row = result.rows[0];

	if (!row || !row.has_area) {
		return null;
	}

	if (
		row.min_x == null ||
		row.min_y == null ||
		row.max_x == null ||
		row.max_y == null
	) {
		return null;
	}

	return {
		minX: row.min_x,
		minY: row.min_y,
		maxX: row.max_x,
		maxY: row.max_y,
	};
}

async function tryRandomFirstPointInConeAndTwiceExpandedOutsideZone(
	db: Kysely<DB>,
	startAngleDeg: number,
	endAngleDeg: number,
	radiusMeters: number,
	randomX3857: number,
	randomY3857: number
): Promise<CandidatePoint | null> {
	const result = await sql<{
		inside: boolean;
		lat: number;
		lng: number;
	}>`
		WITH zone_data AS (
			SELECT
				ST_Transform(ST_Centroid(area::geometry), 3857) AS center_3857,
				ST_Transform(twice_expanded::geometry, 3857) AS twice_expanded_3857,
				ST_Transform(area::geometry, 3857) AS area_3857
			FROM zone
			WHERE id = ${ZONE_ID}
		),
		params AS (
			SELECT
				center_3857,
				${radiusMeters}::double precision AS radius_m,
				radians(${startAngleDeg}) AS start_rad,
				radians(${endAngleDeg}) AS end_rad,
				${CONE_ARC_SEGMENTS}::integer AS arc_segments
			FROM zone_data
		),
		arc_points AS (
			SELECT
				step,
				ST_SetSRID(
					ST_MakePoint(
						ST_X(center_3857) + radius_m * COS(
							start_rad + ((end_rad - start_rad) * step / arc_segments::double precision)
						),
						ST_Y(center_3857) + radius_m * SIN(
							start_rad + ((end_rad - start_rad) * step / arc_segments::double precision)
						)
					),
					3857
				) AS geom
			FROM params
			CROSS JOIN generate_series(0, ${CONE_ARC_SEGMENTS}) AS step
		),
		ring_points AS (
			SELECT 0 AS ord, center_3857 AS geom
			FROM params

			UNION ALL

			SELECT step + 1 AS ord, geom
			FROM arc_points

			UNION ALL

			SELECT ${CONE_ARC_SEGMENTS + 2} AS ord, center_3857 AS geom
			FROM params
		),
		cone AS (
			SELECT ST_MakePolygon(ST_MakeLine(geom ORDER BY ord)) AS cone_3857
			FROM ring_points
		),
		valid_geom AS (
			SELECT ST_CollectionExtract(
				ST_Difference(
					ST_Intersection(z.twice_expanded_3857, c.cone_3857),
					z.area_3857
				),
				3
			) AS geom
			FROM zone_data z
			CROSS JOIN cone c
		),
		random_point AS (
			SELECT ST_SetSRID(ST_MakePoint(${randomX3857}, ${randomY3857}), 3857) AS pt
		)
		SELECT
			ST_Contains(v.geom, p.pt) AS inside,
			ST_Y(ST_Transform(p.pt, 4326)) AS lat,
			ST_X(ST_Transform(p.pt, 4326)) AS lng
		FROM valid_geom v
		CROSS JOIN random_point p
	`.execute(db);

	const row = result.rows[0];

	if (!row?.inside) {
		return null;
	}

	return {
		lat: row.lat,
		lng: row.lng,
		x: randomX3857,
		y: randomY3857,
	};
}

async function tryRandomSecondPointInZoneArea(
	db: Kysely<DB>,
	randomX3857: number,
	randomY3857: number
): Promise<CandidatePoint | null> {
	const result = await sql<{
		inside: boolean;
		lat: number;
		lng: number;
	}>`
		WITH zone_data AS (
			SELECT ST_Transform(area::geometry, 3857) AS area_3857
			FROM zone
			WHERE id = ${ZONE_ID}
		),
		random_point AS (
			SELECT ST_SetSRID(ST_MakePoint(${randomX3857}, ${randomY3857}), 3857) AS pt
		)
		SELECT
			ST_Contains(z.area_3857, p.pt) AS inside,
			ST_Y(ST_Transform(p.pt, 4326)) AS lat,
			ST_X(ST_Transform(p.pt, 4326)) AS lng
		FROM zone_data z
		CROSS JOIN random_point p
	`.execute(db);

	const row = result.rows[0];

	if (!row?.inside) {
		return null;
	}

	return {
		lat: row.lat,
		lng: row.lng,
		x: randomX3857,
		y: randomY3857,
	};
}

async function findValidFirstPointForCone(args: {
	db: Kysely<DB>;
	startAngleDeg: number;
	endAngleDeg: number;
	radiusMeters: number;
	firstPointBounds: Point3857Bounds;
	stats: ConeStats;
}): Promise<CandidatePoint> {
	const { db, startAngleDeg, endAngleDeg, radiusMeters, firstPointBounds, stats } = args;

	while (true) {
		const x = randomBetween(firstPointBounds.minX, firstPointBounds.maxX);
		const y = randomBetween(firstPointBounds.minY, firstPointBounds.maxY);

		const firstPoint = await tryRandomFirstPointInConeAndTwiceExpandedOutsideZone(
			db,
			startAngleDeg,
			endAngleDeg,
			radiusMeters,
			x,
			y
		);

		if (firstPoint) {
			return firstPoint;
		}

		stats.preSamplingFirstGeometryMisses += 1;
	}
}

async function findValidSecondPointForZone(args: {
	db: Kysely<DB>;
	secondPointBounds: Point3857Bounds;
	stats: ConeStats;
}): Promise<CandidatePoint> {
	const { db, secondPointBounds, stats } = args;

	while (true) {
		const x = randomBetween(secondPointBounds.minX, secondPointBounds.maxX);
		const y = randomBetween(secondPointBounds.minY, secondPointBounds.maxY);

		const secondPoint = await tryRandomSecondPointInZoneArea(db, x, y);

		if (secondPoint) {
			return secondPoint;
		}

		stats.preSamplingSecondGeometryMisses += 1;
	}
}

async function diagnoseFailedPairAndUpdateBlacklists(args: {
	failedPair: CoordinatePair;
	successfulPair: CoordinatePair | null;
	startFailureSquares: FailureSquare[];
	targetFailureSquaresForCone: FailureSquare[];
}) {
	const {
		failedPair,
		successfulPair,
		startFailureSquares,
		targetFailureSquaresForCone,
	} = args;

	if (!successfulPair) {
		return;
	}

	const failedStartToSuccessfulTarget = buildPlanQueryFromPoints(
		failedPair.second,
		successfulPair.first,
		failedPair.queryTimeIso
	);

	const successfulStartToFailedTarget = buildPlanQueryFromPoints(
		successfulPair.second,
		failedPair.first,
		failedPair.queryTimeIso
	);

	const startSeemsBad = !(await validatePlanQuery(failedStartToSuccessfulTarget));
	if (DELAY_BETWEEN_VALIDATION_REQUESTS_MS > 0) {
		await sleep(DELAY_BETWEEN_VALIDATION_REQUESTS_MS);
	}

	const targetSeemsBad = !(await validatePlanQuery(successfulStartToFailedTarget));
	if (DELAY_BETWEEN_VALIDATION_REQUESTS_MS > 0) {
		await sleep(DELAY_BETWEEN_VALIDATION_REQUESTS_MS);
	}

	if (startSeemsBad) {
		addFailureSquare(failedPair.second, startFailureSquares);
	}

	if (targetSeemsBad) {
		addFailureSquare(failedPair.first, targetFailureSquaresForCone);
	}
}

async function generateRandomCoordinatePairs(
	db: Kysely<DB>
): Promise<ConeResult[]> {
	const zoneMetadata = await getZoneMetadata(db);

	console.log(
		`Generating random coordinate pairs for zone ${zoneMetadata.id} (${zoneMetadata.name})`
	);
	console.log(
		`Zone center: lat=${zoneMetadata.centerLat}, lng=${zoneMetadata.centerLng}`
	);
	console.log(`Cone count: ${CONE_COUNT}`);
	console.log(`Pairs per cone: ${PAIRS_PER_CONE}`);
	console.log(`Max attempts per cone: ${MAX_ATTEMPTS_PER_CONE}`);
	console.log(`Validation timeout ms: ${REQUEST_TIMEOUT_MS}`);
	console.log(
		`Delay between validation requests ms: ${DELAY_BETWEEN_VALIDATION_REQUESTS_MS}`
	);
	console.log(`Failure square half-size meters: ${FAILURE_SQUARE_HALF_SIZE_METERS}`);
	console.log(
		'First point pre-sampling uses bbox((twice_expanded ∩ current_cone) \\ zone.area).'
	);
	console.log('Second point pre-sampling uses bbox(zone.area).');
	console.log(
		'Cone attempts start only after both sampled points are geometry-valid.'
	);

	const results: ConeResult[] = [];
	const coneAngleSizeDeg = 360 / CONE_COUNT;

	const startFailureSquares: FailureSquare[] = [];
	let successfulPair: CoordinatePair | null = null;

	for (let coneIndex = 0; coneIndex < CONE_COUNT; coneIndex++) {
		const startAngleDeg = coneIndex * coneAngleSizeDeg;
		const endAngleDeg = (coneIndex + 1) * coneAngleSizeDeg;
		const targetFailureSquaresForCone: FailureSquare[] = [];

		const stats: ConeStats = {
			totalAttempts: 0,
			rejectedByTargetFailureSquare: 0,
			rejectedByStartFailureSquare: 0,
			endpointFailures: 0,
			accepted: 0,
			preSamplingFirstGeometryMisses: 0,
			preSamplingSecondGeometryMisses: 0,
		};

		console.log(
			`Processing cone ${coneIndex + 1}/${CONE_COUNT} (${startAngleDeg}° → ${endAngleDeg}°)`
		);

		// Tight bbox for the target point:
		// bbox((twice_expanded ∩ current_cone) \ zone.area)
		const firstPointBounds = await getConeIntersectionBounds(
			db,
			startAngleDeg,
			endAngleDeg,
			zoneMetadata.coneRadiusMeters
		);

		if (!firstPointBounds) {
			console.log(
				`Cone ${coneIndex} has no valid area in (cone ∩ twice_expanded) \\ area. Skipping.`
			);

			results.push({
				coneIndex,
				startAngleDeg,
				endAngleDeg,
				pairs: [],
				attemptsUsed: 0,
				stoppedBecauseAttemptLimit: false,
				stats,
			});

			continue;
		}

		// Tight bbox for the start point:
		// bbox(zone.area)
		const secondPointBounds = zoneMetadata.areaBounds3857;

		const pairs: CoordinatePair[] = [];
		let attempts = 0;

		while (pairs.length < PAIRS_PER_CONE && attempts < MAX_ATTEMPTS_PER_CONE) {
			const firstPoint = await findValidFirstPointForCone({
				db,
				startAngleDeg,
				endAngleDeg,
				radiusMeters: zoneMetadata.coneRadiusMeters,
				firstPointBounds,
				stats,
			});

			const secondPoint = await findValidSecondPointForZone({
				db,
				secondPointBounds,
				stats,
			});

			attempts += 1;
			stats.totalAttempts += 1;

			if (isInsideFailureSquare(firstPoint, targetFailureSquaresForCone)) {
				stats.rejectedByTargetFailureSquare += 1;

				if (attempts % LOG_EVERY_N_ATTEMPTS === 0) {
					console.log(
						`Cone ${coneIndex}: attempts=${attempts}, accepted=${stats.accepted}, targetSquareRejects=${stats.rejectedByTargetFailureSquare}, startSquareRejects=${stats.rejectedByStartFailureSquare}, endpointFails=${stats.endpointFailures}, preFirstGeomMisses=${stats.preSamplingFirstGeometryMisses}, preSecondGeomMisses=${stats.preSamplingSecondGeometryMisses}`
					);
				}
				continue;
			}

			if (isInsideFailureSquare(secondPoint, startFailureSquares)) {
				stats.rejectedByStartFailureSquare += 1;

				if (attempts % LOG_EVERY_N_ATTEMPTS === 0) {
					console.log(
						`Cone ${coneIndex}: attempts=${attempts}, accepted=${stats.accepted}, targetSquareRejects=${stats.rejectedByTargetFailureSquare}, startSquareRejects=${stats.rejectedByStartFailureSquare}, endpointFails=${stats.endpointFailures}, preFirstGeomMisses=${stats.preSamplingFirstGeometryMisses}, preSecondGeomMisses=${stats.preSamplingSecondGeometryMisses}`
					);
				}
				continue;
			}

			const pair: CoordinatePair = {
				first: firstPoint,
				second: secondPoint,
				attemptNumber: attempts,
				queryTimeIso: randomQueryTimeIso(),
			};

			const isValid = await validatePairWithPlanAndSign(pair);

			if (!isValid) {
				stats.endpointFailures += 1;

				await diagnoseFailedPairAndUpdateBlacklists({
					failedPair: pair,
					successfulPair,
					startFailureSquares,
					targetFailureSquaresForCone,
				});

				if (DELAY_BETWEEN_VALIDATION_REQUESTS_MS > 0) {
					await sleep(DELAY_BETWEEN_VALIDATION_REQUESTS_MS);
				}

				if (attempts % LOG_EVERY_N_ATTEMPTS === 0) {
					console.log(
						`Cone ${coneIndex}: attempts=${attempts}, accepted=${stats.accepted}, targetSquareRejects=${stats.rejectedByTargetFailureSquare}, startSquareRejects=${stats.rejectedByStartFailureSquare}, endpointFails=${stats.endpointFailures}, preFirstGeomMisses=${stats.preSamplingFirstGeometryMisses}, preSecondGeomMisses=${stats.preSamplingSecondGeometryMisses}`
					);
				}
				continue;
			}

			pairs.push(pair);
			successfulPair = pair;
			stats.accepted += 1;

			console.log(
				`Cone ${coneIndex}: accepted ${pairs.length}/${PAIRS_PER_CONE} after ${attempts} counted attempts`
			);

			if (DELAY_BETWEEN_VALIDATION_REQUESTS_MS > 0) {
				await sleep(DELAY_BETWEEN_VALIDATION_REQUESTS_MS);
			}
		}

		const stoppedBecauseAttemptLimit = attempts >= MAX_ATTEMPTS_PER_CONE;

		results.push({
			coneIndex,
			startAngleDeg,
			endAngleDeg,
			pairs,
			attemptsUsed: attempts,
			stoppedBecauseAttemptLimit,
			stats,
		});

		console.log(
			`Finished cone ${coneIndex}: pairs=${pairs.length}/${PAIRS_PER_CONE}, countedAttempts=${attempts}, limitReached=${stoppedBecauseAttemptLimit}`
		);
		console.log(`Cone ${coneIndex} stats: ${JSON.stringify(stats)}`);
	}

	return results;
}

async function main() {
	const db = createDb();

	try {
		await ensureTwiceExpandedColumn(db);
		await updateZoneExpansions(db);

		const results = await generateRandomCoordinatePairs(db);
		const queries = buildPlanQueries(results);
		const commands = buildCurlCommands(queries);

		await writeCommandsToResultsFile(commands);

		console.log('========================================');
		console.log('RESULT FILE WRITTEN');
		console.log('========================================');
		console.log(`Commands written to: ${RESULTS_FILE_PATH}`);
		console.log(`Command count: ${commands.length}`);
	} finally {
		await db.destroy();
	}
}

main().catch((error) => {
	console.error(error);
	process.exit(1);
});