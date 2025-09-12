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
	import { cols, cols2, getCols3, jaegerTagColumn } from './tableData.js';
	import Select from '$lib/ui/Select.svelte';
	import { tracingOperationNames } from '$lib/util/tracingNames.js';
	import CoordinatePicker from '$lib/ui/CoordinatePicker.svelte';
	import { Button } from '$lib/shadcn/button';
	import type { LngLat } from 'maplibre-gl';
	import type { Column } from '$lib/ui/tableData.js';

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

	const states = [
		'CHOOSE_TRACE',
		'FILTER_START',
		'FILTER_TARGET',
		'VIEW_LOGS',
		'FILTER_START_BUSSTOPS',
		'FILTER_TARGET_BUSSTOPS'
	];
	const { data } = $props();
	let currentState = $state(states[0]);
	let prevState = $state(states[0]);

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
		{ key: 'startFixed', value: startFixed },
		{ key: 'company', value: company },
		{ key: 'vehicle', value: vehicle }
	]);

	$effect(() => {
		console.log("filters: ", { how },
		{ what },
		{ direction },
		{ prev },
		{ next },
		{ startFixed },
		{ company },
		{ vehicle })
	});
	let startCoordinates = $state(new Array<maplibregl.LngLatLike>());
	let targetCoordinates = $state(new Array<maplibregl.LngLatLike>());
	let startBusstopCoordinates = $state(new Array<maplibregl.LngLatLike>());
	let targetBusstopCoordinates = $state(new Array<maplibregl.LngLatLike>());
	let selectedRow: JaegerNode[] = $state([]);

	let startBusIdxs: number[] = $derived(
		selectedRow.length === 0
			? []
			: startBusstopCoordinates
					.map(
						(b) =>
							selectedRow[0].startBusStops?.findIndex(
								(b2) =>
									(b as maplibregl.LngLat).lat === (b2 as maplibregl.LngLat).lat &&
									(b as maplibregl.LngLat).lng === (b2 as maplibregl.LngLat).lng
							) ?? -1
					)
					.filter((b) => b !== -1)
	);
	let targetBusIdxs: number[] = $derived(
		selectedRow.length === 0
			? []
			: targetBusstopCoordinates
					.map(
						(b) =>
							selectedRow[0].targetBusStops?.findIndex(
								(b2) =>
									(b as maplibregl.LngLat).lat === (b2 as maplibregl.LngLat).lat &&
									(b as maplibregl.LngLat).lng === (b2 as maplibregl.LngLat).lng
							) ?? -1
					)
					.filter((b) => b !== -1)
	);

	let traceRows = $derived(
		data.whitelist.filter(
			(t) =>
				(startCoordinates.length === 0 ||
					startCoordinates.some(
						(c) =>
							(c as LngLat).lat === t.startCoordinates?.lat &&
							(c as LngLat).lng === t.startCoordinates?.lng
					)) &&
				(targetCoordinates.length === 0 ||
					targetCoordinates.some(
						(c) =>
							(c as LngLat).lat === t.targetCoordinates?.lat &&
							(c as LngLat).lng === t.targetCoordinates?.lng
					))
		)
	);

	let spanRows: JaegerNode[] = $derived(
		selectedRow.length === 0
			? []
			: (traceRows
					?.filter((t) => selectedRow[0].traceID === t.traceID)
					.map((t) => filterTree(t, filters, startBusIdxs, targetBusIdxs, new Set<number>()))
					.flatMap((trees) => trees.flatMap((t) => expandTree(t)))
					.filter((s) => tracingOperationNames.some((n) => n === s.operationName)) ?? [])
	);

	$effect(() => {
		console.log("hi", spanRows.length)
	})

	function setState(idx: number) {
		prevState = currentState;
		currentState = states[idx];
	}

	$effect(() => {
		if (selectedRow.length !== 0 && states.findIndex((s) => s === currentState) < 3) {
			setState(3);
		}
	});
	let coordinates: maplibregl.LngLatLike[] | undefined = $state(undefined);
	let isMapOpen = $state(true);

	$effect(() => {
		switch (currentState) {
			case 'CHOOSE_TRACE':
				coordinates = undefined;
				break;
			case 'FILTER_START':
				isMapOpen = true;
				coordinates = data.whitelist
					.filter((t) => t.startCoordinates)
					.map((t) => t.startCoordinates!);
				break;
			case 'FILTER_TARGET':
				isMapOpen = true;
				coordinates = data.whitelist
					.filter((t) => t.targetCoordinates)
					.map((t) => t.targetCoordinates!);
				break;
			case 'VIEW_LOGS':
				coordinates = undefined;
				break;
			case 'FILTER_START_BUSSTOPS':
				isMapOpen = true;
				coordinates = selectedRow.length === 0 ? [] : (selectedRow[0]?.startBusStops! ?? []);
				break;
			case 'FILTER_TARGET_BUSSTOPS':
				isMapOpen = true;
				coordinates = selectedRow.length === 0 ? [] : (selectedRow[0]?.targetBusStops! ?? []);
				break;
		}
	});

	$effect(() => {
		if (!isMapOpen) {
			currentState = prevState;
		}
	});

	let colRows: string[] = $state([]);
	$effect(() => {
		const keys = new Set<string>();
		spanRows.forEach((span) => {
			span.logs.forEach((log) => {
		    	log.fields.forEach((f) => keys.add(f.key));
			});
		});
		colRows = [...keys];
		console.log({keys})
	});
	let cols3: Column<JaegerNode>[] = $derived(
  		colRows.map((key) => jaegerTagColumn(key))
);
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
		<Button
			type="submit"
			onclick={() => {
				setState(4);
			}}>Starthaltestellen filtern</Button
		>
		<Button
			type="submit"
			onclick={() => {
				setState(5);
			}}>Zielhaltestellen filtern</Button
		>
	</div>
{/snippet}

{#if isMapOpen && coordinates !== undefined}
	{#if currentState === states[1]}
		<div>
			<CoordinatePicker
				{coordinates}
				bind:pickedCoordinates={startCoordinates}
				bind:open={isMapOpen}
			/>
		</div>
	{:else if currentState === states[2]}
		<div>
			<CoordinatePicker
				{coordinates}
				bind:pickedCoordinates={targetCoordinates}
				bind:open={isMapOpen}
			/>
		</div>
	{:else if currentState === states[4]}
		<div>
			<CoordinatePicker
				{coordinates}
				bind:pickedCoordinates={startBusstopCoordinates}
				bind:open={isMapOpen}
			/>
		</div>
	{:else if currentState === states[5]}
		<div>
			<CoordinatePicker
				{coordinates}
				bind:pickedCoordinates={targetBusstopCoordinates}
				bind:open={isMapOpen}
			/>
		</div>
	{/if}
{:else if currentState === 'CHOOSE_TRACE'}
	<div class="flex flex-col">
		<div class="flex flex-row">
			<Button
				type="submit"
				onclick={() => {
					setState(1);
				}}>Start filtern</Button
			>
			<Button
				type="submit"
				onclick={() => {
					setState(2);
				}}>Ziel filtern</Button
			>
		</div>
		<div class="flex flex-row justify-start">
			<SortableTable
				bind:rows={traceRows}
				{cols}
				getRowStyle={(_) => 'cursor-pointer '}
				bind:selectedRow
				bindSelectedRow={true}
			/>
		</div>
	</div>
{:else}
	<div class="flex h-full w-screen flex-col">
		<div class="flex flex-row justify-start">
			{@render filterOptions()}
		</div>
		<div>
			<SortableTable rows={spanRows} cols={cols3} />
		</div>
	</div>
{/if}
