try {
	await fetch('http://prima:3000/apiInternal/addPeriodicAvailability', {
		method: 'POST'
	});
} catch (err) {
	console.error('Error:', err);
}
