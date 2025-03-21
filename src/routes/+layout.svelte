<script lang="ts">
	import '../app.css';

	import ChevronsRight from 'lucide-svelte/icons/chevrons-right';
	import TicketCheck from 'lucide-svelte/icons/ticket-check';
	import UserRound from 'lucide-svelte/icons/user-round';
	import CarTaxiFront from 'lucide-svelte/icons/car-taxi-front';
	import Building2 from 'lucide-svelte/icons/building-2';
	import UsersRound from 'lucide-svelte/icons/users-round';
	import CircleAlert from 'lucide-svelte/icons/circle-alert';
	import Receipt from 'lucide-svelte/icons/receipt';

	import * as Alert from '$lib/shadcn/alert';

	import Menu, { type Item as MenuItem } from './Menu.svelte';
	import { t } from '$lib/i18n/translation';

	let { children, data } = $props();

	const baseItems: Array<MenuItem> = [{ title: t.menu.account, href: '/account', Icon: UserRound }];
	const customerItems: Array<MenuItem> = [
		{ title: t.menu.connections, href: '/routing', Icon: ChevronsRight },
		...(data.isLoggedIn ? [{ title: t.menu.bookings, href: '/bookings', Icon: TicketCheck }] : [])
	];
	const taxiOwnerItems: Array<MenuItem> = [
		{ title: t.menu.accounting, href: '/taxi/accounting', Icon: Receipt },
		{ title: t.menu.availability, href: '/taxi/availability', Icon: CarTaxiFront },
		{ title: t.menu.company, href: '/taxi/company', Icon: Building2 },
		{ title: t.menu.employees, href: '/taxi/members', Icon: UsersRound }
	];
	const adminItems: Array<MenuItem> = [
		{ title: t.menu.accounting, href: '/admin/accounting', Icon: Receipt },
		{ title: t.menu.companies, href: '/admin/taxi-owners', Icon: CarTaxiFront }
	];

	const items = $derived([
		...(!data.isTaxiOwner && !data.isAdmin ? customerItems : []),
		...(data.isTaxiOwner ? taxiOwnerItems : []),
		...(data.isAdmin ? adminItems : []),
		...baseItems
	]);
</script>

<div class="flex h-full w-full flex-col">
	{#if data.pendingRating}
		<Alert.Root class="mb-2">
			<CircleAlert class="size-4" />
			<Alert.Title></Alert.Title>
			<Alert.Description>
				{t.rating.thanksForUsing}<br />
				{t.rating.howHasItBeen}
				<a class="font-bold underline" href="/rating/{data.pendingRating.id}">
					{t.rating.giveFeedback}
				</a>
			</Alert.Description>
		</Alert.Root>
	{/if}
	<div class="flex grow flex-col pb-16">
		<div
			id="searchmask-container"
			class="grow overflow-x-auto p-2 py-6 md:mx-auto md:flex md:items-center"
		>
			{@render children()}
		</div>
	</div>
	<Menu {items} />
</div>
