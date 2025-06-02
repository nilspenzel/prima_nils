import type { TestParams } from '$lib/util/booking/testParams';

export const tests: TestParams[] = [
	// printhere
// startoftest
		{
	  "conditions": [
	    {
	      "evalAfterStep": 0,
	      "entity": "requestCompanyMatch",
	      "start": {
	        "lat": 51.49060264996811,
	        "lng": 14.625531716946114
	      },
	      "destination": {
	        "lat": 51.491209466285426,
	        "lng": 14.661981306469755
	      },
	      "company": {
	        "lat": 51.482329691448484,
	        "lng": 14.651830066327534
	      },
	      "expectedPosition": null,
	      "tourCount": null,
	      "requestCount": null
	    }
	  ],
	  "process": {
	    "starts": [
	      {
	        "lat": 51.49060264996811,
	        "lng": 14.625531716946114
	      }
	    ],
	    "destinations": [
	      {
	        "lat": 51.491209466285426,
	        "lng": 14.661981306469755
	      }
	    ],
	    "times": [
	      1749123470408
	    ],
	    "isDepartures": [
	      true
	    ],
	    "companies": [
	      {
	        "lat": 51.51942429622022,
	        "lng": 14.663163034255547
	      },
	      {
	        "lat": 51.52852265326581,
	        "lng": 14.60064892090358
	      },
	      {
	        "lat": 51.482329691448484,
	        "lng": 14.651830066327534
	      }
	    ]
	  },
	  "uuid": "b4f64dfe-2130-4978-b322-b3d56d31e090"
	},
// endoftest

// startoftest
		{
	  "conditions": [
	    {
	      "evalAfterStep": 0,
	      "entity": "requestCount",
	      "tourCount": -1,
	      "requestCount": 1,
	      "expectedPosition": -1,
	      "start": null,
	      "destination": null,
	      "company": null
	    }
	  ],
	  "process": {
	    "starts": [
	      {
	        "lat": 51.5097590428102,
	        "lng": 14.742580233557334
	      }
	    ],
	    "destinations": [
	      {
	        "lat": 51.514950532171554,
	        "lng": 14.754356902851555
	      }
	    ],
	    "times": [
	      1749123340891
	    ],
	    "isDepartures": [
	      true
	    ],
	    "companies": [
	      {
	        "lat": 51.5026080337135,
	        "lng": 14.71234901479113
	      }
	    ]
	  },
	  "uuid": "fb869d06-6999-458c-9c75-14a42dc1d775"
	},
// endoftest

// startoftest
		{
	  "conditions": [
	    {
	      "evalAfterStep": 0,
	      "entity": "requestCompanyMatch",
	      "start": {
	        "lat": 51.484850160402175,
	        "lng": 14.722058640450342
	      },
	      "destination": {
	        "lat": 51.457614225700326,
	        "lng": 14.75446116220752
	      },
	      "company": {
	        "lat": 51.49209954968157,
	        "lng": 14.721071772023038
	      },
	      "expectedPosition": null,
	      "tourCount": null,
	      "requestCount": null
	    }
	  ],
	  "process": {
	    "starts": [
	      {
	        "lat": 51.484850160402175,
	        "lng": 14.722058640450342
	      }
	    ],
	    "destinations": [
	      {
	        "lat": 51.457614225700326,
	        "lng": 14.75446116220752
	      }
	    ],
	    "times": [
	      1749121411730
	    ],
	    "isDepartures": [
	      true
	    ],
	    "companies": [
	      {
	        "lat": 51.53048792186061,
	        "lng": 14.707017666200642
	      },
	      {
	        "lat": 51.49209954968157,
	        "lng": 14.721071772023038
	      },
	      {
	        "lat": 51.47965211310424,
	        "lng": 14.899856519544784
	      },
	      {
	        "lat": 51.40387475880436,
	        "lng": 14.531124261308321
	      },
	      {
	        "lat": 51.384902207670535,
	        "lng": 14.616315986356199
	      },
	      {
	        "lat": 51.502636235270955,
	        "lng": 14.711413136930162
	      }
	    ]
	  },
	  "uuid": "0404b58c-f62d-4f60-ad8c-d9d2c57ed5ad"
	},
// endoftest

// startoftest
		{
	  "conditions": [
	    {
	      "evalAfterStep": 0,
	      "entity": "requestCompanyMatch",
	      "start": {
	        "lat": 51.414031522923324,
	        "lng": 14.587200695662574
	      },
	      "destination": {
	        "lat": 51.420838812774434,
	        "lng": 14.546268001544718
	      },
	      "company": {
	        "lat": 51.40892712567921,
	        "lng": 14.555387900612914
	      },
	      "expectedPosition": null,
	      "tourCount": null,
	      "requestCount": null
	    }
	  ],
	  "process": {
	    "starts": [
	      {
	        "lat": 51.414031522923324,
	        "lng": 14.587200695662574
	      }
	    ],
	    "destinations": [
	      {
	        "lat": 51.420838812774434,
	        "lng": 14.546268001544718
	      }
	    ],
	    "times": [
	      1749120368965
	    ],
	    "isDepartures": [
	      true
	    ],
	    "companies": [
	      {
	        "lat": 51.50202983176706,
	        "lng": 14.711266099437012
	      },
	      {
	        "lat": 51.40892712567921,
	        "lng": 14.555387900612914
	      }
	    ]
	  },
	  "uuid": "599cb1cd-74bd-4096-aeaf-edb121c26cd9"
	},
// endoftest

];
