import type { Coordinates } from '$lib/util/Coordinates';

export type Condition = {
	evalAfterStep: number;
	entity: string;
	company?: Coordinates;
	start?: Coordinates;
	destination?: Coordinates;
	expectedPosition?: number;
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
	}
];
