import type { InsertHow, InsertWhat } from '$lib/util/booking/insertionTypes';

export type DebugInfo = {
	prevEventId?: number;
	nextEventId?: number;
	how?: InsertHow;
	what?: InsertWhat;
	vehicleId?: number;
};

export function debugInfoMatches(
	debugInfo: DebugInfo,
	how: InsertHow,
	what?: InsertWhat,
	prevEventId?: number,
	nextEventId?: number,
	vehicleId?: number
) {
	if (debugInfo.prevEventId !== undefined && prevEventId !== debugInfo.prevEventId) {
		return false;
	}
	if (debugInfo.nextEventId !== undefined && nextEventId !== debugInfo.nextEventId) {
		return false;
	}
	if (debugInfo.how !== undefined && how !== debugInfo.how) {
		return false;
	}
	if (debugInfo.what !== undefined  && what !== undefined && what !== debugInfo.what) {
		return false;
	}
	if (debugInfo.vehicleId !== undefined && vehicleId !== debugInfo.vehicleId) {
		return false;
	}
	return true;
}
