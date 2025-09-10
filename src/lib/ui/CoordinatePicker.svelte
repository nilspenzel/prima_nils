<script lang="ts">
	import maplibregl from 'maplibre-gl';
	import Map from '$lib/map/Map.svelte';

	let {
		pickedCoordinates = $bindable(),
		coordinates,
		open = $bindable()
	}: {
		coordinates: maplibregl.LngLatLike[];
		pickedCoordinates: maplibregl.LngLatLike[];
		open: boolean;
	} = $props();
	import type { StyleSpecification } from 'maplibre-gl';
	import Button from '$lib/shadcn/button/button.svelte';

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
	let markers: maplibregl.Marker[] = [];

	function addMarkers(markers: maplibregl.Marker[], coordinates: maplibregl.LngLatLike[]) {
		markers.forEach((marker) => marker.remove());
		return coordinates.map((coordinate, i) => {
			function setColor(color: string) {
				Object.assign(el.style, {
					backgroundColor: color,
					color: 'black',
					width: '24px',
					height: '24px',
					borderRadius: '50%',
					textAlign: 'center',
					lineHeight: '24px',
					fontWeight: 'bold',
					fontSize: '12px',
					cursor: 'pointer'
				});
			}

			const el = document.createElement('div');
			el.className = 'marker-start';
			el.innerText = `${i + 1}`;
			const exists = pickedCoordinates.some(
				(c) =>
					(c as maplibregl.LngLat).lng === (coordinate as maplibregl.LngLat).lng &&
					(c as maplibregl.LngLat).lat === (coordinate as maplibregl.LngLat).lat
			);
			if (exists) {
				setColor('red');
			} else {
				setColor('green');
			}
			const marker = new maplibregl.Marker({
				element: el
			})
				.setLngLat(coordinate)
				.addTo(map!);

			el.addEventListener('click', () => {
				const exists = pickedCoordinates.some(
					(c) =>
						(c as maplibregl.LngLat).lng === (coordinate as maplibregl.LngLat).lng &&
						(c as maplibregl.LngLat).lat === (coordinate as maplibregl.LngLat).lat
				);
				if (!exists) {
					pickedCoordinates.push(coordinate);
					setColor('red');
				} else {
					pickedCoordinates = pickedCoordinates.filter(
						(c) =>
							(c as maplibregl.LngLat).lat !== (coordinate as maplibregl.LngLat).lat ||
							(c as maplibregl.LngLat).lng !== (coordinate as maplibregl.LngLat).lng
					);
					setColor('green');
				}
			});
			return marker;
		});
	}

	$effect(() => {
		if (!map) return;
		markers = addMarkers(markers, coordinates);
	});
</script>

<div class="flex h-full w-screen">
	<Button onclick={() => (open = false)}>bestätigen</Button>
	<Map
		bind:map
		zoom={10}
		style={getStyle('light', 0)}
		class="h-[600px] w-full rounded-lg border shadow"
		attribution={"&copy; <a href='http://www.openstreetmap.org/copyright' target='_blank'>OpenStreetMap</a>"}
		center={[14.5771254, 51.5269344]}
	></Map>
</div>
