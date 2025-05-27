import type { Coordinates } from '../Coordinates';

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
