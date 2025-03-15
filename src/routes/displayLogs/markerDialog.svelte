<script lang="ts">
	import * as Dialog from '$lib/shadcn/dialog';
	import * as Table from '$lib/shadcn/table';
	import * as Card from '$lib/shadcn/card';

	let {
		blacklistResponse = $bindable(),
        whitelistResponse = $bindable()
	}: {
		blacklistResponse: { blr: boolean; time: Date }[] | undefined;
		whitelistResponse: (undefined | { requestedTime: Date, pickupTime: Date; dropoffTime: Date })[] | undefined;
	} = $props();
</script>

<Dialog.Root
	open={blacklistResponse !== undefined}
	onOpenChange={(x) => {
		if (!x) {
            whitelistResponse = undefined;
			blacklistResponse = undefined;
		}
	}}
>
	<Dialog.Content class="container max-h-screen">
		<Dialog.Header>
			<Dialog.Title>detail</Dialog.Title>
		</Dialog.Header>
		<Dialog.Description>
			<div class="grid grid-cols-2 grid-rows-2 gap-4">
				{@render blacklist()}
			</div>
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
			{#if whitelistResponse}
				<Table.Root>
					<Table.Header>
						<Table.Row>
							<Table.Head>angefragete Zeit</Table.Head>
							<Table.Head>Pickup</Table.Head>
							<Table.Head>Dropoff</Table.Head>
						</Table.Row>
					</Table.Header>

					<Table.Body>
						{#each whitelistResponse as r}
							<Table.Row>
								<Table.Cell>
									{r?.requestedTime ?? 'abgelehnt'}
								</Table.Cell>
								<Table.Cell>
									{r?.pickupTime ?? 'abgelehnt'}
								</Table.Cell>
								<Table.Cell>{r?.dropoffTime ?? 'abgelehnt'}</Table.Cell>
							</Table.Row>
						{/each}
					</Table.Body>
				</Table.Root>
			{/if}
		</Card.Content>
	</Card.Root>
{/snippet}


{#snippet blacklist()}
	<Card.Root class="max-h-80 overflow-y-auto">
		<Card.Header>
			<Card.Title>Blacklist Results</Card.Title>
		</Card.Header>
		<Card.Content>
			{#if blacklistResponse}
				<Table.Root>
					<Table.Header>
						<Table.Row>
							<Table.Head>Zeit</Table.Head>
							<Table.Head>Antwort</Table.Head>
						</Table.Row>
					</Table.Header>

					<Table.Body>
						{#each blacklistResponse as r}
							<Table.Row>
								<Table.Cell>
									{r.time}
								</Table.Cell>
								<Table.Cell>{r.blr}</Table.Cell>
							</Table.Row>
						{/each}
					</Table.Body>
				</Table.Root>
			{/if}
		</Card.Content>
	</Card.Root>
{/snippet}
