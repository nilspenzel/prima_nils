<script lang="ts">
	import maplibregl from 'maplibre-gl';
	import { Card } from '$lib/shadcn/card';
	import Button from '$lib/shadcn/button/button.svelte';
	import Control from '$lib/map/Control.svelte';
	import { getStyle } from '$lib/map/style.js';
	import Map from '$lib/map/Map.svelte';
	import GeoJSON from '$lib/map/GeoJSON.svelte';
	import { enhance } from '$app/forms';
	import Layer from '$lib/map/Layer.svelte';
	import { PUBLIC_MOTIS_URL } from '$env/static/public';
	import MarkerDialog from './markerDialog.svelte';

	const { data, form } = $props();

	let map = $state<maplibregl.Map>();
	let info = $derived(form?.info);

	let init = false;
	let startMarker: maplibregl.Marker | null = null;
	let targetMarker: maplibregl.Marker | null = null;

	let blacklistResponse = $state(undefined);
	let whitelistResponse = $state(undefined);
	$effect(() => {
		if (map && info != undefined) {
			startMarker = new maplibregl.Marker({ draggable: false, color: 'green' }).setLngLat([info.start.lng, info.start.lat]).addTo(map);
			startMarker.b = info.directTimesBlack;
			startMarker.w = info.directTimesWhite;
			startMarker.getElement().addEventListener('click', () => {
				blacklistResponse = startMarker!.b;
				whitelistResponse = startMarker!.w;
			});

			targetMarker = new maplibregl.Marker({ draggable: false, color: 'red' });
			targetMarker.setLngLat([info.target.lng, info.target.lat]).addTo(map);

			for (let bs of info.startBusStops) {
				const marker = new maplibregl.Marker({
					draggable: false,
					color: !bs.responses.some((r) => r.blr)
						? 'blue'
						: bs.wlr != undefined && bs.wlr.some((r) => r)
							? 'yellow'
							: 'white'
				}).setLngLat({
					lat: bs.lat!,
					lng: bs.lng!
				}).addTo(map);
				marker.b = bs.responses;
				marker.w = bs.wlr;

				marker.getElement().addEventListener('click', () => {
					blacklistResponse = marker.b;
					whitelistResponse = marker.w;
				});
			}

			for (let bs of info.targetBusStops) {
				new maplibregl.Marker({ draggable: false, color: 'orange' })
					.setLngLat({
						lat: bs.lat!,
						lng: bs.lng!
					})
					.addTo(map);
			}
			init = true;
		}
	});
</script>

<MarkerDialog bind:blacklistResponse bind:whitelistResponse></MarkerDialog>
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
	<Control position="bottom-left">
		<Card>
			<div class="flex w-full flex-col">
				<div class="flex flex-row space-x-4 rounded p-4 shadow-md">
					<form method="post" use:enhance>
						<input type="text" name="logs" />
						<Button type="submit">Suchen</Button>
					</form>
				</div>
			</div>
		</Card>
	</Control>

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
