<script lang="ts">
	import {
		Dialog,
		DialogTrigger,
		DialogContent,
		DialogHeader,
		DialogFooter,
		DialogTitle
	} from '$lib/shadcn/dialog';
	import { Button } from '$lib/shadcn/button';
	import { Input } from '$lib/shadcn/input';
	import { invalidateAll } from '$app/navigation';

	let { tour = $bindable() } = $props();
	let isDialogOpen = $state(false);
	let reason = $state('');
	let errorMessage: string | undefined = $state(undefined);

	function handleCancel() {
		isDialogOpen = false;
	}

	async function handleConfirm() {
		errorMessage = undefined;
		if (reason == '') {
			errorMessage = 'Stornieren erfordert die Angabe des Grundes.';
			return;
		}
		if (tour != undefined) {
			await fetch('/api/cancelTour', {
				method: 'POST',
				headers: {
					'Content-Type': 'application/json'
				},
				body: JSON.stringify({
					tourId: tour.tourId,
					message: reason
				})
			});
			tour = undefined;
			await invalidateAll();
		}
	}
</script>

<Dialog bind:open={isDialogOpen} onOpenChange={(e) => (isDialogOpen = e)}>
	<DialogTrigger>
		<Button variant="destructive" onclick={() => (isDialogOpen = true)}>Stornieren</Button>
	</DialogTrigger>

	<DialogContent>
		<DialogHeader>
			<DialogTitle>Tour stornieren</DialogTitle>
		</DialogHeader>
		<div class="mb-2 bg-primary-foreground">Bitte geben Sie den Stornierungsgrund an.</div>
		<Input type="text" bind:value={reason} />
		{#if errorMessage != undefined}
			<div class="text-red-500">{errorMessage}</div>
		{/if}

		<DialogFooter>
			<Button variant="default" onclick={handleConfirm}>Stornieren bestätigen</Button>
			<Button variant="outline" onclick={handleCancel}>Stornieren abbrechen</Button>
		</DialogFooter>
	</DialogContent>
</Dialog>
