<script lang="ts">
	import maplibregl from 'maplibre-gl';
	import Map from '$lib/map/Map.svelte';
	import { env } from '$env/dynamic/public';

	const { data } = $props(); // $lib/map/style.ts
	import type { StyleSpecification } from 'maplibre-gl';

	export function getStyle(theme = 'light', _version = 0): StyleSpecification {
		return {
			version: 8 as const,
			sources: {
				osm: {
					type: 'raster' as const,
					tiles: [
						'https://a.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png',
						'https://b.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png',
						'https://c.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png',
						'https://d.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png'
					],
					tileSize: 256,
					attribution:
						'&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors &copy; <a href="https://carto.com/">CARTO</a>'
				}
			},
			layers: [
				{
					id: 'osm',
					type: 'raster' as const,
					source: 'osm'
				}
			]
		};
	}

	let map = $state<maplibregl.Map>();

	let init = false;
	let coordinates: maplibregl.LngLatLike[] = $state(data.coordinates);
	let markers: maplibregl.Marker[] = [];
	function addMarkers(
		markers: maplibregl.Marker[],
		coordinates: maplibregl.LngLatLike[],
		color: string
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
				element: el
			})
				.setLngLat(coordinate)
				.addTo(map!);
			return marker;
		});
	}

	$effect(() => {
		if (!map) return;
		markers = addMarkers(markers, coordinates, 'green');
	});
</script>

<div class="flex h-full w-screen">
	<Map
		bind:map
		zoom={10}
		style={getStyle('light', 0)}
		class="h-[600px] w-full rounded-lg border shadow"
		attribution={"&copy; <a href='http://www.openstreetmap.org/copyright' target='_blank'>OpenStreetMap</a>"}
		center={[14.5771254, 51.5269344]}
	></Map>
</div>
