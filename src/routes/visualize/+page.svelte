<script lang="ts">
	import type { TourWithRequestsEvent } from '$lib/util/getToursTypes';
	import { format, differenceInMinutes, setHours, setMinutes } from 'date-fns';
	import {
		DateFormatter,
		fromDate,
		toCalendarDate,
		getLocalTimeZone,
		type DateValue
	} from '@internationalized/date';

	import CalendarIcon from 'lucide-svelte/icons/calendar';
	import { Calendar } from '$lib/shadcn/calendar';
	import * as Popover from '$lib/shadcn/popover';

	import { Button, buttonVariants } from '$lib/shadcn/button';
	import { ChevronRight, ChevronLeft } from 'lucide-svelte';
	import { LOCALE, TZ } from '$lib/constants.js';

	import { goto } from '$app/navigation';
	import { HOUR, MINUTE } from '$lib/util/time';

	const { data } = $props();
	let value = $state<DateValue>(toCalendarDate(fromDate(data.utcDate!, TZ)));
	const date = $derived(new Date(value.year, value.month - 1, value.day, 2));
	const scheduleStart = $derived(date.getTime());
	const scheduleEnd = $derived(date.getTime() + HOUR * 24);
	const totalMinutes = $derived((scheduleEnd - scheduleStart) / MINUTE);
	function getOffsetMinutes(ts: number) {
		return Math.max(0, ts - scheduleStart) / MINUTE;
	}
	const tourColorMaps = new Map();
	const colorPalette = [
		'bg-blue-200',
		'bg-green-200',
		'bg-yellow-200',
		'bg-purple-200',
		'bg-pink-200',
		'bg-indigo-200',
		'bg-red-200',
		'bg-teal-200'
	];

	function getColor(requestId: number, tourIndex: number) {
		if (!tourColorMaps.has(tourIndex)) {
			tourColorMaps.set(tourIndex, { colorMap: new Map(), colorIndex: 0 });
		}

		const tourData = tourColorMaps.get(tourIndex);
		if (!tourData.colorMap.has(requestId)) {
			tourData.colorMap.set(requestId, colorPalette[tourData.colorIndex % colorPalette.length]);
			tourData.colorIndex++;
		}
		return tourData.colorMap.get(requestId);
	}
	function formatTime(ts: number) {
		return format(new Date(ts), 'HH:mm');
	}
	const laneHeight = 100;
	function getTopByTour(tourIndex: number) {
		return `${tourIndex * laneHeight}px`;
	}
	function getHorizontalStyles(event: TourWithRequestsEvent) {
		const leftPercent = (getOffsetMinutes(event.scheduledTimeStart) / totalMinutes) * 100;
		const widthPercent =
			(differenceInMinutes(event.scheduledTimeEnd, event.scheduledTimeStart) / totalMinutes) * 100;
		const dotLeftPercent = (getOffsetMinutes(event.communicatedTime) / totalMinutes) * 100;
		return {
			left: `${leftPercent}%`,
			width: `${widthPercent}%`,
			dotLeft: `${dotLeftPercent}%`
		};
	}

	function generateHourTimestamps() {
		const timestamps = [];
		const startHour = 2;
		const endHour = 24;
		for (let hour = startHour; hour <= endHour; hour++) {
			const timestamp = setHours(setMinutes(date, 0), hour);
			const offsetMinutes = getOffsetMinutes(timestamp.getTime());
			const leftPercent = (offsetMinutes / totalMinutes) * 100;
			timestamps.push({
				time: format(timestamp, 'HH:mm'),
				left: `${leftPercent}%`
			});
		}
		return timestamps;
	}

	const df = new DateFormatter(LOCALE, { dateStyle: 'long' });

	$effect(() => {
		const offset = value.toDate('UTC').getTimezoneOffset();
		goto(`/visualize?offset=${offset}&date=${value.toDate('UTC').toISOString().slice(0, 10)}`);
	});

	const tours = $derived(
		data.tours.filter((t) => t.startTime >= scheduleStart && t.endTime <= scheduleEnd)
	);
</script>

<div class="h-screen w-screen overflow-auto bg-gray-50 p-6">
	<h1 class="mb-4 text-2xl font-semibold text-gray-800">Tour Schedule Timeline</h1>
	<div class="flex gap-4 p-6 font-semibold leading-none tracking-tight">
		<div class="flex gap-1">
			<Button variant="outline" size="icon" onclick={() => (value = value.add({ days: -1 }))}>
				<ChevronLeft class="size-4" />
			</Button>
			<Popover.Root>
				<Popover.Trigger
					class={buttonVariants({
						variant: 'outline',
						class: 'w-fit justify-start text-left font-normal'
					})}
				>
					<CalendarIcon class="mr-2 size-4" />
					{df.format(value.toDate(getLocalTimeZone()))}
				</Popover.Trigger>
				<Popover.Content class="w-auto p-0">
					<Calendar type="single" bind:value locale={LOCALE} />
				</Popover.Content>
			</Popover.Root>
			<Button variant="outline" size="icon" onclick={() => (value = value.add({ days: 1 }))}>
				<ChevronRight class="size-4" />
			</Button>
		</div>
	</div>
	<div class="relative mb-2" style="min-width: 1000px; height: 20px;">
		{#each generateHourTimestamps() as timestamp}
			<div class="absolute text-xs font-medium text-gray-600" style="left: {timestamp.left};">
				{timestamp.time}
			</div>
		{/each}
	</div>
	<div
		class="timeline-grid relative border-t border-gray-300"
		style="height: {tours.length * laneHeight}px; min-width: 1000px;"
	>
		{#each tours as tour, tourIndex}
			{#each tour.requests as request}
				{#each request.events as event}
					<div
						class={`absolute rounded-lg border border-gray-300 p-2 text-sm text-gray-800 shadow ${getColor(request.requestId, tourIndex)}`}
						style={`top: ${getTopByTour(tourIndex)}; left: ${getHorizontalStyles(event).left}; width: ${getHorizontalStyles(event).width}; height: 60px;`}
						title={`Request ${request.requestId}`}
					>
						<div class="font-medium">
							{formatTime(event.scheduledTimeStart)} – {formatTime(event.scheduledTimeEnd)}
						</div>
						<div class="text-xs">Event: {event.id}</div>
					</div>
					<div
						class="absolute h-4 w-4 rounded-full border-2 border-white bg-red-600 shadow"
						style={`top: calc(${getTopByTour(tourIndex)} + 30px); left: ${getHorizontalStyles(event).dotLeft};`}
						title={`Communicated at ${formatTime(event.communicatedTime)}`}
					></div>
				{/each}
			{/each}
		{/each}
	</div>
</div>
