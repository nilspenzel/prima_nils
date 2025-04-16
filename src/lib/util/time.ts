export const SECOND = 1000;
export const MINUTE = SECOND * 60;
export const HOUR = MINUTE * 60;
export const DAY = HOUR * 24;
let simulationTime: Date | undefined = undefined;

export function milliToSecond(milli: number): number {
	return Math.floor(milli / SECOND);
}

export function secondToMilli(second: number): number {
	return second * SECOND;
}

export function setSimulationTime(t: string) {
	simulationTime = new Date(t);
}

export function nowOrSimulationTime() {
	if (simulationTime) {
		console.log('SIMULATION_TIME: ' + process.env.SIMULATION_TIME);
		return new Date(simulationTime);
	} else {
		return new Date();
	}
}

export function roundToUnit(n: number, unit: number, roundFn: (n: number) => number) {
	return roundFn(n / unit) * unit;
}
