<script lang="ts">
	import maplibregl from 'maplibre-gl';
	import { getStyle } from '$lib/map/style.js';
	import Map from '$lib/map/Map.svelte';
	import { PUBLIC_MOTIS_URL } from '$env/static/public';
	import GeoJSON from '$lib/map/GeoJSON.svelte';
	import Layer from '$lib/map/Layer.svelte';

    const { data } = $props();

	let map = $state<maplibregl.Map>();

    $effect(() => {
	    if (map) {
            console.log("mapyes",data.coordinates.length)
	    	for (let bs of data.coordinates) {
	    		const marker = new maplibregl.Marker({
	    			draggable: false,
	    			color: 'blue'
	    		}).setLngLat({
	    			lat: bs.lat!,
	    			lng: bs.lng!
	    		}).addTo(map);
	    	}
	    }
	});
</script>

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
><GeoJSON id="route" data={data.areas as GeoJSON.GeoJSON}>
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
