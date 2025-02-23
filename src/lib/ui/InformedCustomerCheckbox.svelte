<script lang="ts">
	import { invalidateAll } from '$app/navigation';
	import type { TourEvent } from '$lib/server/db/getTours';
	import Checkbox from '$lib/shadcn/checkbox/checkbox.svelte';
	import { updateInformedCustomer } from '$lib/updateInformedCustomer';

	let {
		event = $bindable()
	}: {
		event: TourEvent;
	} = $props();

	const handleCheckboxChange = async () => {
		await updateInformedCustomer(event.tour, event.customer, event.informed);
		await invalidateAll();
	};
</script>

<Checkbox bind:checked={event.informed} onCheckedChange={handleCheckboxChange} />
