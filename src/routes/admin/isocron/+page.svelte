<script lang="ts">
import maplibregl from 'maplibre-gl';
import { getStyle } from '$lib/map/style.js';
import Map from '$lib/map/Map.svelte';
import { env } from '$env/dynamic/public';

const { data } = $props();
let map = $state<maplibregl.Map>();
let coordinates = $state<{ lat: number; lng: number }[]>([]);
let pairs = $state<{ lat: number; lng: number }[][]>([]);
let isLoading = $state(true);
let selected: number = $state(-1);

function addMarkers(
  markers: maplibregl.Marker[],
  coords: { lat: number; lng: number }[],
  color: string
) {
  markers.forEach((marker) => marker.remove());
  return coords.map((coordinate, i) => {
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
      .setLngLat([coordinate.lng, coordinate.lat])
      .addTo(map!);

       el.addEventListener('click', () => {
        selected = i;
    });
    return marker;
  });
}

let markers: maplibregl.Marker[] = [];

// Wait for the streamed coordinates promise to resolve
$effect(() => {
  (async () => {
    try {
      coordinates = ((await data.coordinates)?.coordinates)!;
      pairs = ((await data.coordinates)?.pairs)!;
      console.log("received coordinates ", coordinates.length)
      isLoading = false;
    } catch (error) {
      console.error('Error loading coordinates:', error);
      isLoading = false;
    }
  })();
});

// Add markers when both map and coordinates are ready
$effect(() => {
  if (!map || coordinates.length === 0||isLoading) return;
  if(selected !== -1) {
    markers = [];
    markers = addMarkers(markers, coordinates, 'yellow');
  } else {
    markers = [];
    markers = addMarkers(markers, pairs[selected], 'red')
  }
});
</script>

<div class="flex h-full w-screen">
  <div class="h-full w-full relative">
    <Map
      bind:map
      transformRequest={(url, _resourceType) => {
        if (url.startsWith('/')) {
          return { url: `${env.PUBLIC_MOTIS_URL}/tiles${url}` };
        }
      }}
      center={[14.5771254, 51.5269344]}
      zoom={10}
      style={getStyle('light', 0)}
      class="h-full w-full rounded-lg border shadow"
      attribution={"&copy; <a href='http://www.openstreetmap.org/copyright' target='_blank'>OpenStreetMap</a>"}
    >
    </Map>
  </div>
</div>