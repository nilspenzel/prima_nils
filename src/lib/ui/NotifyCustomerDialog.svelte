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

	let { tour = $bindable() } = $props();
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
				{#each tour.events as t}
					<Table.Row>
						<Table.Cell>{t.customerName}</Table.Cell>
						<Table.Cell>{t.customerPhone}</Table.Cell>
					</Table.Row>
				{/each}
			</Table.Body>
		</Table.Root>
		<DialogFooter>
			<Button variant="default" onclick={handleConfirmNotify}>Stornieren bestätigen</Button>
		</DialogFooter>
	</DialogContent>
</Dialog>