let simulationTime: Date | undefined = undefined;

export function setSimulationTime(t: number) {
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
