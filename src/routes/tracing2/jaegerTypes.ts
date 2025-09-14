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
	node: JaegerNode,
	filters: { key: string; value: string | undefined }[],
	startBusStops: number[],
	targetBusStops: number[],
	fulfilledFilters: Set<number> = new Set(),
	fulfilledStart: boolean = false,
	fulfilledTarget: boolean = false,
	ret: JaegerNode[] = []
): JaegerNode[] {
  	const localFulfilled = new Set(fulfilledFilters);
	filters.forEach((f, idx) => {
		if (!localFulfilled.has(idx)) {
			if (String(f.value) === 'undefined') {
				localFulfilled.add(idx);
				return;
			}
			if (
				node.logs.some((l) =>
					l.fields.some((field) => field.key === f.key && String(field.value) === String(f.value))
				)
			) {
				localFulfilled.add(idx);
			}
		}
	});
	const startFulfilledHere =
		fulfilledStart ||
		startBusStops.length === 0 ||
		node.logs.some((l) =>
			l.fields.some((f) => f.key === 'busStopIdx' && startBusStops.includes(Number(f.value)))
		);
	const targetFulfilledHere =
		fulfilledTarget ||
		targetBusStops.length === 0 ||
		node.logs.some((l) =>
			l.fields.some((f) => f.key === 'busStopIdx' && targetBusStops.includes(Number(f.value)))
		);
	if (localFulfilled.size === filters.length && startFulfilledHere && targetFulfilledHere) {
		ret.push(node);
	} else {
		node.children.forEach((child) => {
			filterTree(
				child,
				filters,
				startBusStops,
				targetBusStops,
				new Set(localFulfilled),
				startFulfilledHere,
				targetFulfilledHere,
				ret
			);
		});
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

function flattenTree(node: JaegerNode): JaegerNode[] {
  let result: JaegerNode[] = [node];

  if (node.children && node.children.length > 0) {
    for (const child of node.children) {
      result = result.concat(flattenTree(child));
    }
  }
  return result;
}

export function flattenForest(nodes: JaegerNode[]): JaegerNode[] {
  return nodes.flatMap(flattenTree).filter((n) => nodes.some((s) => n.spanID === s.spanID));
}