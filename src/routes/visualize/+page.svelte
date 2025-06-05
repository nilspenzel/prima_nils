<script lang="ts">
	import type { TourWithRequestsEvent } from '$lib/util/getToursTypes';
	import { format, differenceInMinutes, setHours, setMinutes } from 'date-fns';
	const { data } = $props();
	const now = new Date();
	const scheduleStart = setHours(setMinutes(now, 0), 2).getTime();
	const scheduleEnd = setHours(setMinutes(now, 0), 24).getTime();
	const totalMinutes = differenceInMinutes(scheduleEnd, scheduleStart);
	function getOffsetMinutes(ts: number) {
		return Math.max(0, differenceInMinutes(ts, scheduleStart));
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
			const timestamp = setHours(setMinutes(now, 0), hour);
			const offsetMinutes = getOffsetMinutes(timestamp.getTime());
			const leftPercent = (offsetMinutes / totalMinutes) * 100;
			timestamps.push({
				time: format(timestamp, 'HH:mm'),
				left: `${leftPercent}%`
			});
		}
		return timestamps;
	}
</script>

<div class="h-screen w-screen overflow-auto bg-gray-50 p-6">
	<h1 class="mb-4 text-2xl font-semibold text-gray-800">Tour Schedule Timeline</h1>
	<div class="relative mb-2" style="min-width: 1000px; height: 20px;">
		{#each generateHourTimestamps() as timestamp}
			<div class="absolute text-xs font-medium text-gray-600" style="left: {timestamp.left};">
				{timestamp.time}
			</div>
		{/each}
	</div>
	<div
		class="timeline-grid relative border-t border-gray-300"
		style="height: {data.tours.length * laneHeight}px; min-width: 1000px;"
	>
		{#each data.tours as tour, tourIndex}
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
