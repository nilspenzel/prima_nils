import type { TestParams } from '$lib/util/booking/testParams';

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
		uuid: '1'
	}
];
