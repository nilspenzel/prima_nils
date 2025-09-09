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

export enum InsertWhere {
	BEFORE_FIRST_EVENT,
	AFTER_LAST_EVENT,
	BETWEEN_EVENTS,
	BETWEEN_TOURS
}

export enum InsertDirection {
	BUS_STOP_DROPOFF,
	BUS_STOP_PICKUP
}

export function insertHowToString(how: InsertHow) {
	switch (how) {
		case InsertHow.APPEND:
			return 'APPEND';
		case InsertHow.PREPEND:
			return 'PREPEND';
		case InsertHow.CONNECT:
			return 'CONNECT';
		case InsertHow.NEW_TOUR:
			return 'NEW_TOUR';
		case InsertHow.INSERT:
			return 'INSERT';
	}
}

export function insertDirectionToString(direction: InsertDirection) {
	switch (direction) {
		case InsertDirection.BUS_STOP_PICKUP:
			return 'FROM_BUS_STOP';
		case InsertDirection.BUS_STOP_DROPOFF:
			return 'TO_BUS_STOP';
	}
}

export function insertWhatToString(what: InsertWhat) {
	switch (what) {
		case InsertWhat.BOTH:
			return 'BOTH';
		case InsertWhat.BUS_STOP:
			return 'BUS_STOP';
		case InsertWhat.USER_CHOSEN:
			return 'USER_CHOSEN';
	}
}

export function insertWhereToString(where: InsertWhere) {
	switch (where) {
		case InsertWhere.AFTER_LAST_EVENT:
			return 'AFTER_LAST_EVENT';
		case InsertWhere.BEFORE_FIRST_EVENT:
			return 'BEFORE_FIRST_EVENT';
		case InsertWhere.BETWEEN_EVENTS:
			return 'BETWEEN_EVENTS';
		case InsertWhere.BETWEEN_TOURS:
			return 'BETWEEN_TOURS';
	}
}
