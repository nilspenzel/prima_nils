<script lang="ts">
	import SortableTable from '$lib/ui/SortableTable.svelte';
	import {
		InsertDirection,
		insertDirectionToString,
		InsertHow,
		insertHowToString,
		InsertWhat,
		insertWhatToString
	} from '$lib/util/booking/insertionTypes.js';
	import { expandTree, filterTree, type JaegerNode } from './jaegerTypes.js';
	import { cols, cols2 } from './tableData.js';
	import Select from '$lib/ui/Select.svelte';
	import * as Card from '$lib/shadcn/card';
	import { tracingOperationNames } from '$lib/util/tracingNames.js';

	function getPossibleValues(key: string) {
		return [
			...new Set(
				data.whitelist === undefined
					? []
					: data.whitelist
							.flatMap((w) =>
								expandTree(w).flatMap((s) =>
									s.logs.flatMap((l) => l.fields.filter((f) => f.key === key))
								)
							)
							.map((t) => t.value)
							.filter((v) => v !== -1)
			)
		]
			.filter((i) => typeof i === 'number')
			.sort((i1, i2) => i1 - i2);
	}

	const { data } = $props();

	let selectedHowIdx = $state(-1);
	const howOptions = [
		InsertHow.NEW_TOUR,
		InsertHow.PREPEND,
		InsertHow.INSERT,
		InsertHow.CONNECT,
		InsertHow.APPEND
	].map((h) => insertHowToString(h));
	let how: undefined | string = $derived(howOptions[selectedHowIdx]);

	let selectedWhatIdx = $state(-1);
	const whatOptions = [InsertWhat.BUS_STOP, InsertWhat.USER_CHOSEN, InsertWhat.BOTH].map((w) =>
		insertWhatToString(w)
	);
	let what: undefined | string = $derived(whatOptions[selectedWhatIdx]);

	let selectedDirectionIdx = $state(-1);
	const directionOptions = [InsertDirection.BUS_STOP_DROPOFF, InsertDirection.BUS_STOP_PICKUP].map(
		(d) => insertDirectionToString(d)
	);
	let direction: undefined | string = $derived(directionOptions[selectedDirectionIdx]);

	let selectedPrevIdx = $state(-1);
	const prevOptions = $derived(getPossibleValues('prev'));
	let prev: undefined | string = $derived(String(prevOptions[selectedPrevIdx]));

	let selectedNextIdx = $state(-1);
	const nextOptions = $derived(getPossibleValues('next'));
	let next: undefined | string = $derived(String(nextOptions[selectedNextIdx]));

	let selectedBusStopIdxIdx = $state(-1);
	const busStopIdxOptions = $derived(getPossibleValues('busStopIdx'));
	let busStopIdx: undefined | string = $derived(String(busStopIdxOptions[selectedBusStopIdxIdx]));

	let selectedStartFixedIdx = $state(-1);
	const startFixedOptions = [true, false];
	let startFixed: undefined | string = $derived(String(startFixedOptions[selectedStartFixedIdx]));

	let selectedCompanyIdx = $state(-1);
	const companyOptions = $derived(getPossibleValues('company'));
	let company: undefined | string = $derived(String(companyOptions[selectedCompanyIdx]));

	let selectedVehicleIdx = $state(-1);
	const vehicleOptions = $derived(getPossibleValues('vehicle'));
	let vehicle: undefined | string = $derived(String(vehicleOptions[selectedVehicleIdx]));

	const filters: { key: string; value: string | undefined }[] = $derived([
		{ key: 'how', value: how },
		{ key: 'what', value: what },
		{ key: 'direction', value: direction },
		{ key: 'prev', value: prev },
		{ key: 'next', value: next },
		{ key: 'busStopIdx', value: busStopIdx },
		{ key: 'startFixed', value: startFixed },
		{ key: 'company', value: company },
		{ key: 'vehicle', value: vehicle }
	]);

	const traces = data.whitelist!;
	let rows = $state(traces);
	let selectedRow: JaegerNode[] | undefined = $state(undefined);

	let rows2: JaegerNode[] = $state(
		traces?.filter((t) => selectedRow === undefined || selectedRow[0].traceID === t.traceID)
			.map((t) => filterTree(t, filters))
			.flatMap((t) => expandTree(t))
			.filter((s) => tracingOperationNames.some((n) => n === s.operationName)) ?? []
	);
	$effect(() => {
		rows2 = traces?.filter((t) => selectedRow === undefined || selectedRow[0].traceID === t.traceID)
			.map((t) => filterTree(t, filters))
			.flatMap((t) => expandTree(t))
			.filter((s) => tracingOperationNames.some((n) => n === s.operationName)) ?? [];
	});
</script>

{#snippet filterOptions()}
	<div class="grid gap-2 pb-4 pt-4 sm:grid-cols-1 md:grid-cols-2 lg:grid-cols-4">
		<Select
			bind:selectedIdx={selectedHowIdx}
			entries={howOptions}
			initial={'how'}
			disabled={null}
		/>
		<Select
			bind:selectedIdx={selectedWhatIdx}
			entries={whatOptions}
			initial={'what'}
			disabled={null}
		/>
		<Select
			bind:selectedIdx={selectedDirectionIdx}
			entries={directionOptions}
			initial={'direction'}
			disabled={null}
		/>
		<Select
			bind:selectedIdx={selectedPrevIdx}
			entries={prevOptions}
			initial={'prev'}
			disabled={null}
		/>
		<Select
			bind:selectedIdx={selectedNextIdx}
			entries={nextOptions}
			initial={'next'}
			disabled={null}
		/>
		<Select
			bind:selectedIdx={selectedBusStopIdxIdx}
			entries={busStopIdxOptions}
			initial={'busStopIdx'}
			disabled={null}
		/>
		<Select
			bind:selectedIdx={selectedStartFixedIdx}
			entries={startFixedOptions}
			initial={'startFixed'}
			disabled={null}
		/>
		<Select
			bind:selectedIdx={selectedCompanyIdx}
			entries={companyOptions}
			initial={'company'}
			disabled={null}
		/>
		<Select
			bind:selectedIdx={selectedVehicleIdx}
			entries={vehicleOptions}
			initial={'vehicle'}
			disabled={null}
		/>
	</div>
{/snippet}

<div class="flex flex-col gap-4">
	<div class="flex flex-row justify-start">
		{@render filterOptions()}
	</div>
	<div>
		<Card.Header>
			<Card.Title>Abrechnung</Card.Title>
		</Card.Header>
		<Card.Content>
			<div class="flex flex-row justify-start">
				<SortableTable
					bind:rows
					{cols}
					getRowStyle={(_) => 'cursor-pointer '}
					bind:selectedRow
					bindSelectedRow={true}
				/>
			</div>
			<SortableTable rows={rows2} cols={cols2} />
		</Card.Content>
	</div>
</div>
