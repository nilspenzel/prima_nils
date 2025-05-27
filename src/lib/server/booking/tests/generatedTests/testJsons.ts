import type { TestParams } from '$lib/util/booking/testParams';

export const tests: TestParams[] = [
	// printhere
	{
		conditions: [
			{
				evalAfterStep: 0,
				entity: 'requestCompanyMatch',
				start: {
					lat: 51.49141246721595,
					lng: 14.66347074842841
				},
				destination: {
					lat: 51.501059305648226,
					lng: 14.631789153208189
				},
				company: {
					lat: 51.502224322527155,
					lng: 14.711986646723346
				},
				expectedPosition: null,
				tourCount: null,
				requestCount: null
			},
			{
				evalAfterStep: 0,
				entity: 'tourCount',
				tourCount: 1,
				requestCount: 0,
				expectedPosition: null,
				start: null,
				destination: null,
				company: null
			},
			{
				evalAfterStep: 0,
				entity: 'requestCount',
				tourCount: 1,
				requestCount: 1,
				expectedPosition: null,
				start: null,
				destination: null,
				company: null
			}
		],
		process: {
			starts: [
				{
					lat: 51.49141246721595,
					lng: 14.66347074842841
				}
			],
			destinations: [
				{
					lat: 51.501059305648226,
					lng: 14.631789153208189
				}
			],
			times: [1748613334553],
			isDepartures: [true],
			companies: [
				{
					lat: 51.50957440354972,
					lng: 14.741840514758508
				},
				{
					lat: 51.502224322527155,
					lng: 14.711986646723346
				}
			]
		},
		uuid: '68965bc4-a93a-4ffc-8559-4cbc81946107'
	}
];
