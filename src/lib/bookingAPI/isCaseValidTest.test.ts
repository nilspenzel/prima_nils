import { describe, it, expect } from 'vitest';
import {
	InsertDirection,
	InsertHow,
	InsertWhat,
	InsertWhere,
	canCaseBeValid,
	type InsertionType
} from './insertionTypes';

describe('is case valid test', () => {
	it('only Prepend before first event', () => {
		const cases: InsertionType[] = [];
		for (const how of Object.values(InsertHow) as InsertHow[]) {
			for (const what of Object.values(InsertWhat) as InsertWhat[]) {
				for (const direction of Object.values(InsertDirection) as InsertDirection[]) {
					if (how == InsertHow.PREPEND) {
						continue;
					}
					cases.push({ how, what, where: InsertWhere.BEFORE_FIRST_EVENT, direction });
				}
			}
		}
		for (let i = 0; i != cases.length; ++i) {
			expect(canCaseBeValid(cases[i])).toBe(false);
		}
	});
	it('only Append after last event', () => {
		const cases: InsertionType[] = [];
		for (const how of Object.values(InsertHow) as InsertHow[]) {
			for (const what of Object.values(InsertWhat) as InsertWhat[]) {
				for (const direction of Object.values(InsertDirection) as InsertDirection[]) {
					if (how == InsertHow.APPEND) {
						continue;
					}
					cases.push({ how, what, where: InsertWhere.AFTER_LAST_EVENT, direction });
				}
			}
		}
		for (let i = 0; i != cases.length; ++i) {
			expect(canCaseBeValid(cases[i])).toBe(false);
		}
	});
	it('verify between events is insert', () => {
		const cases: InsertionType[] = [];
		for (const how of Object.values(InsertHow) as InsertHow[]) {
			for (const what of Object.values(InsertWhat) as InsertWhat[]) {
				for (const direction of Object.values(InsertDirection) as InsertDirection[]) {
					if (how == InsertHow.INSERT) {
						continue;
					}
					cases.push({ how, what, where: InsertWhere.BETWEEN_EVENTS, direction });
				}
			}
		}
		for (let i = 0; i != cases.length; ++i) {
			expect(canCaseBeValid(cases[i])).toBe(false);
		}
	});
	it('verify between tours is not insert', () => {
		const cases: InsertionType[] = [];
		for (const how of Object.values(InsertHow) as InsertHow[]) {
			for (const what of Object.values(InsertWhat) as InsertWhat[]) {
				for (const direction of Object.values(InsertDirection) as InsertDirection[]) {
					if (how != InsertHow.INSERT) {
						continue;
					}
					cases.push({ how, what, where: InsertWhere.BETWEEN_TOURS, direction });
				}
			}
		}
		for (let i = 0; i != cases.length; ++i) {
			expect(canCaseBeValid(cases[i])).toBe(false);
		}
	});
	it('verify correct direction for prepend and append', () => {
		const appendValid: InsertionType[] = [];
		const prependValid: InsertionType[] = [];
		const appendInvalid: InsertionType[] = [];
		const prependInvalid: InsertionType[] = [];
		for (const where of Object.values(InsertWhere).filter(
			(value) => typeof value === 'number'
		) as InsertWhere[]) {
			if (where == InsertWhere.BETWEEN_EVENTS) {
				continue;
			}
			if (where != InsertWhere.BEFORE_FIRST_EVENT) {
				appendValid.push({
					how: InsertHow.APPEND,
					what: InsertWhat.BOTH,
					where,
					direction: InsertDirection.FROM_BUS_STOP
				});
				appendValid.push({
					how: InsertHow.APPEND,
					what: InsertWhat.BOTH,
					where,
					direction: InsertDirection.TO_BUS_STOP
				});
				appendValid.push({
					how: InsertHow.APPEND,
					what: InsertWhat.USER_CHOSEN,
					where,
					direction: InsertDirection.FROM_BUS_STOP
				});
				appendValid.push({
					how: InsertHow.APPEND,
					what: InsertWhat.BUS_STOP,
					where,
					direction: InsertDirection.TO_BUS_STOP
				});

				appendInvalid.push({
					how: InsertHow.APPEND,
					what: InsertWhat.USER_CHOSEN,
					where,
					direction: InsertDirection.TO_BUS_STOP
				});
				appendInvalid.push({
					how: InsertHow.APPEND,
					what: InsertWhat.BUS_STOP,
					where,
					direction: InsertDirection.FROM_BUS_STOP
				});
			}
			if (where != InsertWhere.AFTER_LAST_EVENT) {
				prependValid.push({
					how: InsertHow.PREPEND,
					what: InsertWhat.BOTH,
					where,
					direction: InsertDirection.FROM_BUS_STOP
				});
				prependValid.push({
					how: InsertHow.PREPEND,
					what: InsertWhat.BOTH,
					where,
					direction: InsertDirection.TO_BUS_STOP
				});
				prependValid.push({
					how: InsertHow.PREPEND,
					what: InsertWhat.USER_CHOSEN,
					where,
					direction: InsertDirection.TO_BUS_STOP
				});
				prependValid.push({
					how: InsertHow.PREPEND,
					what: InsertWhat.BUS_STOP,
					where,
					direction: InsertDirection.FROM_BUS_STOP
				});

				prependInvalid.push({
					how: InsertHow.PREPEND,
					what: InsertWhat.USER_CHOSEN,
					where,
					direction: InsertDirection.FROM_BUS_STOP
				});
				prependInvalid.push({
					how: InsertHow.PREPEND,
					what: InsertWhat.BUS_STOP,
					where,
					direction: InsertDirection.TO_BUS_STOP
				});
			}
		}
		for (let i = 0; i != appendValid.length; ++i) {
			expect(canCaseBeValid(appendValid[i])).toBe(true);
			expect(canCaseBeValid(prependValid[i])).toBe(true);
		} /*
		for (let i = 0; i != appendInvalid.length; ++i) {
			expect(canCaseBeValid(appendInvalid[i])).toBe(
				appendInvalid[i].where != InsertWhere.AFTER_LAST_EVENT
			);
			expect(canCaseBeValid(prependInvalid[i])).toBe(
				prependInvalid[i].where != InsertWhere.BEFORE_FIRST_EVENT
			);
		}*/
	});
});
