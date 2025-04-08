<script lang="ts">
	import { t } from '$lib/i18n/translation';

	const {
		passengers,
		wheelchair,
		price,
		luggage,
		lightLuggage
	}: {
		passengers: number;
		wheelchair: boolean;
		price: number;
		luggage: number;
		lightLuggage: number;
	} = $props();
</script>

<div class="mb-2">{t.booking.summary}:</div>
<ul class="flex list-inside list-disc flex-col gap-2">
	<li>
		{t.booking.totalPrice}:
		<span class="font-bold">{price} €</span>
	</li>

	<li>{t.booking.bookingFor(passengers)}</li>

	{#if wheelchair}
		<li>{t.booking.withFoldableWheelchair}</li>
	{/if}

	<li>mit {luggage} Koffern</li>
	<li>und {lightLuggage} Handgepäcken</li>
</ul>
