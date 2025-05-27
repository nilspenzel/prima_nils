<script lang="ts">
	import { v4 as uuidv4 } from 'uuid';
	import maplibregl from 'maplibre-gl';
	import { getStyle } from '$lib/map/style.js';
	import Map from '$lib/map/Map.svelte';
	import GeoJSON from '$lib/map/GeoJSON.svelte';
	import Layer from '$lib/map/Layer.svelte';
	import { PUBLIC_MOTIS_URL } from '$env/static/public';
	import { Button } from '$lib/shadcn/button/index.js';
	import { DAY, HOUR, MINUTE } from '$lib/util/time.js';
	import Switch from '$lib/shadcn/switch/switch.svelte';
	import { Label } from '$lib/shadcn/label/index.js';
	import type { Coordinates } from '$lib/util/Coordinates.js';
	import type { Condition } from '$lib/server/booking/tests/generatedTests/testJsons.js';

	const { data } = $props();

	let time = $state(new Date(Date.now() + DAY * 3));
	let addCompany = $state(true);
	let departure = $state(true);

	let map = $state<maplibregl.Map>();

	let starts: { lat: number; lng: number }[] = $state([]);
	let destinations: { lat: number; lng: number }[] = $state([]);
	let companies: { lat: number; lng: number }[] = $state([]);

	let init = false;
	let startMarkers: maplibregl.Marker[] = [];
	let destinationMarkers: maplibregl.Marker[] = [];
	let companyMarkers: maplibregl.Marker[] = [];
	let times: number[] = [];
	let isDepartures: boolean[] = [];

	function addTime(t: number) {
		time = new Date(time.getTime() + t);
	}

	function addMarkers(
		markers: maplibregl.Marker[],
		coordinates: { lat: number; lng: number }[],
		color: string,
		onDropNearCompany?: (start: number, company: number) => void
	) {
		markers.forEach((marker) => marker.remove());
		return coordinates.map((coordinate, i) => {
			const el = document.createElement('div');
			el.className = 'marker-start';
			el.innerText = `${i + 1}`;
			Object.assign(el.style, {
				backgroundColor: color,
				color: 'black',
				width: '24px',
				height: '24px',
				borderRadius: '50%',
				textAlign: 'center',
				lineHeight: '24px',
				fontWeight: 'bold',
				fontSize: '12px'
			});
			const marker = new maplibregl.Marker({
				element: el,
				draggable: onDropNearCompany !== undefined
			})
				.setLngLat([coordinate.lng, coordinate.lat])
				.addTo(map!);
			if (onDropNearCompany !== undefined) {
				marker.on('dragend', () => {
					const dropped = marker.getLngLat();

					const threshold = 0.002;
					const foundIndex = companies.findIndex((company) => {
						const dx = dropped.lng - company.lng;
						const dy = dropped.lat - company.lat;
						return Math.sqrt(dx * dx + dy * dy) < threshold;
					});

					if (foundIndex !== -1 && destinations.length !== i) {
						onDropNearCompany(i, foundIndex);
					}
					marker.setLngLat(coordinate);
				});
			}
			return marker;
		});
	}

	let currentTestEntity = $state(undefined);
	let expectedRequestCount = $state('0');
	let expectedTourCount = $state('0');
	let expectedStartPosition = $state('0');
	let expectedDestinationPosition = $state('0');
	let afterRequest = $state('0');
	let selectedRequest = $state(undefined);

	let conditions: Condition[] = $state([]);
	let uuid = '1';
	function addCondition() {
		uuid = uuidv4();
		conditions.push({
			evalAfterStep: parseInt(afterRequest),
			entity: currentTestEntity!,
			tourCount: parseInt(expectedTourCount),
			requestCount: parseInt(expectedRequestCount),
			startIdxInTimeSortedTour: parseInt(expectedStartPosition),
			destinationIdxInTimeSortedTour: parseInt(expectedDestinationPosition),
			start: selectedRequest ? starts[selectedRequest] : undefined,
			destination: selectedRequest ? destinations[selectedRequest] : undefined
		});
	}

	function assignRequestToCompany(startIdx: number, start: Coordinates, company: Coordinates) {
		uuid = uuidv4();
		conditions.push({
			evalAfterStep: startIdx,
			entity: 'requestCompanyMatch',
			start,
			destination: destinations[startIdx],
			company
		});
	}

	$effect(() => {
		if (!map) return;
		companyMarkers = addMarkers(companyMarkers, companies, 'yellow');
		startMarkers = addMarkers(startMarkers, starts, 'green', (s, c) =>
			assignRequestToCompany(s, starts[s], companies[c])
		);
		destinationMarkers = addMarkers(destinationMarkers, destinations, 'red');
	});

	$effect(() => {
		if (map && !init) {
			map.on('contextmenu', (e) => {
				const { lat, lng } = e.lngLat;
				if (addCompany) {
					companies.push({ lat, lng });
				} else {
					if (starts.length === destinations.length) {
						starts.push({ lat, lng });
					} else {
						destinations.push({ lat, lng });
						times.push(time.getTime());
						isDepartures.push(departure);
					}
				}
			});
			init = true;
		}
	});

	let json: string = $derived(
		JSON.stringify(
			{
				conditions,
				process: { starts, destinations, times, isDepartures, companies },
				uuid
			},
			null,
			'\t'
		).replace(/"([^"]+)"(?=\s*:)/g, '$1')
	);
</script>

<div class="flex h-full w-screen">
	<div class="h-full w-2/3">
		<Map
			bind:map
			transformRequest={(url, _resourceType) => {
				if (url.startsWith('/')) {
					return { url: `${PUBLIC_MOTIS_URL}/tiles${url}` };
				}
			}}
			center={[14.5771254, 51.5269344]}
			zoom={10}
			style={getStyle('light', 0)}
			class="h-full w-full rounded-lg border shadow"
			attribution={"&copy; <a href='http://www.openstreetmap.org/copyright' target='_blank'>OpenStreetMap</a>"}
		>
			<GeoJSON id="route" data={data.areas as GeoJSON.GeoJSON}>
				<Layer
					id="areas"
					type="fill"
					layout={{}}
					filter={['literal', true]}
					paint={{
						'fill-color': '#088',
						'fill-opacity': 0.4,
						'fill-outline-color': '#000'
					}}
				/>
				<Layer
					id="areas-outline"
					type="line"
					layout={{}}
					filter={['literal', true]}
					paint={{
						'line-color': '#000',
						'line-width': 2
					}}
				/>
				<Layer
					id="areas-labels"
					type="symbol"
					layout={{
						'symbol-placement': 'point',
						'text-field': ['get', 'name'],
						'text-font': ['Noto Sans Display Regular'],
						'text-size': 16
					}}
					filter={['literal', true]}
					paint={{
						'text-halo-width': 12,
						'text-halo-color': '#fff',
						'text-color': '#f00'
					}}
				/>
			</GeoJSON>
		</Map>
	</div>
	<div class="h-full w-1/3 flex-col overflow-auto border-l border-gray-300 p-4">
		<div class="mt-4 flex gap-4">
			<Switch class="justify-self-end" bind:checked={addCompany} />
			<Label class="flex items-center gap-2">Add Company</Label>

			<Switch class="justify-self-end" bind:checked={departure} />
			<Label class="flex items-center gap-2">Time fixed at start</Label>

			<form method="POST">
				<input type="hidden" name="value" value={json} />
				<button type="submit" name="intent">Write to File</button>
			</form>
		</div>

		<div class="mt-4 flex gap-4">
			{time.toISOString().slice(0, time.toISOString().lastIndexOf('.')).replaceAll('T', ' ')}
			<Button onclick={() => addTime(MINUTE)}>+1m</Button>
			<Button onclick={() => addTime(5 * MINUTE)}>+5m</Button>
			<Button onclick={() => addTime(HOUR)}>+1h</Button>
			<Button onclick={() => addTime(-MINUTE)}>-1m</Button>
			<Button onclick={() => addTime(-5 * MINUTE)}>-5m</Button>
			<Button onclick={() => addTime(-HOUR)}>-1h</Button>
		</div>

		<div class="mt-4 flex gap-4">
			<select bind:value={afterRequest} class="rounded border border-gray-300 bg-white px-3 py-2">
				<option value="-1">After Request #</option>
				{#each destinations.entries() as [i, _]}
					<option value={i}>{i + 1}</option>
				{/each}
			</select>

			<select
				bind:value={currentTestEntity}
				class="rounded border border-gray-300 bg-white px-3 py-2"
			>
				<option value="" disabled selected hidden>Select test type</option>
				<option value="requestCount">requestCount</option>
				<option value="tourCount">tourCount</option>
				<option value="startPosition">startPosition</option>
				<option value="destinationPosition">destinationPosition</option>
			</select>

			{#if currentTestEntity === 'requestCount'}
				<select
					bind:value={expectedRequestCount}
					class="rounded border border-gray-300 bg-white px-3 py-2"
				>
					<option value="0" selected>0</option>
					{#each destinations.entries() as [i, _]}
						<option value={(i + 1).toString()}>{i + 1}</option>
					{/each}
				</select>
			{/if}

			{#if currentTestEntity === 'tourCount'}
				<select
					bind:value={expectedTourCount}
					class="rounded border border-gray-300 bg-white px-3 py-2"
				>
					<option value="0" selected>0</option>
					{#each destinations.entries() as [i, _]}
						<option value={(i + 1).toString()}>{i + 1}</option>
					{/each}
				</select>
			{/if}

			{#if currentTestEntity === 'startPosition' || currentTestEntity === 'destinationPosition'}
				<select
					bind:value={selectedRequest}
					class="rounded border border-gray-300 bg-white px-3 py-2"
				>
					{#each destinations.entries() as [i, _]}
						<option value={(i + 1).toString()}>{i + 1}</option>
					{/each}
				</select>
			{/if}

			{#if currentTestEntity === 'startPosition'}
				<select
					bind:value={expectedStartPosition}
					class="rounded border border-gray-300 bg-white px-3 py-2"
				>
					<option value="0" selected>0</option>
					{#each destinations.entries() as [i, _]}
						<option value={(i + 1).toString()}>{i + 1}</option>
					{/each}
				</select>
			{/if}

			{#if currentTestEntity === 'destinationPosition'}
				<select
					bind:value={expectedDestinationPosition}
					class="rounded border border-gray-300 bg-white px-3 py-2"
				>
					<option value="0" selected>0</option>
					{#each destinations.entries() as [i, _]}
						<option value={(i + 1).toString()}>{i + 1}</option>
					{/each}
				</select>
			{/if}

			{#if currentTestEntity !== '' && parseInt(afterRequest) !== -1}
				<Button onclick={addCondition}>Add Condition</Button>
			{/if}
		</div>

		<pre>
			{json}
		</pre>
	</div>
</div>
