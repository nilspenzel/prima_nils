<script lang="ts">
	import * as Dialog from '$lib/shadcn/dialog';
	import * as Table from '$lib/shadcn/table';
	import * as Card from '$lib/shadcn/card';

	let {
		expectedStart = $bindable(),
        expectedTarget = $bindable(),
        start = $bindable(),
        target = $bindable()
	}: {
		expectedStart: string | undefined;
        expectedTarget: string | undefined;
        start: string | undefined;
        target: string | undefined;
	} = $props();
</script>

<Dialog.Root
	open={expectedStart !== undefined}
	onOpenChange={(x) => {
		if (!x) {
		    expectedStart = undefined;
            expectedTarget = undefined;
            start = undefined;
            target = undefined;
		}
	}}
>
	<Dialog.Content class="container max-h-screen">
		<Dialog.Header>
			<Dialog.Title>detail</Dialog.Title>
		</Dialog.Header>
		<Dialog.Description>
			<div class="grid grid-cols-2 grid-rows-2 gap-4">
				{@render whitelist()}
			</div>
		</Dialog.Description>
	</Dialog.Content>
</Dialog.Root>

{#snippet whitelist()}
	<Card.Root class="max-h-80 overflow-y-auto">
		<Card.Header>
			<Card.Title>Whitelist Results</Card.Title>
		</Card.Header>
		<Card.Content>
			{#if expectedStart}
				<Table.Root>
					<Table.Header>
						<Table.Row>
							<Table.Head>geplante Startzeit</Table.Head>
							<Table.Head>geplante Ankunftszeit</Table.Head>
							<Table.Head>Startzei</Table.Head>
							<Table.Head>Ankunftszeit</Table.Head>
						</Table.Row>
					</Table.Header>

					<Table.Body>
						<Table.Row>
							<Table.Cell>
								{expectedStart ?? 'abgelehnt'}
							</Table.Cell>
							<Table.Cell>
								{expectedTarget ?? 'abgelehnt'}
							</Table.Cell>
							<Table.Cell>{start ?? 'abgelehnt'}</Table.Cell>
							<Table.Cell>{target ?? 'abgelehnt'}</Table.Cell>
						</Table.Row>
					</Table.Body>
				</Table.Root>
			{/if}
		</Card.Content>
	</Card.Root>
{/snippet}
