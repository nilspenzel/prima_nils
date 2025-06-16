import type { TestParams } from '$lib/util/booking/testParams';

export const tests: TestParams[] = [
	// printhere
	// startoftest
	{
		conditions: [
			{
				evalAfterStep: 1,
				entity: 'requestCount',
				tourCount: -1,
				requestCount: 2,
				expectedPosition: null,
				start: null,
				destination: null,
				company: null
			},
			{
				evalAfterStep: 1,
				entity: 'tourCount',
				tourCount: 1,
				requestCount: -1,
				expectedPosition: null,
				start: null,
				destination: null,
				company: null
			},
			{
				evalAfterStep: 2,
				entity: 'requestCount',
				tourCount: -1,
				requestCount: 3,
				expectedPosition: null,
				start: null,
				destination: null,
				company: null
			},
			{
				evalAfterStep: 2,
				entity: 'tourCount',
				tourCount: 1,
				requestCount: -1,
				expectedPosition: null,
				start: null,
				destination: null,
				company: null
			}
		],
		process: {
			starts: [
				{
					lat: 51.527358114107585,
					lng: 14.697645909939212
				},
				{
					lat: 51.48886873577544,
					lng: 14.629302941137638
				},
				{
					lat: 51.518385803966225,
					lng: 14.661366479080641
				}
			],
			destinations: [
				{
					lat: 51.520202846066724,
					lng: 14.664217543076205
				},
				{
					lat: 51.47846438451026,
					lng: 14.661735025493101
				},
				{
					lat: 51.49116349369399,
					lng: 14.625863174614835
				}
			],
			times: [1750247620692, 1750248850692, 1750247940000],
			isDepartures: [true, true, true],
			companies: [
				{
					lat: 51.530278670149244,
					lng: 14.706657669152918
				}
			]
		},
		uuid: '4f6728fa-2cd0-42e4-9c49-eb7386d3fcfx'
	},
	// endoftest

	// startoftest
	{
		conditions: [
			{
				evalAfterStep: 1,
				entity: 'requestCount',
				tourCount: -1,
				requestCount: 2,
				expectedPosition: null,
				start: null,
				destination: null,
				company: null
			},
			{
				evalAfterStep: 1,
				entity: 'tourCount',
				tourCount: 1,
				requestCount: -1,
				expectedPosition: null,
				start: null,
				destination: null,
				company: null
			},
			{
				evalAfterStep: 2,
				entity: 'requestCount',
				tourCount: -1,
				requestCount: 3,
				expectedPosition: null,
				start: null,
				destination: null,
				company: null
			},
			{
				evalAfterStep: 2,
				entity: 'tourCount',
				tourCount: 1,
				requestCount: -1,
				expectedPosition: null,
				start: null,
				destination: null,
				company: null
			}
		],
		process: {
			starts: [
				{
					lat: 51.527358114107585,
					lng: 14.697645909939212
				},
				{
					lat: 51.48886873577544,
					lng: 14.629302941137638
				},
				{
					lat: 51.518385803966225,
					lng: 14.661366479080641
				}
			],
			destinations: [
				{
					lat: 51.520202846066724,
					lng: 14.664217543076205
				},
				{
					lat: 51.47846438451026,
					lng: 14.661735025493101
				},
				{
					lat: 51.49116349369399,
					lng: 14.625863174614835
				}
			],
			times: [1750247670692, 1750248850692, 1750247940000],
			isDepartures: [true, true, true],
			companies: [
				{
					lat: 51.530278670149244,
					lng: 14.706657669152918
				}
			]
		},
		uuid: '4f6728fa-2cd0-42e4-9c49-eb7386d3fcff'
	},
	// endoftest

	// startoftest
	{
		conditions: [
			{
				evalAfterStep: 1,
				entity: 'requestCount',
				tourCount: -1,
				requestCount: 2,
				expectedPosition: null,
				start: null,
				destination: null,
				company: null
			},
			{
				evalAfterStep: 1,
				entity: 'tourCount',
				tourCount: 1,
				requestCount: -1,
				expectedPosition: null,
				start: null,
				destination: null,
				company: null
			}
		],
		process: {
			starts: [
				{
					lat: 51.50049423863311,
					lng: 14.700125777933437
				},
				{
					lat: 51.49891682074758,
					lng: 14.636875019641622
				}
			],
			destinations: [
				{
					lat: 51.491453680659845,
					lng: 14.661142259725608
				},
				{
					lat: 51.51571958072245,
					lng: 14.656366778744939
				}
			],
			times: [1749206842990, 1749207742990],
			isDepartures: [true, true],
			companies: [
				{
					lat: 51.502278807277605,
					lng: 14.711610880111863
				}
			]
		},
		uuid: 'd1fad5fb-f841-4e3c-b21d-a35663f71039'
	},
	// endoftest

	// startoftest
	{
		conditions: [
			{
				evalAfterStep: 1,
				entity: 'startPosition',
				tourCount: -1,
				requestCount: -1,
				expectedPosition: 0,
				start: {
					lat: 51.49465839904684,
					lng: 14.719442801988833
				},
				destination: {
					lat: 51.47958853282958,
					lng: 14.72251402209821
				},
				company: null
			}
		],
		process: {
			starts: [
				{
					lat: 51.49465839904684,
					lng: 14.719442801988833
				},
				{
					lat: 51.47606896351152,
					lng: 14.722514022099006
				}
			],
			destinations: [
				{
					lat: 51.47958853282958,
					lng: 14.72251402209821
				},
				{
					lat: 51.46336565051166,
					lng: 14.74487250449556
				}
			],
			times: [1749143608824, 1749143908824],
			isDepartures: [true, true],
			companies: [
				{
					lat: 51.5021304238399,
					lng: 14.7129780281048
				}
			]
		},
		uuid: '73e5bae1-3648-43d9-8db2-399875e13fe8'
	},
	// endoftest

	// startoftest
	{
		conditions: [
			{
				evalAfterStep: 0,
				entity: 'requestCount',
				tourCount: -1,
				requestCount: 1,
				expectedPosition: -1,
				start: null,
				destination: null,
				company: null
			},
			{
				evalAfterStep: 1,
				entity: 'requestCount',
				tourCount: -1,
				requestCount: 2,
				expectedPosition: -1,
				start: null,
				destination: null,
				company: null
			},
			{
				evalAfterStep: 1,
				entity: 'tourCount',
				tourCount: 1,
				requestCount: -1,
				expectedPosition: -1,
				start: null,
				destination: null,
				company: null
			}
		],
		process: {
			starts: [
				{
					lat: 51.49515596447975,
					lng: 14.679697910637685
				},
				{
					lat: 51.50544687066633,
					lng: 14.642429986843212
				}
			],
			destinations: [
				{
					lat: 51.49939898802958,
					lng: 14.635469440764979
				},
				{
					lat: 51.51970586364183,
					lng: 14.66316661370189
				}
			],
			times: [1749138735856, 1749139335856],
			isDepartures: [true, true],
			companies: [
				{
					lat: 51.509779188629835,
					lng: 14.741907791211815
				}
			]
		},
		uuid: '09c7e76e-14cf-40cf-b32b-6a3ea5a43099'
	},
	// endoftest

	// startoftest
	{
		conditions: [
			{
				evalAfterStep: 0,
				entity: 'requestCompanyMatch',
				start: {
					lat: 51.49060264996811,
					lng: 14.625531716946114
				},
				destination: {
					lat: 51.491209466285426,
					lng: 14.661981306469755
				},
				company: {
					lat: 51.482329691448484,
					lng: 14.651830066327534
				},
				expectedPosition: null,
				tourCount: null,
				requestCount: null
			}
		],
		process: {
			starts: [
				{
					lat: 51.49060264996811,
					lng: 14.625531716946114
				}
			],
			destinations: [
				{
					lat: 51.491209466285426,
					lng: 14.661981306469755
				}
			],
			times: [1749123470408],
			isDepartures: [true],
			companies: [
				{
					lat: 51.51942429622022,
					lng: 14.663163034255547
				},
				{
					lat: 51.52852265326581,
					lng: 14.60064892090358
				},
				{
					lat: 51.482329691448484,
					lng: 14.651830066327534
				}
			]
		},
		uuid: 'b4f64dfe-2130-4978-b322-b3d56d31e090'
	},
	// endoftest

	// startoftest
	{
		conditions: [
			{
				evalAfterStep: 0,
				entity: 'requestCount',
				tourCount: -1,
				requestCount: 1,
				expectedPosition: -1,
				start: null,
				destination: null,
				company: null
			}
		],
		process: {
			starts: [
				{
					lat: 51.5097590428102,
					lng: 14.742580233557334
				}
			],
			destinations: [
				{
					lat: 51.514950532171554,
					lng: 14.754356902851555
				}
			],
			times: [1749123340891],
			isDepartures: [true],
			companies: [
				{
					lat: 51.5026080337135,
					lng: 14.71234901479113
				}
			]
		},
		uuid: 'fb869d06-6999-458c-9c75-14a42dc1d775'
	},
	// endoftest

	// startoftest
	{
		conditions: [
			{
				evalAfterStep: 0,
				entity: 'requestCompanyMatch',
				start: {
					lat: 51.484850160402175,
					lng: 14.722058640450342
				},
				destination: {
					lat: 51.457614225700326,
					lng: 14.75446116220752
				},
				company: {
					lat: 51.49209954968157,
					lng: 14.721071772023038
				},
				expectedPosition: null,
				tourCount: null,
				requestCount: null
			}
		],
		process: {
			starts: [
				{
					lat: 51.484850160402175,
					lng: 14.722058640450342
				}
			],
			destinations: [
				{
					lat: 51.457614225700326,
					lng: 14.75446116220752
				}
			],
			times: [1749121411730],
			isDepartures: [true],
			companies: [
				{
					lat: 51.53048792186061,
					lng: 14.707017666200642
				},
				{
					lat: 51.49209954968157,
					lng: 14.721071772023038
				},
				{
					lat: 51.47965211310424,
					lng: 14.899856519544784
				},
				{
					lat: 51.40387475880436,
					lng: 14.531124261308321
				},
				{
					lat: 51.384902207670535,
					lng: 14.616315986356199
				},
				{
					lat: 51.502636235270955,
					lng: 14.711413136930162
				}
			]
		},
		uuid: '0404b58c-f62d-4f60-ad8c-d9d2c57ed5ad'
	},
	// endoftest

	// startoftest
	{
		conditions: [
			{
				evalAfterStep: 0,
				entity: 'requestCompanyMatch',
				start: {
					lat: 51.414031522923324,
					lng: 14.587200695662574
				},
				destination: {
					lat: 51.420838812774434,
					lng: 14.546268001544718
				},
				company: {
					lat: 51.40892712567921,
					lng: 14.555387900612914
				},
				expectedPosition: null,
				tourCount: null,
				requestCount: null
			}
		],
		process: {
			starts: [
				{
					lat: 51.414031522923324,
					lng: 14.587200695662574
				}
			],
			destinations: [
				{
					lat: 51.420838812774434,
					lng: 14.546268001544718
				}
			],
			times: [1749120368965],
			isDepartures: [true],
			companies: [
				{
					lat: 51.50202983176706,
					lng: 14.711266099437012
				},
				{
					lat: 51.40892712567921,
					lng: 14.555387900612914
				}
			]
		},
		uuid: '599cb1cd-74bd-4096-aeaf-edb121c26cd9'
	}
	// endoftest
];
