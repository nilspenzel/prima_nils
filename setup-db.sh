#!/bin/sh

export DB="postgresql://postgres:pw@localhost:6500/"
export DATABASE_URL="postgresql://postgres:pw@localhost:6500/prima"

docker compose up -d pg

sleep 2
echo "SELECT pg_terminate_backend(pid)
    FROM pg_stat_activity
    WHERE datname = 'prima' AND pid <> pg_backend_pid();" | psql $DB

echo "DROP DATABASE prima;" | psql $DB
echo "CREATE DATABASE prima;" | psql $DB

pnpm run kysely migrate:latest

psql $DATABASE_URL --user postgres < data/zone.sql
psql $DATABASE_URL --user postgres < data/company.sql
psql $DATABASE_URL --user postgres < data/vehicle.sql
psql $DATABASE_URL --user postgres < data/user.sql
