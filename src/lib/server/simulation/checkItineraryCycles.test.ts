import { describe, expect, it } from 'vitest';
import { findItineraryCycles, findRepeatedLegTarget } from '$lib/util/checkItineraryCycles';

const legTo = (lat: number, lon: number, mode = 'ODM') => ({
	mode,
	to: { name: 'target', lat, lon }
});

describe('findRepeatedLegTarget', () => {
	it('returns the indexes when a target occurs again', () => {
		const result = findRepeatedLegTarget([legTo(51.5, 14.5), legTo(51.6, 14.6), legTo(51.5, 14.5)]);

		expect(result).toEqual({ firstLegIndex: 0, repeatedLegIndex: 2 });
	});

	it('returns undefined when every target is unique', () => {
		const result = findRepeatedLegTarget([legTo(51.5, 14.5), legTo(51.6, 14.6), legTo(51.7, 14.7)]);

		expect(result).toBeUndefined();
	});

	it('ignores a walk leg that repeats an earlier target', () => {
		const result = findRepeatedLegTarget([legTo(51.5, 14.5), legTo(51.5, 14.5, 'WALK')]);

		expect(result).toBeUndefined();
	});

	it('does not use walk-leg targets as previous targets', () => {
		const result = findRepeatedLegTarget([legTo(51.5, 14.5, 'WALK'), legTo(51.5, 14.5)]);

		expect(result).toBeUndefined();
	});

	it('finds cycles across multiple itineraries', () => {
		const result = findItineraryCycles([
			{ legs: [legTo(51.5, 14.5), legTo(51.6, 14.6)] },
			{ legs: [legTo(51.5, 14.5), legTo(51.6, 14.6), legTo(51.5, 14.5)] }
		]);

		expect(result).toEqual([{ itineraryIndex: 1, firstLegIndex: 0, repeatedLegIndex: 2 }]);
	});
});
