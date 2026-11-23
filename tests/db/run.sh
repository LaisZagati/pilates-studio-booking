#!/usr/bin/env bash
# Usage: PGHOST=/tmp PGPORT=54329 PGUSER=postgres tests/db/run.sh
set -euo pipefail
cd "$(dirname "$0")/../.."
P="psql -v ON_ERROR_STOP=1 -q -tA"
$P -d postgres -c "drop database if exists studio_test" -c "create database studio_test"
$P -d studio_test -f tests/db/supabase_stub.sql
for f in supabase/migrations/*.sql; do $P -d studio_test -f "$f"; done
$P -d studio_test -f supabase/seed.sql
$P -d studio_test -f tests/db/booking_engine_test.sql 2>&1 | sed "s/^psql:[^ ]* NOTICE:  //" | grep -v "^$"
