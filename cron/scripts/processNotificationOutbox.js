try {
	await fetch('http://prima:3000/apiInternal/processNotificationOutbox', {
		method: 'POST'
	});
} catch (err) {
	console.error('Error:', err);
}
