import type { Column } from '$lib/ui/tableData';
import { expandTree, type JaegerNode } from './jaegerTypes';

export const cols: Column<JaegerNode>[] = [
	{
		text: ['name'],
		sort: (a: JaegerNode, b: JaegerNode) => (a.operationName < b.operationName ? 1 : -1),
		toTableEntry: (r: JaegerNode) => r.operationName
	},
	jaegerTagColumn('startFixedDirect'),
	jaegerTagColumn('start'),
	jaegerTagColumn('target')
];

export const cols2: Column<JaegerNode>[] = [
	{
		text: ['name'],
		sort: (a: JaegerNode, b: JaegerNode) => a.operationName.localeCompare(b.operationName),
		toTableEntry: (r: JaegerNode) => r.operationName
	},
	jaegerTagColumn('how'),
	jaegerTagColumn('what'),
	jaegerTagColumn('direction'),
	jaegerTagColumn('prev'),
	jaegerTagColumn('next'),
	jaegerTagColumn('busStopIdx'),
	jaegerTagColumn('startFixed')
];

export function getCols3(): Column<string>[] {
	return [{
		text: ['key'],
		sort: undefined,
		toTableEntry: ((e: string) => e)
	}];
}

function getLogByKey(j: JaegerNode, key: string) {
	return j.logs.find((l) => l.fields.some((f) => f.key === key))?.fields.find((f) => f.key === key)
		?.value;
}

function sortJaegerNodeByTag(a: JaegerNode, b: JaegerNode, key: string) {
	const tagA = getLogByKey(a, key);
	const tagB = getLogByKey(b, key);
	if (tagA === undefined && tagB === undefined) {
		return 0;
	}
	if (tagA === undefined) {
		return -1;
	}
	if (tagB === undefined) {
		return 1;
	}
	return String(tagA).localeCompare(String(tagB));
}

export function jaegerTagColumn(key: string) {
	return {
		text: [key],
		sort: (a: JaegerNode, b: JaegerNode) => sortJaegerNodeByTag(a, b, key),
		toTableEntry: (r: JaegerNode) => String(getLogByKey(r, key))
	};
}
