import type { Coordinates } from '$lib/util/Coordinates';

export type Condition = {
	evalAfterStep: number;
	entity: string;
	company?: Coordinates;
	start?: Coordinates;
	destination?: Coordinates;
	startIdxInTimeSortedTour?: number;
	destinationIdxInTimeSortedTour?: number;
	tourCount?: number;
	requestCount?: number;
};

export type TestProcess = {
	companies: Coordinates[];
	starts: Coordinates[];
	destinations: Coordinates[];
	times: number[];
	isDepartures: boolean[];
};

export type TestParams = {
	process: TestProcess;
	conditions: Condition[];
	uuid: string;
};

export const tests: TestParams[] = [
	{
		uuid: '1',
		conditions: [
			{
				evalAfterStep: 0,
				entity: 'tourCount',
				tourCount: 1,
				requestCount: 0,
				startIdxInTimeSortedTour: 0,
				destinationIdxInTimeSortedTour: 0
			},
			{
				evalAfterStep: 0,
				entity: 'requestCount',
				tourCount: 1,
				requestCount: 1,
				startIdxInTimeSortedTour: 0,
				destinationIdxInTimeSortedTour: 0
			}
		],
		process: {
			starts: [
				{
					lat: 51.41338108635742,
					lng: 14.586166197540251
				}
			],
			destinations: [
				{
					lat: 51.478652953930094,
					lng: 14.6620580024329
				}
			],
			times: [1748507952806],
			isDepartures: [true],
			companies: [
				{
					lat: 51.4119808067274,
					lng: 14.582142097790353
				},
				{
					lat: 51.485117908927776,
					lng: 14.843755355753473
				}
			]
		}
	}
];
