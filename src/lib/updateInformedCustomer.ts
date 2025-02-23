export async function updateInformedCustomer(tourId: number, customer: number, informed: boolean) {
	console.log('informed: ', informed);
	await fetch('http://localhost:5173/api/updateInformedCustomer', {
		method: 'POST',
		headers: {
			'Content-Type': 'application/json'
		},
		body: JSON.stringify({
			tourId,
			customer,
			informed
		})
	});
}
