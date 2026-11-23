-- Booking engine + security tests. Run against a fresh DB with the stub,
-- migration and seed applied. Any failure aborts with an error.
\set ON_ERROR_STOP 1
\set QUIET 1

-- ---------- test helpers (test DB only) ----------
create or replace function public.t_ok(cond boolean, label text) returns void language plpgsql as $$
begin
  if not coalesce(cond, false) then raise exception 'FAIL: %', label; end if;
  raise notice 'PASS: %', label;
end $$;
create or replace function public.t_err(stmt text, expected text, label text) returns void language plpgsql as $$
begin
  begin
    execute stmt;
  exception when others then
    if sqlerrm like '%' || expected || '%' then raise notice 'PASS: % (got %)', label, sqlerrm; return; end if;
    raise exception 'FAIL: % — expected %, got %', label, expected, sqlerrm;
  end;
  raise exception 'FAIL: % — expected error %, but it succeeded', label, expected;
end $$;
create or replace function public.t_as(p_role text, p_uid uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', coalesce(p_uid::text, ''), false);
  perform set_config('request.jwt.claim.role', p_role, false);
end $$;
grant execute on function public.t_ok(boolean, text), public.t_err(text, text, text), public.t_as(text, uuid)
  to anon, authenticated;

-- ---------- fixtures ----------
insert into auth.users(id, email, email_confirmed_at) values
  ('00000000-0000-0000-0000-0000000000a1', 'owner@studio.test', now()),
  ('00000000-0000-0000-0000-0000000000c1', 'ana@client.test',   now()),
  ('00000000-0000-0000-0000-0000000000c2', 'bea@client.test',   now());
insert into public.admins(user_id) values ('00000000-0000-0000-0000-0000000000a1');
update public.notification_settings set owner_email = 'owner@studio.test';

-- A Monday 2+ weeks out, 10:00 Madrid time.
create table public.t_ctx as
select ((date_trunc('week', now() at time zone 'Europe/Madrid')::date + 14) + time '10:00')
         at time zone 'Europe/Madrid' as t10,
       (select id from public.services where slug = 'private-reformer') as private_id,
       (select id from public.services where slug = 'duet-reformer')    as duet_id,
       (select id from public.services where slug = 'mat-pilates')      as mat_id;
grant select on public.t_ctx to anon, authenticated;

-- =====================================================================
-- 1. Availability basics (as anonymous visitor)
-- =====================================================================
set role anon;
select t_as('anon', null);
select t_ok((select count(*) from get_available_slots((select private_id from t_ctx),
              ((select t10 from t_ctx) at time zone 'Europe/Madrid')::date,
              ((select t10 from t_ctx) at time zone 'Europe/Madrid')::date)) = 14,
            'Monday 07:00–21:00 offers 14 one-hour Private slots');
select t_ok(exists (select 1 from get_available_slots((select mat_id from t_ctx),
              ((select t10 from t_ctx) at time zone 'Europe/Madrid')::date,
              ((select t10 from t_ctx) at time zone 'Europe/Madrid')::date) g
              where g.starts_at = (select t10 from t_ctx) and g.spots_left = 4),
            'Mat 10:00 shows 4 spots');
select t_err($$ select * from public.bookings $$, 'permission denied', 'anon cannot read bookings table');
select t_err($$ select * from public.clients $$,  'permission denied', 'anon cannot read clients table');
select t_err($$ insert into public.sessions(service_id, starts_at, ends_at, capacity)
                values ((select private_id from t_ctx), now(), now() + interval '1h', 1) $$,
             'permission denied', 'anon cannot insert sessions directly');

-- =====================================================================
-- 2. Reformer rules
-- =====================================================================
-- Guest books Private at 10:00 → uses Reformer 1
select t_ok((book_session((select private_id from t_ctx), (select t10 from t_ctx),
            'Guest One', 'guest1@test.com', '+34 600 111 111')->>'reference') like 'PS-%',
            'Guest books Private 10:00 and gets a PS- reference');
-- Second Private at the same time → Reformer 2
select t_ok((book_session((select private_id from t_ctx), (select t10 from t_ctx),
            'Guest Two', 'guest2@test.com', null)->>'status') = 'confirmed',
            'Second simultaneous Private uses the second reformer');
-- Third Private → no reformer left
select t_err($$ select book_session((select private_id from t_ctx), (select t10 from t_ctx),
             'Guest Three', 'guest3@test.com', null) $$, 'SLOT_UNAVAILABLE',
             'Third simultaneous Private is refused (only two reformers)');
-- Duet at 10:00 → both reformers busy
select t_err($$ select book_session((select duet_id from t_ctx), (select t10 from t_ctx),
             'Duo', 'duo@test.com', null, 2) $$, 'SLOT_UNAVAILABLE',
             'Duet refused while two Privates hold the reformers');
-- Private at 10:00 has disappeared from availability
select t_ok(not exists (select 1 from get_available_slots((select private_id from t_ctx),
              ((select t10 from t_ctx) at time zone 'Europe/Madrid')::date,
              ((select t10 from t_ctx) at time zone 'Europe/Madrid')::date) g
              where g.starts_at = (select t10 from t_ctx)),
            'Full 10:00 slot no longer listed for Private');

-- Duet at 12:00 reserves both reformers
select book_session((select duet_id from t_ctx), (select t10 from t_ctx) + interval '2 hours',
                    'Duo', 'duo@test.com', null, 2);
select t_err($$ select book_session((select private_id from t_ctx), (select t10 from t_ctx) + interval '2 hours',
             'Guest Four', 'guest4@test.com', null) $$, 'SLOT_UNAVAILABLE',
             'Private refused while a Duet occupies both reformers');
select t_err($$ select book_session((select private_id from t_ctx), (select t10 from t_ctx) + interval '2 hours 30 minutes',
             'Guest Four', 'guest4@test.com', null) $$, 'SLOT_UNAVAILABLE',
             'Off-grid / overlapping time 12:30 refused');
select t_err($$ select book_session((select duet_id from t_ctx), (select t10 from t_ctx) + interval '3 hours',
             'Duo', 'duo@test.com', null, 3) $$, 'PARTY_SIZE_INVALID',
             'Duet cannot take 3 people');

-- Private at 14:00, then Duet at 14:00 refused (one reformer is busy)
select book_session((select private_id from t_ctx), (select t10 from t_ctx) + interval '4 hours',
                    'Guest Five', 'guest5@test.com', null);
select t_err($$ select book_session((select duet_id from t_ctx), (select t10 from t_ctx) + interval '4 hours',
             'Duo', 'duo@test.com', null, 2) $$, 'SLOT_UNAVAILABLE',
             'Duet refused when one Private already uses a reformer');

-- =====================================================================
-- 3. Mat capacity (independent of reformers)
-- =====================================================================
select book_session((select mat_id from t_ctx), (select t10 from t_ctx), 'Mat A', 'mata@test.com', null);
select book_session((select mat_id from t_ctx), (select t10 from t_ctx), 'Mat B', 'matb@test.com', null, 2);
select t_ok((select spots_left from get_available_slots((select mat_id from t_ctx),
              ((select t10 from t_ctx) at time zone 'Europe/Madrid')::date,
              ((select t10 from t_ctx) at time zone 'Europe/Madrid')::date) g
              where g.starts_at = (select t10 from t_ctx)) = 1,
            'Mat runs at 10:00 alongside two reformer Privates; 1 spot left after 3 booked');
select t_err($$ select book_session((select mat_id from t_ctx), (select t10 from t_ctx),
             'Mat C', 'matc@test.com', null, 2) $$, 'SLOT_UNAVAILABLE',
             'Mat refuses 2 more when only 1 spot left');
select book_session((select mat_id from t_ctx), (select t10 from t_ctx), 'Mat D', 'matd@test.com', null);
select t_err($$ select book_session((select mat_id from t_ctx), (select t10 from t_ctx),
             'Mat E', 'mate@test.com', null) $$, 'SLOT_UNAVAILABLE',
             'Fifth Mat client refused (capacity 4)');
select t_err($$ select book_session((select mat_id from t_ctx), (select t10 from t_ctx) + interval '30 minutes',
             'Mat F', 'matf@test.com', null) $$, 'SLOT_UNAVAILABLE',
             'Overlapping second Mat class refused (one mat studio)');

-- =====================================================================
-- 4. Duplicate submissions / validation
-- =====================================================================
select book_session((select private_id from t_ctx), (select t10 from t_ctx) + interval '6 hours',
                    'Idem Pat', 'idem@test.com', null, 1, 'key-123');
select t_ok((book_session((select private_id from t_ctx), (select t10 from t_ctx) + interval '6 hours',
                    'Idem Pat', 'idem@test.com', null, 1, 'key-123')->>'duplicate')::boolean,
            'Repeating the same submission returns the original booking (no double booking)');
select t_err($$ select book_session((select private_id from t_ctx), (select t10 from t_ctx) + interval '7 hours',
             'X', 'bad-email', null) $$, 'INVALID_NAME', 'Name validation');
select t_err($$ select book_session((select private_id from t_ctx), (select t10 from t_ctx) + interval '7 hours',
             'Valid Name', 'bad-email', null) $$, 'INVALID_EMAIL', 'Email validation');
select t_err($$ select book_session((select private_id from t_ctx), now() + interval '30 minutes',
             'Valid Name', 'late@test.com', null) $$, 'SLOT_UNAVAILABLE', 'Minimum advance notice enforced');
select t_err($$ select book_session((select private_id from t_ctx), (select t10 from t_ctx) + interval '120 days',
             'Valid Name', 'far@test.com', null) $$, 'SLOT_UNAVAILABLE', 'Maximum advance window enforced');
select t_err($$ select book_session((select private_id from t_ctx), (select t10 from t_ctx) - interval '6 hours',
             'Valid Name', 'night@test.com', null) $$, 'SLOT_UNAVAILABLE', 'Outside opening hours (04:00) refused');

-- =====================================================================
-- 5. Guest cancel with manage token, availability returns
-- =====================================================================
create temp table g_bk as
select book_session((select private_id from t_ctx), (select t10 from t_ctx) + interval '8 hours',
                    'Guest Cancel', 'gc@test.com', null) as r;
select t_err($$ select cancel_booking(null, (select r->>'reference' from g_bk), 'wrong-token') $$,
             'NOT_FOUND', 'Wrong manage token cannot cancel');
select t_ok((cancel_booking(null, (select r->>'reference' from g_bk), (select r->>'manage_token' from g_bk))->>'status') = 'cancelled',
            'Guest cancels with reference + manage token');
select book_session((select duet_id from t_ctx), (select t10 from t_ctx) + interval '8 hours', 'Duo', 'duo@test.com', null, 2);
select t_ok(true, 'Cancelled Private freed its reformer: Duet now fits at 18:00');
reset role;

-- =====================================================================
-- 6. Signed-in clients and RLS isolation
-- =====================================================================
set role authenticated;
select t_as('authenticated', '00000000-0000-0000-0000-0000000000c1');
select t_ok(link_my_client() is not null, 'Ana links a client record on login');
select book_session((select private_id from t_ctx), (select t10 from t_ctx) + interval '1 day',
                    'Ana Lopez', 'ignored@x.com', '+34 600 222 222');
select t_ok((select count(*) from bookings) = 1, 'Ana sees exactly her own booking');
select t_ok((select email from clients)::text = 'ana@client.test', 'Booking uses Ana''s verified login email, not the typed one');
select t_err($$ select admin_create_booking((select private_id from t_ctx), (select t10 from t_ctx) + interval '1 day 2 hours',
             (select id from clients limit 1)) $$, 'FORBIDDEN', 'Client cannot call admin functions');
select t_err($$ insert into bookings(reference, session_id, client_id, price_cents)
                select 'PS-HACK', session_id, client_id, 0 from bookings limit 1 $$,
             'permission denied', 'Client cannot insert bookings directly');
select t_err($$ update bookings set status = 'completed' $$, 'permission denied', 'Client cannot change booking status');
select t_err($$ update clients set email = 'other@x.com' $$, 'permission denied', 'Client cannot change their email column');
update clients set phone = '+34 699 999 999';
select t_ok((select phone from clients) = '+34 699 999 999', 'Client can update own phone');
select t_ok((select count(*) from client_notes) = 0, 'Client sees no private client notes');
select t_ok((select count(*) from notifications) = 0, 'Client sees no notifications outbox');
select t_ok(request_reschedule((select id from bookings limit 1), 'Could we move to Tuesday?') is not null,
            'Client can request a reschedule');

select t_as('authenticated', '00000000-0000-0000-0000-0000000000c2');
select t_ok(link_my_client() is not null, 'Bea links a client record');
select t_ok((select count(*) from bookings) = 0, 'Bea cannot see Ana''s bookings');
select t_ok((select count(*) from clients) = 1, 'Bea sees only her own client row');
select t_err($$ select cancel_booking((select id from public.bookings where reference like 'PS-%' limit 1)) $$,
             'NOT_FOUND', 'Bea cannot cancel a booking that is not hers');
reset role;
-- (as superuser) Bea tries Ana's booking id explicitly
set role authenticated;
select t_as('authenticated', '00000000-0000-0000-0000-0000000000c2');
reset role;
create temp table ana_bk as select b.id from bookings b join clients c on c.id = b.client_id where c.email = 'ana@client.test';
grant select on ana_bk to authenticated;
set role authenticated;
select t_err($$ select cancel_booking((select id from ana_bk)) $$, 'NOT_FOUND', 'Bea cannot cancel Ana''s booking by id');

-- Late cancellation window for clients
select t_as('authenticated', '00000000-0000-0000-0000-0000000000c1');
reset role;
update business_settings set cancellation_window_hours = 720;  -- 30 days: makes Ana's booking "late"
set role authenticated;
select t_as('authenticated', '00000000-0000-0000-0000-0000000000c1');
select t_err($$ select cancel_booking((select id from bookings limit 1)) $$, 'LATE_CANCELLATION',
             'Client cannot cancel inside the cancellation window');
reset role;
update business_settings set cancellation_window_hours = 24;
set role authenticated;
select t_as('authenticated', '00000000-0000-0000-0000-0000000000c1');
select t_ok((cancel_booking((select id from bookings limit 1))->>'status') = 'cancelled', 'Client cancels own booking in time');

-- =====================================================================
-- 7. Owner: override, blocks, reschedule, payments
-- =====================================================================
select t_as('authenticated', '00000000-0000-0000-0000-0000000000a1');
select t_ok((select count(*) from bookings) > 10, 'Owner sees all bookings');
select t_ok((select count(*) from admin_calendar) = (select count(*) from bookings), 'Admin calendar view works for owner');

-- Override outside opening hours (06:00) works, but needs a reason
select t_err($$ select admin_create_booking((select private_id from t_ctx), (select t10 from t_ctx) - interval '4 hours',
             (select id from clients where email = 'guest1@test.com'), 1, true, null) $$,
             'OVERRIDE_REASON_REQUIRED', 'Override needs a reason');
select t_ok((admin_create_booking((select private_id from t_ctx), (select t10 from t_ctx) - interval '4 hours',
             (select id from clients where email = 'guest1@test.com'), 1, true, 'Early client request')->>'reference') is not null,
            'Owner override books 06:00 outside opening hours');
-- Override can NEVER exceed the two reformers
select t_err($$ select admin_create_booking((select private_id from t_ctx), (select t10 from t_ctx),
             (select id from clients where email = 'guest5@test.com'), 1, true, 'squeeze in') $$,
             'NO_EQUIPMENT', 'Even with override, a third reformer booking at 10:00 is impossible');
-- Override CAN over-fill Mat (owner decision) — with warning flag stored
select t_ok((admin_create_booking((select mat_id from t_ctx), (select t10 from t_ctx),
             (select id from clients where email = 'guest5@test.com'), 1, true, 'Friend of the studio')->>'reference') is not null,
            'Owner override can add a 5th Mat client');
select t_ok((select count(*) from bookings where admin_override) = 2, 'Overrides are flagged on the booking');

-- Holiday block removes availability
insert into blocked_slots(kind, starts_at, ends_at, title)
values ('holiday', (select t10 from t_ctx) + interval '2 days' - interval '10 hours',
                   (select t10 from t_ctx) + interval '3 days' - interval '10 hours', 'Holiday');
select t_ok((select count(*) from get_available_slots((select private_id from t_ctx),
              ((select t10 from t_ctx) at time zone 'Europe/Madrid')::date + 2,
              ((select t10 from t_ctx) at time zone 'Europe/Madrid')::date + 2)) = 0,
            'Holiday: no slots that day');

-- Reschedule: Duo's 12:00 Duet → next day 12:00; old slot frees up
create temp table duet12 as select booking_id from admin_calendar
 where service_slug = 'duet-reformer' and starts_at = (select t10 from t_ctx) + interval '2 hours';
select record_payment((select booking_id from duet12), 4000, 'cash');
select t_ok((select payment_status from bookings where id = (select booking_id from duet12)) = 'partial', 'Partial payment recorded');
create temp table resched as
select reschedule_booking((select booking_id from duet12), (select t10 from t_ctx) + interval '1 day 2 hours') as r;
select t_ok((select payment_status from bookings where id = ((select r from resched)->>'booking_id')::uuid) = 'partial',
            'Payment moved with the rescheduled booking');
select t_ok((select status from bookings where id = (select booking_id from duet12)) = 'cancelled', 'Old booking marked cancelled');
select t_ok(exists (select 1 from get_available_slots((select private_id from t_ctx),
              ((select t10 from t_ctx) at time zone 'Europe/Madrid')::date,
              ((select t10 from t_ctx) at time zone 'Europe/Madrid')::date) g
              where g.starts_at = (select t10 from t_ctx) + interval '2 hours'),
            'Old 12:00 slot is bookable again');
-- Reschedule into a full slot fails and changes nothing
select t_err($$ select reschedule_booking(((select r from resched)->>'booking_id')::uuid, (select t10 from t_ctx)) $$,
             'SLOT_UNAVAILABLE', 'Reschedule into a full slot is refused');
select t_ok((select status from bookings where id = ((select r from resched)->>'booking_id')::uuid) = 'confirmed',
            'Failed reschedule left the booking untouched');

select record_payment(((select r from resched)->>'booking_id')::uuid, 5000, 'card_terminal');
select t_ok((select payment_status from bookings where id = ((select r from resched)->>'booking_id')::uuid) = 'paid', 'Fully paid');
select t_err($$ select record_payment(((select r from resched)->>'booking_id')::uuid, 99999, 'cash', 'refund') $$,
             'REFUND_TOO_LARGE', 'Refund cannot exceed amount paid');
select record_payment(((select r from resched)->>'booking_id')::uuid, 9000, 'cash', 'refund');
select t_ok((select payment_status from bookings where id = ((select r from resched)->>'booking_id')::uuid) = 'refunded', 'Refunded');
select t_err($$ select record_payment(((select r from resched)->>'booking_id')::uuid, 100, 'online') $$,
             'ONLINE_NOT_ENABLED', 'Online payments cannot be faked');

-- Recurring Mat class every Monday 19:00 for 4 weeks
select t_ok(((create_recurring_series((select mat_id from t_ctx), 1, '19:00',
              ((select t10 from t_ctx) at time zone 'Europe/Madrid')::date,
              ((select t10 from t_ctx) at time zone 'Europe/Madrid')::date + 27))->>'created')::int = 4,
            'Recurring Mat: 4 weekly sessions created');

-- Notifications were queued
select t_ok((select count(*) from notifications where type = 'booking_confirmed') > 10, 'Confirmation emails queued');
select t_ok((select count(*) from notifications where type = 'owner_new_booking') > 10, 'Owner new-booking emails queued');
select t_ok((select count(*) from notifications where type = 'booking_cancelled') >= 2, 'Cancellation emails queued');
select t_ok((select count(*) from notifications where type = 'booking_rescheduled') = 1, 'Reschedule email queued');
select t_ok((select count(*) from notifications where type = 'booking_reminder' and status = 'skipped') >= 2,
            'Reminders for cancelled bookings were skipped');
reset role;


-- Guest lookup by reference + token (migration 2)
set role anon;
select t_as('anon', null);
create temp table g2 as select book_session((select private_id from t_ctx), (select t10 from t_ctx) + interval '1 day 3 hours',
                    'Lookup Guest', 'lookup@test.com', null) as r;
select t_ok((select count(*) from get_booking_by_token((select r->>'reference' from g2), (select r->>'manage_token' from g2))) = 1
            and (select can_cancel from get_booking_by_token((select r->>'reference' from g2), (select r->>'manage_token' from g2))),
            'Guest can view own booking with reference + token');
select t_ok((select count(*) from get_booking_by_token((select r->>'reference' from g2), repeat('0', 48))) = 0,
            'Wrong token reveals nothing');
select t_ok((select count(*) from get_booking_by_token((select r->>'reference' from g2), null)) = 0,
            'Missing token reveals nothing');
reset role;

-- Final invariant: no reformer ever double-held
select t_ok(not exists (
  select 1 from session_resources a join session_resources b
    on a.resource_id = b.resource_id and a.session_id <> b.session_id and a.during && b.during),
  'INVARIANT: no reformer is held by two overlapping sessions');
\echo ALL_TESTS_PASSED
