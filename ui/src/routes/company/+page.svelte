<script lang="ts">
	import type { PageData } from './$types.js';
	export let data: PageData;
	import * as Form from '$lib/components/ui/form';
	import { Input } from '$lib/components/ui/input';
	import * as Select from '$lib/components/ui/select';
	import { formSchema } from './schema';
	import { superForm } from 'sveltekit-superforms';
	import { zodClient } from 'sveltekit-superforms/adapters';
	import * as Card from '$lib/components/ui/card';

	const form = superForm(data.form, {
		validators: zodClient(formSchema)
	});
	const { form: formData, enhance } = form;

	$: selectedZone = {
		value: $formData.zone,
		label: $formData.zone
	};

	$: selectedCommunity = {
		value: $formData.community,
		label: $formData.community
	};

	if (data.company) {
		$formData.companyname = data.company.display_name;
		$formData.email = data.company.email;

		$formData.zone = data.zones.find((z) => (z.id! = data.company!.zone))!.name;
		$formData.community = data.zones.find((z) => (z.id! = data.company!.community_area))!.name;
	}
</script>

<div class="grid gap-4 md:grid-cols-2 lg:grid-cols-2">
	<Card.Root class="w-fit m-auto">
		<div class="flex justify-between">
			<Card.Header>
				<Card.Title>Fahrzeuge und Touren</Card.Title>
				<Card.Description>Fahrzeugverfügbarkeit- und Tourenverwaltung</Card.Description>
			</Card.Header>
			<div class="font-semibold leading-none tracking-tight p-6 flex gap-4">
				<div class="flex gap-1">
					<form method="POST" use:enhance>
						<Card.Content>
							<Form.Field {form} name="companyname">
								<Form.Control let:attrs>
									<Form.Label>Name</Form.Label>
									<Form.FieldErrors />
									<Input {...attrs} bind:value={$formData.companyname} />
								</Form.Control>
							</Form.Field>

							<Form.Field {form} name="email">
								<Form.Control let:attrs>
									<Form.Label>Email</Form.Label>
									<Form.FieldErrors />
									<Input {...attrs} bind:value={$formData.email} />
								</Form.Control>
							</Form.Field>

							<Form.Field {form} name="address">
								<Form.Control let:attrs>
									<Form.Label>Unternehmenssitz</Form.Label>
									<Form.FieldErrors />
									<Input {...attrs} bind:value={$formData.address} />
								</Form.Control>
							</Form.Field>

							<Form.Field {form} name="zone">
								<Form.Control let:attrs>
									<Form.Label for="zone">Pflichtfahrgebiet</Form.Label>
									<Form.FieldErrors />
									<Select.Root
										selected={selectedZone}
										onSelectedChange={(s) => 
										{
											s && s.label && ($formData.zone = s.label!);
										}}
									>
										<Select.Trigger id="zone">
											<Select.Value placeholder="Bitte auswählen" />
										</Select.Trigger>
										<Select.Content>
											{#each data.zones as zone}
												<Select.Item value={zone} label={zone.name.toString()}
													>{zone.name.toString()}</Select.Item
												>
											{/each}
										</Select.Content>
									</Select.Root>
									<input hidden name={attrs.name} bind:value={$formData.zone} />
								</Form.Control>
							</Form.Field>

							<Form.Field {form} name="community">
								<Form.Control let:attrs>
									<Form.Label for="community">Gemeinde</Form.Label>
									<Form.FieldErrors />
									<Select.Root
										selected={selectedCommunity}
										onSelectedChange={(s) => 
										{
											s && s.label && ($formData.community = s.label!);
										}}
									>
										<Select.Trigger id="community">
											<Select.Value placeholder="Bitte auswählen" />
										</Select.Trigger>
										<Select.Content>
											{#each data.zones as community}
												<Select.Item value={community} label={community.name.toString()}
													>{community.name.toString()}</Select.Item
												>
											{/each}
										</Select.Content>
									</Select.Root>
									<input hidden name={attrs.name} bind:value={$formData.community} />
								</Form.Control>
							</Form.Field>
						</Card.Content>

						<Card.Footer>
							<Form.Button>Übernehmen</Form.Button>
						</Card.Footer>
					</form>
				</div>
			</div>
		</div>
	</Card.Root>

	<Card.Root>
		<Card.Content>
			<Input value="test">TEST</Input>
		</Card.Content>
	</Card.Root>
</div>
