#!/usr/bin/env bash
# Fires many simultaneous booking attempts from separate connections and
# checks capacity was never exceeded. Run after tests/db/run.sh.
set -uo pipefail
DB=studio_test
Q() { psql -d $DB -tA -q -c "$1" 2>&1; }
Q "update services set schedule_only=false; update business_settings set require_online_payment=false" >/dev/null
SLOT=$(Q "select (t10 + interval '1 day 5 hours')::text from t_ctx")   # Tue 15:00
SLOT2=$(Q "select (t10 + interval '1 day 6 hours')::text from t_ctx")  # Tue 16:00
attempt() { # service-slug slot name email party
  psql -d $DB -tA -q -c "set role anon; select book_session((select id from services where slug='$1'), '$2', '$3', '$4', null, $5)->>'reference';" 2>&1 | grep -m1 -oE '^PS-[A-Z0-9]+|ERROR: +[A-Z_]+'
}
export -f attempt; export DB
echo "--- 25 simultaneous Private attempts + 5 Duet attempts at the same time (2 reformers)"
( for i in $(seq 1 25); do attempt private-reformer "$SLOT" "Racer $i" "racer$i@race.test" 1 & done
  for i in $(seq 1 5);  do attempt duet-reformer    "$SLOT" "Duo $i"   "duo$i@race.test"   2 & done
  wait ) > /tmp/race1.out
echo "succeeded: $(grep -c '^PS-' /tmp/race1.out)  refused: $(grep -c 'SLOT_UNAVAILABLE\|NO_EQUIPMENT' /tmp/race1.out)"
echo "--- 15 simultaneous Mat attempts (capacity 4)"
( for i in $(seq 1 15); do attempt mat-pilates "$SLOT2" "Mat Racer $i" "matracer$i@race.test" 1 & done; wait ) > /tmp/race2.out
echo "succeeded: $(grep -c '^PS-' /tmp/race2.out)  refused: $(grep -c 'SLOT_UNAVAILABLE\|SESSION_FULL' /tmp/race2.out)"
echo "--- 10 simultaneous identical submissions (same idempotency key)"
( for i in $(seq 1 10); do psql -d $DB -tA -q -c "set role anon; select book_session((select id from services where slug='private-reformer'), '$SLOT2', 'Double Tap', 'tap@race.test', null, 1, 'tap-key-1')->>'reference';" 2>&1 | grep -m1 -oE '^PS-[A-Z0-9]+|ERROR: +.*' & done; wait ) > /tmp/race3.out
echo "distinct references returned: $(grep '^PS-' /tmp/race3.out | sort -u | wc -l)"

echo "--- checks"
Q "select 'reformers held at Tue 15:00: ' || count(*) from session_resources sr join resources r on r.id=sr.resource_id where r.kind='reformer' and sr.during @> '$SLOT'::timestamptz"
Q "select 'reformer-booked people at Tue 15:00: ' || coalesce(sum(b.party_size),0) from bookings b join sessions s on s.id=b.session_id join services v on v.id=s.service_id where v.reformers_required>0 and s.starts_at='$SLOT' and b.status='confirmed'"
Q "select 'mat seats booked at Tue 16:00: ' || coalesce(sum(b.party_size),0) from bookings b join sessions s on s.id=b.session_id join services v on v.id=s.service_id where v.slug='mat-pilates' and s.starts_at='$SLOT2' and b.status='confirmed'"
Q "select 'bookings with tap-key-1: ' || count(*) from bookings where idempotency_key='tap-key-1'"
echo "--- database backstop: raw insert of a third reformer hold (bypassing the engine)"
Q "insert into session_resources select s.id, r.id, tstzrange('$SLOT', '$SLOT'::timestamptz + interval '1 hour') from sessions s, resources r where r.name='Reformer 1' and s.starts_at='$SLOT' and not exists (select 1 from session_resources x where x.session_id=s.id and x.resource_id=r.id) limit 1" | head -1
