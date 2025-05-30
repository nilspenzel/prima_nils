<script lang="ts">
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
	import { InsertHow, InsertWhat } from '$lib/util/booking/insertionTypes.js';

	const { data } = $props();

	let time = $state(new Date(Date.now() + DAY * 3));
	let departure = $state(true);

	let map = $state<maplibregl.Map>();

	let events = $state(
		data.tours.flatMap((t) =>
			t.requests.flatMap((r) =>
				r.events.map((e) => {
					return { ...e, tourId: t.tourId, requestId: r.requestId };
				})
			)
		)
	);
	let companies = $state(
		data.companies
			.filter((c) => c.lat && c.lng)
			.map((c) => {
				return { ...c, lat: c.lat!, lng: c.lng!, companyId: c.id };
			})
	);

	let init = false;
	let start: { lat: number; lng: number } | undefined = $state(undefined);
	let destination: { lat: number; lng: number } | undefined = $state(undefined);

	function addTime(t: number) {
		time = new Date(time.getTime() + t);
	}

	function addMarkers(
		coordinates: {
			lat: number;
			lng: number;
			requestId?: number;
			tourId?: number;
			companyId?: number;
		}[],
		color: string,
		onDropNearCompany?: (start: number, company: number) => void
	) {
		return coordinates.map((coordinate, i) => {
			const el = document.createElement('div');
			el.className = 'marker-start';
			el.innerText = `${coordinate.requestId ? 'r' + coordinate.requestId + ' ' : ''}${coordinate.tourId ? 't' + coordinate.tourId + ' ' : ''}${coordinate.companyId ? 'c' + coordinate.companyId : ''}`;
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
						const dx = dropped.lng - company.lng!;
						const dy = dropped.lat - company.lat!;
						return Math.sqrt(dx * dx + dy * dy) < threshold;
					});

					if (foundIndex !== -1) {
						onDropNearCompany(i, foundIndex);
					}
					marker.setLngLat(coordinate);
				});
			}
			return marker;
		});
	}

	let vehicle: undefined | number = $state(undefined);
	let what: undefined | number = $state(undefined);
	let how: undefined | number = $state(undefined);
	let prevEventId: undefined | number = $state(undefined);
	let nextEventId: undefined | number = $state(undefined);

	$effect(() => {
		if (!map) return;
		addMarkers(companies, 'yellow');
		addMarkers(
			events.filter((e) => e.isPickup),
			'green'
		);
		addMarkers(
			events.filter((e) => !e.isPickup),
			'red'
		);
	});

	$effect(() => {
		if (start) {
			addMarkers([start], 'white');
		}
	});

	$effect(() => {
		if (destination) {
			addMarkers([destination], 'black');
		}
	});

	$effect(() => {
		if (map && !init) {
			map.on('contextmenu', (e) => {
				const { lat, lng } = e.lngLat;
				if (start) {
					if (!destination) {
						destination = { lat, lng };
					}
				} else {
					start = { lat, lng };
				}
			});
			init = true;
		}
	});
</script>

<div class="flex h-full w-screen">
	<div class="h-full w-1/2">
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
	<div class="h-full w-1/2 flex-col overflow-auto border-l border-gray-300 p-4">
		<div class="mt-4 flex gap-4">
			<Switch class="justify-self-end" bind:checked={departure} />
			<Label class="flex items-center gap-2">Time fixed at start</Label>
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
			<select bind:value={vehicle} class="rounded border border-gray-300 bg-white px-3 py-2">
				{#if vehicle === undefined}
					<option value={undefined} disabled selected>vehicleId</option>
				{/if}
				{#each data.companies.flatMap((c) => c.vehicles.map((v) => v.id)) as v}
					<option value={v}>{v}</option>
				{/each}
			</select>
			<select bind:value={how} class="rounded border border-gray-300 bg-white px-3 py-2">
				{#if how === undefined}
					<option value={undefined} disabled selected>InsertHow</option>
				{/if}
				<option value={InsertHow.NEW_TOUR}>NewTour</option>
				<option value={InsertHow.INSERT}>Insert</option>
				<option value={InsertHow.PREPEND}>Prepend</option>
				<option value={InsertHow.APPEND}>Append</option>
				<option value={InsertHow.CONNECT}>Connect</option>
			</select>
			<select bind:value={what} class="rounded border border-gray-300 bg-white px-3 py-2">
				{#if what === undefined}
					<option value={undefined} disabled selected>InsertWhat</option>
				{/if}
				<option value={InsertWhat.BOTH}>Both</option>
				<option value={InsertWhat.BUS_STOP}>BusStop</option>
				<option value={InsertWhat.USER_CHOSEN}>UserChosen</option>
			</select>
			<select bind:value={prevEventId} class="rounded border border-gray-300 bg-white px-3 py-2">
				<option disabled selected hidden>Select position</option>
				{#if prevEventId === undefined}
					<option value={undefined} disabled selected>PrevEventId</option>
				{/if}
				{#each data.tours.flatMap( (t) => t.requests.flatMap( (r) => r.events.map((e) => e.id) ) ) as event}
					<option value={event}>{event}</option>
				{/each}
			</select>
			<select bind:value={nextEventId} class="rounded border border-gray-300 bg-white px-3 py-2">
				<option disabled selected hidden>Select position</option>
				{#if nextEventId === undefined}
					<option value={undefined} disabled selected>NextEventId</option>
				{/if}
				{#each data.tours.flatMap( (t) => t.requests.flatMap( (r) => r.events.map((e) => e.id) ) ) as event}
					<option value={event}>{event}</option>
				{/each}
			</select>
			{#if start && destination}
				<form method="POST">
					<input type="hidden" value={start?.lat} name="startLat" />
					<input type="hidden" value={start?.lng} name="startLng" />
					<input type="hidden" value={destination?.lat} name="destinationLat" />
					<input type="hidden" value={destination?.lng} name="destinationLng" />
					<input type="hidden" value={time} name="time" />
					<input type="hidden" value={departure} name="startFixed" />
					<input type="hidden" value={vehicle} name="vehicle" />
					<input type="hidden" value={how} name="how" />
					<input type="hidden" value={what} name="what" />
					<input type="hidden" value={prevEventId} name="prev" />
					<input type="hidden" value={nextEventId} name="next" />
					<Button type="submit" name="intent">test booking</Button>
				</form>
			{/if}
		</div>
	</div>
</div>
