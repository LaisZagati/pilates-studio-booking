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
-- Sections 1–7 test the open-booking engine; the timetable is tested in section 8.
update public.services set schedule_only = false;
update public.business_settings set require_online_payment = false;

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


-- =====================================================================
-- 8. AUTOMATED STUDIO: timetable, card payment holds, credits, waitlist
-- =====================================================================
reset role;
update public.services set schedule_only = true;
update public.business_settings set require_online_payment = true, payment_hold_minutes = 15, cancellation_window_hours = 24;
insert into auth.users(id, email, email_confirmed_at) values
  ('00000000-0000-0000-0000-0000000000c3', 'cara@client.test', now()),
  ('00000000-0000-0000-0000-0000000000c4', 'dani@client.test', now());
-- Timetable 3 weeks out: Mat Wed 19:00 (4 places), two Privates Thu 09:00 side by side, Duet Thu 09:00 must clash.
create table public.t8 as
select (t10 + interval '16 days 9 hours') as mat19,     -- Wednesday 19:00
       (t10 + interval '17 days' - interval '1 hour') as thu9  -- Thursday 09:00
  from public.t_ctx;
grant select on public.t8 to anon, authenticated;
set role authenticated;
select t_as('authenticated', '00000000-0000-0000-0000-0000000000a1');
select t_ok(((create_recurring_series((select mat_id from t_ctx), extract(dow from (select mat19 from t8) at time zone 'Europe/Madrid')::int, '19:00',
              ((select mat19 from t8) at time zone 'Europe/Madrid')::date, ((select mat19 from t8) at time zone 'Europe/Madrid')::date))->>'created')::int = 1,
            'Timetable: Mat Wednesday 19:00 created');
select create_recurring_series((select private_id from t_ctx), extract(dow from (select thu9 from t8) at time zone 'Europe/Madrid')::int, '09:00',
              ((select thu9 from t8) at time zone 'Europe/Madrid')::date, ((select thu9 from t8) at time zone 'Europe/Madrid')::date);
select t_ok(((create_recurring_series((select private_id from t_ctx), extract(dow from (select thu9 from t8) at time zone 'Europe/Madrid')::int, '09:00',
              ((select thu9 from t8) at time zone 'Europe/Madrid')::date, ((select thu9 from t8) at time zone 'Europe/Madrid')::date))->>'created')::int = 1,
            'Timetable: second Private at the same time takes the second reformer');
select t_ok(((create_recurring_series((select duet_id from t_ctx), extract(dow from (select thu9 from t8) at time zone 'Europe/Madrid')::int, '09:00',
              ((select thu9 from t8) at time zone 'Europe/Madrid')::date, ((select thu9 from t8) at time zone 'Europe/Madrid')::date))->>'created')::int = 0,
            'Timetable: a Duet clashing with two Privates is refused (skipped)');
insert into packages(name, credits, price_cents, validity_days) values ('5-class pack', 5, 9000, 90);
reset role;

set role anon;
select t_as('anon', null);
select t_ok((select count(*) from get_available_slots((select mat_id from t_ctx),
              ((select mat19 from t8) at time zone 'Europe/Madrid')::date, ((select mat19 from t8) at time zone 'Europe/Madrid')::date)) = 1,
            'Timetable: only the scheduled Mat class is offered that day (no open grid)');
select t_err($$ select book_session((select mat_id from t_ctx), (select mat19 from t8) - interval '2 hours', 'Off Time', 'off@test.com', null) $$,
             'SLOT_UNAVAILABLE', 'Timetable: times outside the timetable cannot be booked');

-- Card payment hold
create temp table p1 as select book_session((select mat_id from t_ctx), (select mat19 from t8), 'Card Payer', 'card@test.com', null) as r;
select t_ok(((select r from p1)->>'requires_payment')::boolean and (select r from p1)->>'status' = 'pending',
            'Paid booking starts as pending, awaiting card payment');
select t_ok((select spots_left from get_available_slots((select mat_id from t_ctx),
              ((select mat19 from t8) at time zone 'Europe/Madrid')::date, ((select mat19 from t8) at time zone 'Europe/Madrid')::date)) = 3,
            'The pending booking holds its place (3 left)');
select t_err($$ select confirm_booking_payment(((select r from p1)->>'booking_id')::uuid, 2000, 'cs_test_1') $$,
             'permission denied', 'Visitors cannot fake a payment confirmation');
reset role;
select t_as('service_role', null);
select t_ok((confirm_booking_payment(((select r from p1)->>'booking_id')::uuid, 2000, 'cs_test_1'))->>'action' = 'confirmed',
            'Stripe webhook (service role) confirms the booking');
select t_ok((confirm_booking_payment(((select r from p1)->>'booking_id')::uuid, 2000, 'cs_test_1'))->>'action' = 'none',
            'Repeated webhook is ignored (idempotent)');
select t_ok((select status = 'confirmed' and payment_status = 'paid' from bookings where id = ((select r from p1)->>'booking_id')::uuid),
            'Booking confirmed and marked paid');

-- Unpaid hold expires and frees the place
create temp table p2 as select book_session((select mat_id from t_ctx), (select mat19 from t8), 'Slow Payer', 'slow@test.com', null) as r;
update bookings set hold_expires_at = now() - interval '1 minute' where id = ((select r from p2)->>'booking_id')::uuid;
select run_maintenance();
select t_ok((select status from bookings where id = ((select r from p2)->>'booking_id')::uuid) = 'cancelled',
            'Expired unpaid hold is cancelled automatically');
select t_ok((confirm_booking_payment(((select r from p2)->>'booking_id')::uuid, 2000, 'cs_late'))->>'action' in ('confirmed','refund'),
            'Late payment after expiry is either re-confirmed (place still free) or refunded');

-- Credits
select t_as('service_role', null);
select grant_package_credits((select id from clients where email = 'cara@client.test'), (select id from packages limit 1), 9000, 'cs_pack_1')
  from (select link_my_client()) x where false;  -- (client row is created on first login below)
set role authenticated;
select t_as('authenticated', '00000000-0000-0000-0000-0000000000c3');
select t_ok(link_my_client() is not null, 'Cara signs in');
select t_err($$ select book_with_credit((select mat_id from t_ctx), (select mat19 from t8)) $$, 'NO_CREDITS', 'No credits yet → cannot book with credit');
reset role;
select t_as('service_role', null);
select grant_package_credits((select id from clients where email = 'cara@client.test'), (select id from packages limit 1), 9000, 'cs_pack_1');
select grant_package_credits((select id from clients where email = 'cara@client.test'), (select id from packages limit 1), 9000, 'cs_pack_1');
select t_ok((select count(*) from client_credits where provider_ref = 'cs_pack_1') = 1
            and (select credits_total from client_credits where provider_ref = 'cs_pack_1') = 5,
            'Pack purchase webhook grants 5 credits once (idempotent)');
set role authenticated;
select t_as('authenticated', '00000000-0000-0000-0000-0000000000c3');
create temp table cbk as select book_with_credit((select mat_id from t_ctx), (select mat19 from t8)) as r;
select t_ok((select r->>'status' from cbk) = 'confirmed' and (select credits_used from client_credits) = 1,
            'Booking with a credit confirms instantly and uses 1 credit');
create temp table ccx as select cancel_booking(((select r from cbk)->>'booking_id')::uuid) as r;
select t_ok(((select r from ccx)->>'credit_returned')::int = 1 and (select credits_used from client_credits) = 0,
            'Cancelling in time returns the credit');
select book_with_credit((select mat_id from t_ctx), (select mat19 from t8));

-- Fill the class: card(1) + cara(1) + 2 more
reset role;
select t_as('anon', null);
set role anon;
select book_session((select mat_id from t_ctx), (select mat19 from t8), 'Filler One', 'f1@test.com', null);
select book_session((select mat_id from t_ctx), (select mat19 from t8), 'Filler Two', 'f2@test.com', null);
select t_ok((select spots_left from get_available_slots((select mat_id from t_ctx),
              ((select mat19 from t8) at time zone 'Europe/Madrid')::date, ((select mat19 from t8) at time zone 'Europe/Madrid')::date)) = 0,
            'Class full: shown with 0 places (so the app can offer the waitlist)');
reset role;

-- Waitlist: Dani (with credit) joins
select t_as('service_role', null);
set role authenticated;
select t_as('authenticated', '00000000-0000-0000-0000-0000000000c4');
select link_my_client();
reset role;
select t_as('service_role', null);
select grant_package_credits((select id from clients where email = 'dani@client.test'), (select id from packages limit 1), 9000, 'cs_pack_2');
set role authenticated;
select t_as('authenticated', '00000000-0000-0000-0000-0000000000c4');
select t_ok(join_waitlist((select g.session_id from get_available_slots((select mat_id from t_ctx), ((select mat19 from t8) at time zone 'Europe/Madrid')::date, ((select mat19 from t8) at time zone 'Europe/Madrid')::date) g)) is not null,
            'Dani joins the waitlist of the full class');
select t_err($$ select join_waitlist((select g.session_id from get_available_slots((select mat_id from t_ctx), ((select mat19 from t8) at time zone 'Europe/Madrid')::date, ((select mat19 from t8) at time zone 'Europe/Madrid')::date) g)) $$,
             'ALREADY_WAITLISTED', 'Cannot join twice');
-- Cara cancels → Dani is booked automatically with her credit
select t_as('authenticated', '00000000-0000-0000-0000-0000000000c3');
reset role;
create temp table cara_bk as select b.id from bookings b join clients c on c.id = b.client_id
 where c.email = 'cara@client.test' and b.status = 'confirmed';
grant select on cara_bk to authenticated;
set role authenticated;
select t_as('authenticated', '00000000-0000-0000-0000-0000000000c3');
select cancel_booking((select id from cara_bk));
select t_as('authenticated', '00000000-0000-0000-0000-0000000000c4');
select t_ok((select status from waitlist_entries) = 'booked'
            and (select count(*) from bookings where status = 'confirmed' and paid_with = 'credit') = 1,
            'Cancellation auto-books the first waitlisted client using her credit');
reset role;
select t_ok((select count(*) from notifications where type = 'waitlist_booked') = 1, 'Waitlist "you are booked" email queued');

-- Waitlist without credit → offer (hold) email
select t_as('authenticated', '00000000-0000-0000-0000-0000000000c2');
set role authenticated;
select t_as('authenticated', '00000000-0000-0000-0000-0000000000c2');
select t_ok(join_waitlist((select g.session_id from get_available_slots((select mat_id from t_ctx), ((select mat19 from t8) at time zone 'Europe/Madrid')::date, ((select mat19 from t8) at time zone 'Europe/Madrid')::date) g)) is not null,
            'Bea (no credits) joins the waitlist');
reset role;
update bookings set status = 'cancelled' where id = (select b.id from bookings b join clients c on c.id = b.client_id where c.email = 'f1@test.com' and b.status <> 'cancelled' limit 1);
select _promote_waitlist((select g.session_id from get_available_slots((select mat_id from t_ctx), ((select mat19 from t8) at time zone 'Europe/Madrid')::date, ((select mat19 from t8) at time zone 'Europe/Madrid')::date) g));
select t_ok((select w.status from waitlist_entries w join clients c on c.id = w.client_id where c.email = 'bea@client.test') = 'offered'
            and (select count(*) from notifications where type = 'waitlist_offer') = 1,
            'Without credits she gets a held place + "pay to confirm" offer email');

-- Timetabled Private side by side
set role anon;
select t_as('anon', null);
select book_session((select private_id from t_ctx), (select thu9 from t8), 'Priv One', 'p1@test.com', null);
select t_ok((book_session((select private_id from t_ctx), (select thu9 from t8), 'Priv Two', 'p2@test.com', null))->>'status' = 'pending',
            'Second timetabled Private at the same time books the other reformer session');
select t_err($$ select book_session((select private_id from t_ctx), (select thu9 from t8), 'Priv Three', 'p3@test.com', null) $$,
             'SLOT_UNAVAILABLE', 'Third Private refused: both timetabled sessions taken');
reset role;


-- =====================================================================
-- 9. Demo payment mode
-- =====================================================================
reset role;
insert into sessions(service_id, starts_at, ends_at, capacity)
select private_id, (select thu9 from t8) + interval '1 day', (select thu9 from t8) + interval '1 day 1 hour', 1 from t_ctx;
select _allocate_resources((select id from sessions where starts_at = (select thu9 from t8) + interval '1 day'));
set role anon;
select t_as('anon', null);
create temp table dp as select book_session((select private_id from t_ctx), (select thu9 from t8) + interval '1 day', 'Demo Payer', 'demo@test.com', null) as r;
select t_ok((select count(*) from get_payment_details((select r->>'reference' from dp), (select r->>'manage_token' from dp))) = 1,
            'Payment page finds the booking with its private link');
select t_ok((select count(*) from get_payment_details((select r->>'reference' from dp), repeat('a', 48))) = 0,
            'Payment page reveals nothing with a wrong link');
select t_ok((demo_pay_booking((select r->>'reference' from dp), (select r->>'manage_token' from dp), false))->>'status' = 'declined',
            'Demo "declined card" changes nothing');
select t_ok((select status from get_payment_details((select r->>'reference' from dp), (select r->>'manage_token' from dp))) = 'pending',
            'Still pending after a declined demo card');
select t_ok((demo_pay_booking((select r->>'reference' from dp), (select r->>'manage_token' from dp)))->>'status' = 'confirmed',
            'Demo payment confirms the booking');
reset role;
select t_ok((select provider = 'demo' and method = 'other' and note like 'Demo payment%' from payments
              where booking_id = ((select r from dp)->>'booking_id')::uuid),
            'Demo payment is recorded as a demo, not as real money');
-- packs in demo mode
set role authenticated;
select t_as('authenticated', '00000000-0000-0000-0000-0000000000c2');
select t_ok(((demo_buy_package((select id from packages limit 1)))->>'credits')::int = 5, 'Demo pack purchase adds credits');
reset role;
update business_settings set payment_mode = 'stripe';
set role anon;
select t_as('anon', null);
select t_err($$ select demo_pay_booking('PS-XXXXXX', repeat('a', 48)) $$, 'DEMO_DISABLED', 'Demo payments are impossible once Stripe is switched on');
reset role;
update business_settings set payment_mode = 'demo';

-- Final invariant: no reformer ever double-held
select t_ok(not exists (
  select 1 from session_resources a join session_resources b
    on a.resource_id = b.resource_id and a.session_id <> b.session_id and a.during && b.during),
  'INVARIANT: no reformer is held by two overlapping sessions');
\echo ALL_TESTS_PASSED
