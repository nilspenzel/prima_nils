import { serviceName } from '$lib/constants';
import { groupBy } from '$lib/util/groupBy';
import { evaluateNewToursString } from '$lib/util/tracingNames';
import type { PageServerLoad } from '../$types';
import type { JaegerNode, JaegerResponse, JaegerSpan } from './jaegerTypes';

const childOfKey = 'CHILD_OF';

export const load: PageServerLoad = async () => {
	const res = await fetch(`http://localhost:16686/api/traces?service=${serviceName}&limit=500000`);
	if (!res.ok) {
		throw new Error(`Failed to fetch Jaeger traces: ${res.statusText}`);
	}
	const d: JaegerResponse = await res.json();
	if (!d.data || d.data.length === 0) {
		console.log('no data received.');
		return { traces: [] };
	}
	const spans = d.data.flatMap((d) => d.spans);
	const whitelistRootSpans = spans.filter((s) =>
		s.tags.some((t) => t.key === 'http.url' && t.value === 'http://localhost/api/whitelist')
	);
	const bookingRootSpans = spans.filter((s) =>
		s.tags.some((t) => t.key === 'http.url' && t.value === 'http://localhost/api/bookingApi')
	);
	const whitelist = getTrees(whitelistRootSpans, spans).flatMap((w) => w.children);
	const booking = getTrees(bookingRootSpans, spans);
	return { whitelist, booking };
};

function getChildren(
	spans: JaegerSpan[],
	span: JaegerSpan
): (JaegerSpan & { children: JaegerNode[] })[] {
	return spans
		.filter((s) => s.references.some((r) => r.refType === childOfKey && r.spanID === span.spanID))
		.map((child) => ({
			...child,
			children: getChildren(spans, child)
		}));
}

function isInternal(span: JaegerSpan) {
	return span.tags.some((t) => t.key === 'span.kind' && t.value === 'internal');
}

function hasParent(span: JaegerSpan) {
	return (
		span.logs.some((l) => l.fields.some((f) => f.key === childOfKey)) ||
		span.references.some((r) => r.refType === childOfKey)
	);
}

function getTrees(chosenSpans: JaegerSpan[], allSpans: JaegerSpan[]) {
	const spansWithParents = allSpans.filter((s) =>
		chosenSpans.some((sl) => sl.traceID === s.traceID)
	);
	const spansByTrace = groupBy(
		spansWithParents,
		(s) => s.traceID,
		(s) => {
			return { ...s, children: new Array<string>() };
		}
	);
	const traceTrees = new Array<JaegerNode>();
	for (const [traceId, spans] of spansByTrace) {
		const firstSpanWithoutParentIdx = spans.findIndex((s) => !isInternal(s) && !hasParent(s));
		const lastSpanWithoutParentIdx = spans.findLastIndex((s) => !isInternal(s) && !hasParent(s));
		if (firstSpanWithoutParentIdx !== lastSpanWithoutParentIdx) {
			console.log('More than one span without parent in trace.', { traceId });
			throw new Error();
		}
		const spanWithNoParent = spans[firstSpanWithoutParentIdx];
		traceTrees.push({ ...spanWithNoParent, children: getChildren(spans, spanWithNoParent) });
	}
	return traceTrees;
}
