import { readFile } from 'fs/promises';
import { parse } from 'csv-parse/sync';
import type { PageServerLoad } from './$types';
import { sql } from 'kysely';
import { db } from '$lib/server/db';

export const load: PageServerLoad = async () => {
  try {
    // Read the CSV file
    const filePath = './in_zone.csv';
    const fileContents = await readFile(filePath, 'utf-8');
    // Validate file contents
    if (!fileContents) {
      throw new Error('CSV file is empty');
    }

    // Parse the CSV file
    let records;
    try {
      records = parse(fileContents, {
        columns: true, // Assumes first row is header
        skip_empty_lines: true,
        cast: true // Automatically convert values to appropriate types
      });
    } catch (parseError) {
      console.error('CSV Parsing Error:', parseError);
      throw new Error(`Failed to parse CSV: ${parseError instanceof Error ? parseError.message : 'Unknown parsing error'}`);
    }

    // Validate records
    if (!Array.isArray(records) || records.length === 0) {
      throw new Error('No valid records found in the CSV');
    }

    // Convert coordinates to the expected format with additional validation
    const coordinates: {lat: number, lng: number}[] = records.map((record: any) => {
      // Validate each record has required fields
      if (!record.longitude || !record.latitude) {
        console.warn('Skipping invalid record:', record);
        return null;
      }

      // Convert and validate coordinates
      const lng = parseFloat(record.longitude);
      const lat = parseFloat(record.latitude);

      if (isNaN(lng) || isNaN(lat)) {
        console.warn('Invalid coordinate values:', { longitude: record.longitude, latitude: record.latitude });
        return null;
      }

      return { lng, lat };
    }).filter(coord => coord !== null); // Remove any null entries
    console.log({coordinates})
    return {
      coordinates,
      areas: (await sql`
      SELECT 'FeatureCollection' AS TYPE,
        array_to_json(array_agg(f)) AS features
      FROM
        (SELECT 'Feature' AS TYPE,
          ST_AsGeoJSON(lg.area, 15, 0)::json As geometry,
          json_build_object('id', id, 'name', name) AS properties
        FROM zone AS lg) AS f`.execute(db)).rows[0]
    };
  } catch (error) {
    // Log the full error for debugging
    console.error('Comprehensive Error:', {
      message: error instanceof Error ? error.message : 'Unknown error',
      stack: error instanceof Error ? error.stack : 'No stack trace',
      type: typeof error
    });

    // Return empty coordinates list in case of any error
    return {
      coordinates: []
    };
  }
};