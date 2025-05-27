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
	// printhere
	{
		conditions: [
			{
				evalAfterStep: 0,
				entity: 'requestCompanyMatch',
				start: {
					lat: 51.50160511059539,
					lng: 14.715852084016717
				},
				destination: {
					lat: 51.49160769764529,
					lng: 14.716166957112847
				},
				company: {
					lat: 51.51281106529095,
					lng: 14.74984948040995
				}
			}
		],
		process: {
			starts: [
				{
					lat: 51.50160511059539,
					lng: 14.715852084016717
				}
			],
			destinations: [
				{
					lat: 51.49160769764529,
					lng: 14.716166957112847
				}
			],
			times: [1748599200403],
			isDepartures: [true],
			companies: [
				{
					lat: 51.51281106529095,
					lng: 14.74984948040995
				},
				{
					lat: 51.43291180971573,
					lng: 14.783953304677055
				}
			]
		},
		uuid: 'fb0c53ed-7a1e-4439-a28a-be4425e35426'
	},
	{
		conditions: [
			{
				evalAfterStep: 0,
				entity: 'requestCompanyMatch',
				start: {
					lat: 51.537015283793494,
					lng: 14.608825073401135
				},
				destination: {
					lat: 51.53918656449426,
					lng: 14.594695490056267
				},
				company: {
					lat: 51.537190960856094,
					lng: 14.632143533304486
				}
			}
		],
		process: {
			starts: [
				{
					lat: 51.537015283793494,
					lng: 14.608825073401135
				}
			],
			destinations: [
				{
					lat: 51.53918656449426,
					lng: 14.594695490056267
				}
			],
			times: [1748590615492],
			isDepartures: [true],
			companies: [
				{
					lat: 51.537190960856094,
					lng: 14.632143533304486
				},
				{
					lat: 51.5360501900239,
					lng: 14.669216422668057
				}
			]
		},
		uuid: '22a5d98e-317c-429a-9a85-b90765e7325b'
	},
	{
		uuid: '22a5d98e-317c-429a-9a85-b90765e7325a',
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
