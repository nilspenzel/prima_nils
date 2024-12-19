import type { Coordinates } from './location';

export type BusStop = {
	coordinates: Coordinates;
	times: Date[];
};

export type RequestBusStop = {
	coordinates: Coordinates;
	times: string[];
}
