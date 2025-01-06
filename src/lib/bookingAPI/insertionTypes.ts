import type { Vehicle } from '$lib/compositionTypes';
import type { Range } from './capacitySimulation';

export enum InsertWhere {
	BEFORE_FIRST_EVENT,
	AFTER_LAST_EVENT,
	BETWEEN_EVENTS,
	BETWEEN_TOURS
}

export enum InsertHow {
	CONNECT,
	APPEND,
	PREPEND,
	INSERT,
	NEW_TOUR
}

export enum InsertWhat {
	USER_CHOSEN,
	BUS_STOP,
	BOTH
}

export enum InsertDirection {
	TO_BUS_STOP,
	FROM_BUS_STOP
}

export type InsertionType = {
	how: InsertHow;
	direction: InsertDirection;
	where: InsertWhere;
	what: InsertWhat;
};

export function printInsertionType (t: InsertionType) {
	let ret = "how: ";
	switch(t.how) {
		case InsertHow.APPEND: ret += "APPEND";break;
		case InsertHow.PREPEND: ret += "PREPEND";break;
		case InsertHow.CONNECT: ret += "CONNECT";break;
		case InsertHow.NEW_TOUR: ret += "NEW_TOUR";break;
		case InsertHow.INSERT: ret += "INSERT";break;
	}
	ret += ", where: ";
	switch(t.where) {
		case InsertWhere.AFTER_LAST_EVENT: ret += "AFTER_LAST_EVENT";break;
		case InsertWhere.BEFORE_FIRST_EVENT: ret += "BEFORE_FIRST_EVENT";break;
		case InsertWhere.BETWEEN_EVENTS: ret += "BETWEEN_EVENTS";break;
		case InsertWhere.BETWEEN_TOURS: ret += "BETWEEN_TOURS";break;
	}
	ret += ", what: ";
	switch(t.what) {
		case InsertWhat.BOTH: ret+= "BOTH";break;
		case InsertWhat.BUS_STOP: ret+= "BUS_STOP";break;
		case InsertWhat.USER_CHOSEN: ret+= "USER_CHOSEN";break;
	}
	ret += ", direction: ";
	switch(t.direction) {
		case InsertDirection.FROM_BUS_STOP: ret+= "FROM_BUS_STOP";break;
		case InsertDirection.TO_BUS_STOP: ret+= "TO_BUS_STOP";break;
	}
	return ret;
}

export type InsertionInfo = {
	companyIdx: number;
	prevEventIdxInRoutingResults: number;
	nextEventIdxInRoutingResults: number;
	vehicle: Vehicle;
	idxInEvents: number;
	currentRange: Range;
};

export const INSERTION_TYPES = [
	InsertHow.CONNECT,
	InsertHow.APPEND,
	InsertHow.PREPEND,
	InsertHow.INSERT
];

export const canCaseBeValid = (insertionCase: InsertionType): boolean => {
	switch (insertionCase.where) {
		case InsertWhere.BEFORE_FIRST_EVENT:
			return insertionCase.how == InsertHow.PREPEND;
		case InsertWhere.AFTER_LAST_EVENT:
			return insertionCase.how == InsertHow.APPEND;
		case InsertWhere.BETWEEN_TOURS:
			return insertionCase.how != InsertHow.INSERT;
		case InsertWhere.BETWEEN_EVENTS:
			return insertionCase.how == InsertHow.INSERT;
	}
};

export const isCaseValid = (insertionCase: InsertionType): boolean => {
	switch (insertionCase.what) {
		case InsertWhat.USER_CHOSEN:
			return (
				insertionCase.how !=
				(insertionCase.direction == InsertDirection.TO_BUS_STOP
					? InsertHow.APPEND
					: InsertHow.PREPEND)
			);
		case InsertWhat.BUS_STOP:
			return (
				insertionCase.how !=
				(insertionCase.direction == InsertDirection.TO_BUS_STOP
					? InsertHow.PREPEND
					: InsertHow.APPEND)
			);
		case InsertWhat.BOTH:
			return true;
	}
};
