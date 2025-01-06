export enum INTERVAL_RELATION {
	EQUAL,
	A_CONTAINS_B,
	B_CONTAINS_A,
	OVERLAPPING_A_EARLIER,
	OVERLAPPING_B_EARLIER,
	A_BEFORE_B,
	B_BEFORE_A,
	TOUCH_A_BEFORE_B,
	TOUCH_B_BEFORE_A
}

export class Interval {
	startTime: Date;
	endTime: Date;

	constructor(startTime: Date, endTime: Date) {
		this.startTime = startTime;
		this.endTime = endTime;
	}

	overlaps(other: Interval) {
		return this.startTime < other.endTime && this.endTime > other.startTime;
	}

	touches(other: Interval) {
		return (
			this.startTime.getTime() == other.endTime.getTime() ||
			this.endTime.getTime() == other.startTime.getTime()
		);
	}

	eitherEndIsEqual(other: Interval) {
		return (
			this.startTime.getTime() == other.startTime.getTime() ||
			this.endTime.getTime() == other.endTime.getTime()
		);
	}

	contains(other: Interval) {
		return this.startTime <= other.startTime && other.endTime <= this.endTime;
	}

	cut(cutter: Interval): Interval {
		if (this.startTime < cutter.startTime) {
			return new Interval(this.startTime, cutter.startTime);
		} else {
			return new Interval(cutter.endTime, this.endTime);
		}
	}

	split(splitter: Interval) {
		return [
			new Interval(this.startTime, splitter.startTime),
			new Interval(splitter.endTime, this.endTime)
		];
	}

	merge(overlapping: Interval) {
		return new Interval(
			new Date(Math.min(this.startTime.getTime(), overlapping.startTime.getTime())),
			new Date(Math.max(this.endTime.getTime(), overlapping.endTime.getTime()))
		);
	}

	equals(other: Interval) {
		return (
			this.startTime.getTime() == other.startTime.getTime() &&
			this.endTime.getTime() == other.endTime.getTime()
		);
	}

	expand(preponeStart: number, postponeEnd: number) {
		return new Interval(
			new Date(this.startTime.getTime() - preponeStart),
			new Date(this.endTime.getTime() + postponeEnd)
		);
	}

	shrink(postponeStart: number, preponeEnd: number) {
		if (this.getDurationMs() < postponeStart + preponeEnd) {
			return undefined;
		}
		return new Interval(
			new Date(this.startTime.getTime() + postponeStart),
			new Date(this.endTime.getTime() - preponeEnd)
		);
	}

	isMergeable(other: Interval): boolean {
		return this.overlaps(other) || this.touches(other);
	}

	getDurationMs() {
		return this.endTime.getTime() - this.startTime.getTime();
	}

	static merge = (unmerged: Interval[]): Interval[] => {
		if (unmerged.length == 0) {
			return new Array<Interval>();
		}
		unmerged.sort((i1, i2) => i1.startTime.getTime() - i2.startTime.getTime());
		const merged = new Array<Interval>();
		for (let i = 1; i < unmerged.length; ++i) {
			const previous = unmerged[i - 1];
			const current = unmerged[i];
			if (previous.isMergeable(current)) {
				unmerged[i] = previous.merge(current);
				continue;
			}
			merged.push(previous);
		}
		merged.push(unmerged.pop()!);
		return merged;
	};

	hasCommonPoint(other: Interval) {
		return this.startTime <= other.endTime && this.endTime >= other.startTime;
	}

	intersect(other: Interval): Interval | undefined {
		if (this.hasCommonPoint(other)) {
			return new Interval(
				new Date(Math.max(this.startTime.getTime(), other.startTime.getTime())),
				new Date(Math.min(this.endTime.getTime(), other.endTime.getTime()))
			);
		}
		return undefined;
	}

	covers(time: Date): boolean {
		return this.startTime <= time && this.endTime >= time;
	}

	static subtract(minuend: Interval[], subtrahend: Interval[]): Interval[] {
		subtrahend.sort((s1, s2) => s1.startTime.getTime() - s2.startTime.getTime());
		minuend.sort((m1, m2) => m1.startTime.getTime() - m2.startTime.getTime());
		let minuendPos = 0;
		let subtrahendPos = 0;
		let ret: Interval[] = [];
		let currentMinuend = minuend[minuendPos];
		let currentSubtrahend = subtrahend[subtrahendPos];
		while (minuendPos != minuend.length && subtrahendPos != subtrahend.length) {
			switch (currentMinuend.getRelation(currentSubtrahend)) {
				case INTERVAL_RELATION.TOUCH_B_BEFORE_A: {
					currentSubtrahend = subtrahend[++subtrahendPos];
					break;
				}
				case INTERVAL_RELATION.TOUCH_A_BEFORE_B: {
					ret.push(currentMinuend);
					currentMinuend = minuend[++minuendPos];
					break;
				}
				case INTERVAL_RELATION.B_BEFORE_A: {
					subtrahendPos++;
					currentSubtrahend = subtrahend[subtrahendPos];
					break;
				}
				case INTERVAL_RELATION.A_BEFORE_B: {
					ret.push(currentMinuend);
					currentMinuend = minuend[++minuendPos];
					break;
				}
				case INTERVAL_RELATION.A_CONTAINS_B: {
					const splitResult = currentMinuend.split(currentSubtrahend);
					if (splitResult[0].startTime < splitResult[0].endTime) {
						ret.push(splitResult[0]);
					}
					currentMinuend =
						splitResult[1].startTime < splitResult[1].endTime
							? splitResult[1]
							: minuend[++minuendPos];
					currentSubtrahend = subtrahend[++subtrahendPos];
					break;
				}
				case INTERVAL_RELATION.B_CONTAINS_A: {
					currentMinuend = minuend[++minuendPos];
					break;
				}
				case INTERVAL_RELATION.OVERLAPPING_B_EARLIER: {
					const cutResult = currentMinuend.cut(currentSubtrahend);
					currentMinuend = cutResult;
					currentSubtrahend = subtrahend[++subtrahendPos];
					break;
				}
				case INTERVAL_RELATION.OVERLAPPING_A_EARLIER: {
					const cutResult = currentMinuend.cut(currentSubtrahend);
					ret.push(cutResult);
					currentMinuend = minuend[++minuendPos];
					break;
				}
				default:
					break;
			}
		}
		if (minuendPos != minuend.length) {
			ret.push(currentMinuend);
			ret = ret.concat(minuend.slice(++minuendPos));
		}
		return ret;
	}
	getRelation(other: Interval): INTERVAL_RELATION {
		if (other.startTime == this.startTime && other.endTime == this.endTime) {
			return INTERVAL_RELATION.EQUAL;
		}
		if (other.contains(this)) {
			return INTERVAL_RELATION.B_CONTAINS_A;
		}
		if (this.contains(other)) {
			return INTERVAL_RELATION.A_CONTAINS_B;
		}
		if (this.overlaps(other)) {
			return this.startTime > other.startTime
				? INTERVAL_RELATION.OVERLAPPING_B_EARLIER
				: INTERVAL_RELATION.OVERLAPPING_A_EARLIER;
		}
		if (this.touches(other)) {
			return this.startTime > other.startTime
				? INTERVAL_RELATION.TOUCH_B_BEFORE_A
				: INTERVAL_RELATION.TOUCH_A_BEFORE_B;
		}
		return this.startTime > other.startTime
			? INTERVAL_RELATION.B_BEFORE_A
			: INTERVAL_RELATION.A_BEFORE_B;
	}
}
