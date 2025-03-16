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
	import BookingDialog from './bookingDialog.svelte';

	const { data, form } = $props();

	let map = $state<maplibregl.Map>();
	let info = $derived(form?.info);
	let booking1 = $derived(form?.booking1);

	let init = false;
	let startMarker: maplibregl.Marker | null = null;
	let targetMarker: maplibregl.Marker | null = null;
	let booking1Marker: maplibregl.Marker | null = null;

	let blacklistResponse: undefined | {
	    time: string;
	    blr: boolean;
	}[] = $state(undefined);
	let whitelistResponse: undefined | (undefined | { requestedTime: string, pickupTime?: string; dropoffTime?: string })[] = $state(undefined);


	let expectedStart: string | undefined = $state(undefined)
    let expectedTarget: string | undefined = $state(undefined)
    let start: string | undefined = $state(undefined)
    let target: string | undefined = $state(undefined)
	$effect(() => {
		if (map && info != undefined) {
			startMarker = new maplibregl.Marker({ draggable: false, color: 'green' }).setLngLat([info.start.lng, info.start.lat]).addTo(map);
			startMarker.getElement().addEventListener('click', () => {
				blacklistResponse = info.directTimesBlack;
				whitelistResponse = info.directTimesWhite;
			});

			targetMarker = new maplibregl.Marker({ draggable: false, color: 'red' });
			targetMarker.setLngLat([info.target.lng, info.target.lat]).addTo(map);

			if(booking1){
				booking1Marker = new maplibregl.Marker({ draggable: true, color: 'orange' }).setLngLat([booking1.start.lng, booking1.start.lat]).addTo(map);
				booking1Marker.getElement().addEventListener('click', () => {
					expectedStart = booking1.startTime;
        			expectedTarget = booking1.targetTime;
        			start = undefined;
        			target = undefined;
				});
				booking1Marker = new maplibregl.Marker({ draggable: false, color: 'purple' }).setLngLat([booking1.target.lng, booking1.target.lat]).addTo(map);
			}

			for (let bs of info.startBusStops) {
				const marker = new maplibregl.Marker({
					draggable: false,
					color: !bs.responses.some((r) => r.blr)
						? 'blue'
						: bs.wlr != undefined && bs.wlr.some((r) => r)
							? 'yellow'
							: 'pink'
				}).setLngLat({
					lat: bs.lat!,
					lng: bs.lng!
				}).addTo(map);

				marker.getElement().addEventListener('click', () => {
					blacklistResponse = bs.responses;
					whitelistResponse = bs.wlr;
				});
			}

			for (let bs of info.targetBusStops) {
				const marker = new maplibregl.Marker({
					draggable: false,
					color: !bs.responses.some((r) => r.blr)
						? 'white'
						: bs.wlr != undefined && bs.wlr.some((r) => r)
							? 'grey'
							: 'black'
				}).setLngLat({
					lat: bs.lat!,
					lng: bs.lng!
				}).addTo(map);
			
				marker.getElement().addEventListener('click', () => {
					blacklistResponse = bs.responses;
					whitelistResponse = bs.wlr;
				});
			}
			init = true;
		}
	});
</script>

<MarkerDialog bind:blacklistResponse bind:whitelistResponse></MarkerDialog>
<BookingDialog bind:expectedStart bind:start bind:expectedTarget bind:target></BookingDialog>
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
