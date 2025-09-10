import type { BusStop } from '$lib/server/booking/BusStop';
import type { Coordinates } from '$lib/util/Coordinates';

export type JaegerTag = {
	key: string;
	type: string;
	value: string | number | boolean;
};

export type JaegerLog = {
	timestamp: number;
	fields: JaegerTag[];
};

export type JaegerSpan = {
	spanID: string;
	traceID: string;
	operationName: string;
	process: { serviceName: string };
	tags: JaegerTag[];
	logs: JaegerLog[];
	references: Reference[];
};

export type JaegerTrace = {
	traceID: string;
	spans: JaegerSpan[];
};

export type JaegerResponse = {
	data: JaegerTrace[];
	total?: number;
	limit?: number;
	errors?: string[];
};

export type Reference = {
	refType: string;
	spanID: string;
};

export type JaegerNode = JaegerSpan & {
	children: JaegerNode[];
	startCoordinates?: Coordinates;
	targetCoordinates?: Coordinates;
	startBusStops?: Coordinates[];
	targetBusStops?: Coordinates[];
};

export function filterTree(
	tree: JaegerNode,
	filters: { key: string; value: string | undefined }[],
	startBusStops: number[],
	targetBusStops: number[],
	ret: JaegerNode[]
): JaegerNode[] {
	const relevantFilters = filters.filter(
		(f) => f.value !== String(undefined) && f.value !== undefined
	);
	const fulfilledFilterIdxs = relevantFilters
		.map((filter, idx) =>
			!tree.logs.some((l) =>
				l.fields.some((field) => filter.key === field.key && filter.value !== String(field.value))
			)
				? idx
				: undefined
		)
		.filter((i) => i !== undefined);
	const startBusStopsFulfilled =
		startBusStops.length === 0 ||
		tree.logs.some((l) =>
			l.fields.some(
				(f) => f.key === 'busStopIdx' && startBusStops.some((b) => String(f.value) === String(b))
			)
		);
	const targetBusStopsFulfilled =
		targetBusStops.length === 0 ||
		tree.logs.some((l) =>
			l.fields.some(
				(f) => f.key === 'busStopIdx' && targetBusStops.some((b) => String(f.value) === String(b))
			)
		);
	const requiredChildFilters = relevantFilters
		.filter((f, idx) => (!fulfilledFilterIdxs.some((i) => i === idx) ? f : undefined))
		.filter((f) => f !== undefined);
	if (
		fulfilledFilterIdxs.length === relevantFilters.length &&
		startBusStopsFulfilled &&
		targetBusStopsFulfilled
	) {
		ret.push(tree);
	} else {
		tree.children.forEach((c) =>
			filterTree(c, requiredChildFilters, startBusStopsFulfilled ? [] : startBusStops, targetBusStopsFulfilled ? [] : targetBusStops, ret)
		);
	}
	return ret;
}

export function expandTree(tree: JaegerNode): JaegerNode[] {
	const spans: JaegerNode[] = [];
	const stack: JaegerNode[] = [tree];

	while (stack.length > 0) {
		const node = stack.pop()!;
		spans.push(node);
		for (let i = node.children.length - 1; i >= 0; i--) {
			stack.push(node.children[i]);
		}
	}

	return spans;
}

export function addCoordinates(n: JaegerNode) {
	const start = n.logs
		.find((l) => l.fields.some((f) => f.key === 'start'))
		?.fields.find((f) => f.key === 'start')?.value;
	const target = n.logs
		.find((l) => l.fields.some((f) => f.key === 'target'))
		?.fields.find((f) => f.key === 'target')?.value;
	const startBusStops = n.logs
		.find((l) => l.fields.some((f) => f.key === 'startBusStops'))
		?.fields.find((f) => f.key === 'startBusStops')?.value;
	const targetBusStops = n.logs
		.find((l) => l.fields.some((f) => f.key === 'targetBusStops'))
		?.fields.find((f) => f.key === 'targetBusStops')?.value;
	console.log({ abc: start }, { abc2: target }, { abc1: startBusStops }, { abc3: targetBusStops });
	const ret: JaegerNode = {
		...n,
		startCoordinates: undefined,
		targetCoordinates: undefined,
		startBusStops: [],
		targetBusStops: []
	};
	if (typeof start === 'string') {
		ret.startCoordinates = JSON.parse(start) as Coordinates;
	}
	if (typeof target === 'string') {
		ret.targetCoordinates = JSON.parse(target) as Coordinates;
	}
	if (typeof startBusStops === 'string') {
		ret.startBusStops = (JSON.parse(startBusStops) as BusStop[]).map((b) => {
			return { lat: b.lat, lng: b.lng };
		});
	}
	if (typeof targetBusStops === 'string') {
		ret.targetBusStops = (JSON.parse(targetBusStops) as BusStop[]).map((b) => {
			return { lat: b.lat, lng: b.lng };
		});
	}
	return ret;
}
