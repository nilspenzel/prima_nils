import { MIN_PREP } from '$lib/constants';
import { Interval } from './interval';
import { DAY, MINUTE, nowOrSimulationTime, roundToUnit } from './time';

export function getAlterableTimeframe() {
	return new Interval(
		roundToUnit(nowOrSimulationTime().getTime() + MIN_PREP, 15 * MINUTE, Math.ceil),
		roundToUnit(nowOrSimulationTime().getTime(), DAY, Math.ceil) + 14 * DAY
	);
}
