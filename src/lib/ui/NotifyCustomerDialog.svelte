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
	import * as Table from '$lib/shadcn/table';
	import type { TourEvent } from '$lib/server/db/getTours';

	let { tour = $bindable() } = $props();
	const customerNames: Set<string> = $derived(
		new Set(tour.events.map((e: TourEvent) => e.customerName))
	);
	const customerPhones: Set<string> = $derived(
		new Set(tour.events.map((e: TourEvent) => e.customerPhone))
	);
	let isDialogOpen = $state(false);

    async function handleConfirmNotify() {
        tour = undefined;
    }
</script>

<Dialog bind:open={isDialogOpen} onOpenChange={(e) => (isDialogOpen = e)}>
	<DialogTrigger>
		<Button variant="destructive" onclick={() => (isDialogOpen = true)}>Kunden informieren</Button>
	</DialogTrigger>
	<DialogContent>
		<DialogHeader>
			<DialogTitle>Tour erfolgreich storniert</DialogTitle>
		</DialogHeader>
		<div class="mb-2 bg-primary-foreground">Bitte informieren Sie die Kunden in der folgenden Liste.</div>
		<Table.Root>
			<Table.Header>
				<Table.Row>
					<Table.Head>Kunde</Table.Head>
					<Table.Head>Telefonnummer</Table.Head>
				</Table.Row>
			</Table.Header>
			<Table.Body>
				{#each requests as r}
					<Table.Row>
						<Table.Cell>{r.customerName}</Table.Cell>
						<Table.Cell>{r.customerPhone}</Table.Cell>
					</Table.Row>
				{/each}
			</Table.Body>
		</Table.Root>
		<DialogFooter>
			<Button variant="default" onclick={handleConfirmNotify}>Kunden informiert</Button>
		</DialogFooter>
	</DialogContent>
</Dialog>