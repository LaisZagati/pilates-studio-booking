-- =====================================================================
-- Phase: automated studio
--   * Fixed weekly timetable (services bookable only in scheduled sessions)
--   * Online card payment with a temporary seat hold
--   * Class packs & memberships (credits)
--   * Automatic waitlist
-- Card payments themselves run through Stripe in the app; the database
-- only trusts payment confirmations made with the server's service role.
-- =====================================================================

alter type public.notification_type add value if not exists 'waitlist_offer';
alter type public.notification_type add value if not exists 'waitlist_booked';
alter type public.notification_type add value if not exists 'credits_added';

create type public.paid_with       as enum ('card','credit','studio','free');
create type public.waitlist_status as enum ('waiting','offered','booked','expired','cancelled');

-- ---------------------------------------------------------------------
-- Settings & services
-- ---------------------------------------------------------------------
alter table public.business_settings
  add column if not exists require_online_payment boolean not null default true,
  add column if not exists payment_hold_minutes   int not null default 15 check (payment_hold_minutes between 5 and 120),
  add column if not exists waitlist_offer_hours   int not null default 2  check (waitlist_offer_hours between 1 and 48),
  add column if not exists waitlist_enabled       boolean not null default true;

alter table public.services
  add column if not exists schedule_only boolean not null default true,  -- bookable only in timetable sessions
  add column if not exists allow_credits boolean not null default true;

-- ---------------------------------------------------------------------
-- Packs, memberships and credits
-- ---------------------------------------------------------------------
create table public.packages (
  id               uuid primary key default gen_random_uuid(),
  name             text not null check (char_length(name) between 1 and 80),
  description      text,
  kind             text not null default 'pack' check (kind in ('pack','membership')),
  credits          int  not null check (credits between 1 and 500),     -- per purchase / per billing period
  price_cents      int  not null check (price_cents >= 0),
  validity_days    int  not null default 90 check (validity_days between 1 and 730),
  service_ids      uuid[],                                                -- null = any service that allows credits
  stripe_price_id  text,                                                  -- set when created in Stripe
  sort_order       int not null default 0,
  active           boolean not null default true,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);
create trigger packages_updated before update on public.packages
  for each row execute function public.tg_set_updated_at();

create table public.client_credits (
  id              uuid primary key default gen_random_uuid(),
  client_id       uuid not null references public.clients(id) on delete cascade,
  package_id      uuid references public.packages(id) on delete set null,
  label           text not null,
  credits_total   int  not null check (credits_total >= 0),
  credits_used    int  not null default 0,
  service_ids     uuid[],
  expires_at      timestamptz not null,
  source          text not null check (source in ('purchase','membership','admin','refund')),
  provider_ref    text,                       -- Stripe checkout/invoice id (idempotency)
  created_by      uuid references auth.users(id) on delete set null,
  created_at      timestamptz not null default now(),
  check (credits_used between 0 and credits_total)
);
create index client_credits_client_idx on public.client_credits(client_id, expires_at);
create unique index client_credits_provider_ref_uidx on public.client_credits(provider_ref) where provider_ref is not null;

-- Payments can now belong to a booking OR a credit purchase.
alter table public.payments alter column booking_id drop not null;
alter table public.payments add column if not exists client_credit_id uuid references public.client_credits(id) on delete set null;
alter table public.payments add constraint payments_target_chk check (booking_id is not null or client_credit_id is not null);
create unique index if not exists payments_provider_ref_uidx on public.payments(provider, provider_ref, kind) where provider_ref is not null;
create index if not exists payments_credit_idx on public.payments(client_credit_id);

alter table public.bookings
  add column if not exists paid_with       public.paid_with,
  add column if not exists credit_id       uuid references public.client_credits(id) on delete set null,
  add column if not exists hold_expires_at timestamptz;
create index if not exists bookings_hold_idx on public.bookings(hold_expires_at) where status = 'pending';
create index if not exists bookings_credit_idx on public.bookings(credit_id);

-- ---------------------------------------------------------------------
-- Waitlist
-- ---------------------------------------------------------------------
create table public.waitlist_entries (
  id            uuid primary key default gen_random_uuid(),
  session_id    uuid not null references public.sessions(id) on delete cascade,
  client_id     uuid not null references public.clients(id) on delete cascade,
  party_size    int  not null default 1 check (party_size between 1 and 50),
  status        public.waitlist_status not null default 'waiting',
  booking_id    uuid references public.bookings(id) on delete set null,
  offered_until timestamptz,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
create unique index waitlist_one_active_uidx on public.waitlist_entries(session_id, client_id)
  where status in ('waiting','offered');
create index waitlist_session_idx on public.waitlist_entries(session_id, status, created_at);
create index waitlist_client_idx on public.waitlist_entries(client_id);
create index waitlist_booking_idx on public.waitlist_entries(booking_id);
create trigger waitlist_updated before update on public.waitlist_entries
  for each row execute function public.tg_set_updated_at();

-- =====================================================================
-- Seat counting (pending bookings only count while their hold is valid)
-- =====================================================================
create or replace function public.session_seats_used(p_session_id uuid) returns int
language sql stable security definer set search_path = public, pg_temp as $$
  select coalesce(sum(party_size), 0)::int
    from public.bookings
   where session_id = p_session_id
     and (status in ('confirmed','completed')
          or (status = 'pending' and (hold_expires_at is null or hold_expires_at > now())));
$$;

-- Free places in a session. Private/Duet sessions are taken whole by one booking.
create or replace function public.session_spots_left(p_session_id uuid) returns int
language sql stable security definer set search_path = public, pg_temp as $$
  select case
           when s.status <> 'scheduled' then 0
           when not sv.is_group and public.session_seats_used(s.id) > 0 then 0
           else greatest(s.capacity - public.session_seats_used(s.id), 0)
         end
    from public.sessions s join public.services sv on sv.id = s.service_id
   where s.id = p_session_id;
$$;

create or replace function public._slot_spots(p_service_id uuid, p_starts timestamptz) returns int
language plpgsql stable security definer set search_path = public, pg_temp as $$
declare
  svc   public.services;
  sess  public.sessions;
  buf   int;
  v_end timestamptz;
  rng   tstzrange;
  free_count int;
begin
  select * into svc from public.services where id = p_service_id;
  select buffer_minutes into buf from public.business_settings where id;
  v_end := p_starts + make_interval(mins => svc.duration_minutes);
  rng   := tstzrange(p_starts, v_end + make_interval(mins => coalesce(buf, 0)));

  if exists (select 1 from public.blocked_slots b
             where b.resource_id is null
               and tstzrange(b.starts_at, b.ends_at) && tstzrange(p_starts, v_end)) then
    return 0;
  end if;

  if svc.is_group or svc.schedule_only then
    select * into sess from public.sessions s
     where s.service_id = svc.id and s.starts_at = p_starts and s.status = 'scheduled'
     order by public.session_spots_left(s.id) desc
     limit 1;
    if found then
      return public.session_spots_left(sess.id);
    end if;
  end if;
  if svc.schedule_only then return 0; end if;

  if svc.reformers_required > 0 then
    select count(*) into free_count
      from public.resources r
     where r.kind = 'reformer' and r.active
       and not exists (select 1 from public.session_resources sr where sr.resource_id = r.id and sr.during && rng)
       and not exists (select 1 from public.blocked_slots b where b.resource_id = r.id
                         and tstzrange(b.starts_at, b.ends_at) && rng);
    if free_count < svc.reformers_required then return 0; end if;
  end if;
  if svc.uses_mat_space then
    select count(*) into free_count
      from public.resources r
     where r.kind = 'mat_space' and r.active
       and not exists (select 1 from public.session_resources sr where sr.resource_id = r.id and sr.during && rng)
       and not exists (select 1 from public.blocked_slots b where b.resource_id = r.id
                         and tstzrange(b.starts_at, b.ends_at) && rng);
    if free_count < 1 then return 0; end if;
  end if;
  return svc.capacity;
end $$;

-- Availability: timetable services list their scheduled sessions; others
-- keep the opening-hours grid. Also returns session_id for the app.
drop function if exists public.get_available_slots(uuid, date, date);
create function public.get_available_slots(p_service_id uuid, p_from date, p_to date)
returns table (starts_at timestamptz, ends_at timestamptz, spots_left int, session_id uuid)
language plpgsql stable security definer set search_path = public, pg_temp as $$
declare
  st        public.business_settings;
  svc       public.services;
  v_min     timestamptz;
  v_max     timestamptz;
  step      int;
  d         date;
  r         record;
  m         int;
  m_end     int;
  v_start   timestamptz;
  spots     int;
  seen      timestamptz[] := '{}';
  own_rules boolean;
begin
  select * into svc from public.services where id = p_service_id and active;
  if not found then return; end if;
  select * into st from public.business_settings where id;
  if p_to < p_from then return; end if;
  if p_to - p_from > 62 then p_to := p_from + 62; end if;

  v_min := now() + make_interval(mins => st.min_advance_minutes);
  v_max := now() + make_interval(days => st.max_advance_days);

  -- 1. Scheduled sessions (the timetable)
  for r in
    select s.id, s.starts_at, s.ends_at from public.sessions s
     where s.service_id = svc.id and s.status = 'scheduled'
       and s.starts_at >= greatest(v_min, (p_from::timestamp at time zone st.timezone))
       and s.starts_at <= v_max
       and s.starts_at <  ((p_to + 1)::timestamp at time zone st.timezone)
     order by s.starts_at, public.session_spots_left(s.id) desc
  loop
    continue when exists (select 1 from public.blocked_slots b where b.resource_id is null
                          and tstzrange(b.starts_at, b.ends_at) && tstzrange(r.starts_at, r.ends_at));
    spots := public.session_spots_left(r.id);
    continue when spots = 0 and not svc.schedule_only;   -- open-booking services: hide full times
    continue when r.starts_at = any(seen);               -- one entry per time (best session first)
    seen := seen || r.starts_at;
    starts_at := r.starts_at; ends_at := r.ends_at; spots_left := spots; session_id := r.id;
    return next;   -- full sessions are returned too (spots_left = 0) so the app can offer the waitlist
  end loop;

  if svc.schedule_only then return; end if;

  -- 2. Open booking grid from opening hours (services not on the timetable)
  step := coalesce(st.slot_interval_minutes, svc.duration_minutes + st.buffer_minutes);
  own_rules := exists (select 1 from public.availability_rules where service_id = svc.id);
  for d in select g::date from generate_series(p_from::timestamp, p_to::timestamp, interval '1 day') g loop
    for r in
      select ar.start_time, ar.end_time from public.availability_rules ar
       where ar.weekday = extract(dow from d)::int
         and ((own_rules and ar.service_id = svc.id) or (not own_rules and ar.service_id is null))
       order by ar.start_time
    loop
      m     := extract(hour from r.start_time)::int * 60 + extract(minute from r.start_time)::int;
      m_end := extract(hour from r.end_time)::int * 60 + extract(minute from r.end_time)::int;
      while m + svc.duration_minutes <= m_end loop
        v_start := (d + make_interval(mins => m))::timestamp at time zone st.timezone;
        m := m + step;
        continue when v_start < v_min or v_start > v_max or v_start = any(seen);
        spots := public._slot_spots(svc.id, v_start);
        if spots > 0 then
          seen := seen || v_start;
          starts_at := v_start; ends_at := v_start + make_interval(mins => svc.duration_minutes);
          spots_left := spots; session_id := null;
          return next;
        end if;
      end loop;
    end loop;
  end loop;
end $$;

-- =====================================================================
-- Notifications (new types)
-- =====================================================================
create or replace function public._enqueue_booking_notifications(p_booking_id uuid, p_type public.notification_type)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare
  ns   public.notification_settings;
  b    record;
begin
  select * into ns from public.notification_settings where id;
  select bk.id, c.email, s.starts_at into b
    from public.bookings bk
    join public.clients c on c.id = bk.client_id
    join public.sessions s on s.id = bk.session_id
   where bk.id = p_booking_id;

  if (p_type = 'booking_confirmed'   and coalesce(ns.send_confirmations, true))
  or (p_type = 'booking_cancelled'   and coalesce(ns.send_cancellations, true))
  or (p_type = 'booking_rescheduled' and coalesce(ns.send_reschedules, true))
  or  p_type in ('waitlist_offer', 'waitlist_booked') then
    insert into public.notifications(type, booking_id, recipient_email) values (p_type, b.id, b.email);
  end if;

  if p_type in ('booking_confirmed','booking_rescheduled','waitlist_booked') and coalesce(ns.send_reminders, true) then
    insert into public.notifications(type, booking_id, recipient_email, scheduled_for)
    select 'booking_reminder', b.id, b.email,
           b.starts_at - make_interval(hours => coalesce(ns.reminder_hours_before, 24))
    where b.starts_at - make_interval(hours => coalesce(ns.reminder_hours_before, 24)) > now();
  end if;

  if p_type in ('booking_confirmed','waitlist_booked') and coalesce(ns.notify_owner_new, true) and ns.owner_email is not null then
    insert into public.notifications(type, booking_id, recipient_email) values ('owner_new_booking', b.id, ns.owner_email);
  end if;
end $$;

-- =====================================================================
-- Credits helpers
-- =====================================================================
-- Best usable credit for a client & service (soonest to expire first).
create or replace function public._find_credit(p_client_id uuid, p_service_id uuid, p_needed int, p_session_start timestamptz)
returns uuid language sql stable security definer set search_path = public, pg_temp as $$
  select cc.id from public.client_credits cc
   where cc.client_id = p_client_id
     and cc.expires_at > greatest(now(), p_session_start)
     and cc.credits_total - cc.credits_used >= p_needed
     and (cc.service_ids is null or p_service_id = any(cc.service_ids))
     and exists (select 1 from public.services sv where sv.id = p_service_id and sv.allow_credits)
   order by cc.expires_at, cc.created_at
   limit 1;
$$;

create or replace function public._client_for_user() returns public.clients
language plpgsql security definer set search_path = public, pg_temp as $$
declare c public.clients;
begin
  if auth.uid() is null then perform public._raise('SIGN_IN_REQUIRED', 'Please sign in first.'); end if;
  perform public.link_my_client();
  select * into c from public.clients where user_id = auth.uid();
  if not found then perform public._raise('SIGN_IN_REQUIRED', 'Please confirm your email address first.'); end if;
  return c;
end $$;

-- Gives back what a cancelled booking used: a credit, or reports card money to refund.
create or replace function public._settle_cancellation(p_booking_id uuid) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  bk public.bookings; paid int; refunded int;
begin
  select * into bk from public.bookings where id = p_booking_id;
  if bk.paid_with = 'credit' and bk.credit_id is not null then
    update public.client_credits set credits_used = greatest(credits_used - bk.party_size, 0) where id = bk.credit_id;
    return jsonb_build_object('credit_returned', bk.party_size, 'refund_cents', 0);
  end if;
  select coalesce(sum(amount_cents) filter (where kind = 'payment'), 0),
         coalesce(sum(amount_cents) filter (where kind = 'refund'), 0)
    into paid, refunded from public.payments where booking_id = p_booking_id and method = 'online';
  return jsonb_build_object('credit_returned', 0, 'refund_cents', greatest(paid - refunded, 0));
end $$;

-- =====================================================================
-- Holds & waitlist
-- =====================================================================
create or replace function public._promote_waitlist(p_session_id uuid) returns int
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  st     public.business_settings;
  sess   public.sessions;
  w      record;
  bk     public.bookings;
  cred   uuid;
  n      int := 0;
begin
  select * into st from public.business_settings where id;
  if not st.waitlist_enabled then return 0; end if;
  select * into sess from public.sessions where id = p_session_id;
  if sess.status <> 'scheduled' or sess.starts_at <= now() then return 0; end if;

  for w in select * from public.waitlist_entries
            where session_id = p_session_id and status = 'waiting'
            order by created_at for update loop
    exit when public.session_spots_left(p_session_id) <= 0;
    continue when w.party_size > public.session_spots_left(p_session_id);

    cred := public._find_credit(w.client_id, sess.service_id, w.party_size, sess.starts_at);
    bk := public._create_booking(sess.service_id, sess.starts_at, w.client_id, w.party_size, 'online',
                                 true, null, null, null, null, null);
    update public.bookings set admin_override = false, override_reason = null where id = bk.id;

    if cred is not null then
      update public.bookings set status = 'confirmed', paid_with = 'credit', credit_id = cred, payment_status = 'paid'
       where id = bk.id;
      update public.client_credits set credits_used = credits_used + w.party_size where id = cred;
      update public.waitlist_entries set status = 'booked', booking_id = bk.id where id = w.id;
      perform public._enqueue_booking_notifications(bk.id, 'waitlist_booked');
    else
      update public.bookings
         set status = 'pending', paid_with = 'card',
             hold_expires_at = least(now() + make_interval(hours => st.waitlist_offer_hours), sess.starts_at)
       where id = bk.id;
      update public.waitlist_entries
         set status = 'offered', booking_id = bk.id,
             offered_until = least(now() + make_interval(hours => st.waitlist_offer_hours), sess.starts_at)
       where id = w.id;
      perform public._enqueue_booking_notifications(bk.id, 'waitlist_offer');
    end if;
    n := n + 1;
  end loop;
  return n;
end $$;

-- Cancels unpaid bookings whose hold ran out, then refills from the waitlist.
create or replace function public._expire_holds() returns int
language plpgsql security definer set search_path = public, pg_temp as $$
declare b record; n int := 0;
begin
  for b in select id, session_id from public.bookings
            where status = 'pending' and hold_expires_at is not null and hold_expires_at <= now()
            for update skip locked loop
    update public.bookings set status = 'cancelled', cancelled_at = now(), cancel_reason = 'Payment not completed in time'
     where id = b.id;
    update public.notifications set status = 'skipped'
     where booking_id = b.id and status = 'pending';
    update public.waitlist_entries set status = 'expired' where booking_id = b.id and status = 'offered';
    perform public._release_session_if_empty(b.session_id);
    perform public._promote_waitlist(b.session_id);
    n := n + 1;
  end loop;
  return n;
end $$;

-- Cron / owner entry point.
create or replace function public.run_maintenance() returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare expired int; completed int;
begin
  if not public.is_admin() and coalesce(auth.role(), '') <> 'service_role' then
    perform public._raise('FORBIDDEN', 'Administrators only.');
  end if;
  perform public._studio_lock();
  expired := public._expire_holds();
  completed := public.complete_past_bookings();
  return jsonb_build_object('expired_holds', expired, 'completed', completed);
end $$;

-- =====================================================================
-- Core booking (timetable-aware)
-- =====================================================================
create or replace function public._create_booking(
  p_service_id      uuid,
  p_starts_at       timestamptz,
  p_client_id       uuid,
  p_party_size      int,
  p_source          text,
  p_override        boolean,
  p_override_reason text,
  p_instructor_id   uuid,
  p_client_notes    text,
  p_idempotency_key text,
  p_notify          public.notification_type
) returns public.bookings
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  st       public.business_settings;
  svc      public.services;
  sess     public.sessions;
  bk       public.bookings;
  v_local  date;
begin
  perform public._studio_lock();
  select * into st from public.business_settings where id;

  select * into svc from public.services where id = p_service_id;
  if not found or (not svc.active and not p_override) then
    perform public._raise('SERVICE_UNAVAILABLE', 'This service is not available for booking.');
  end if;
  if p_party_size is null or p_party_size < 1 or p_party_size > svc.capacity then
    perform public._raise('PARTY_SIZE_INVALID', format('This service allows 1 to %s people.', svc.capacity));
  end if;

  if not p_override then
    v_local := (p_starts_at at time zone st.timezone)::date;
    if not exists (select 1 from public.get_available_slots(svc.id, v_local, v_local) g
                    where g.starts_at = p_starts_at and g.spots_left >= p_party_size) then
      perform public._raise('SLOT_UNAVAILABLE', 'Sorry, that time is no longer available. Please choose another.');
    end if;
  end if;

  -- Prefer the session at this time with the most room (e.g. two timetabled
  -- Private sessions side by side on the two reformers).
  select * into sess from public.sessions s
   where s.service_id = svc.id and s.starts_at = p_starts_at and s.status = 'scheduled'
   order by public.session_spots_left(s.id) desc
   limit 1 for update;

  if sess.id is not null and public.session_spots_left(sess.id) < p_party_size then
    if svc.is_group and p_override then
      null;                                   -- owner may over-fill a group class
    elsif not svc.is_group and not svc.schedule_only then
      sess := null;                           -- open booking: try another reformer below
    else
      -- Private/Duet are physical: never over-filled, even by the owner.
      perform public._raise('SESSION_FULL', 'This session is full.');
    end if;
  end if;

  if sess.id is null then
    insert into public.sessions(service_id, instructor_id, starts_at, ends_at, capacity)
    values (svc.id, p_instructor_id, p_starts_at,
            p_starts_at + make_interval(mins => svc.duration_minutes), svc.capacity)
    returning * into sess;
    perform public._allocate_resources(sess.id);
  end if;

  if exists (select 1 from public.bookings where session_id = sess.id and client_id = p_client_id
              and (status = 'confirmed' or (status = 'pending' and (hold_expires_at is null or hold_expires_at > now())))) then
    perform public._raise('ALREADY_BOOKED', 'You already have a booking for this session.');
  end if;
  -- a stale, expired hold by the same client must not block the unique index
  update public.bookings set status = 'cancelled', cancelled_at = now(), cancel_reason = 'Payment not completed in time'
   where session_id = sess.id and client_id = p_client_id and status = 'pending' and hold_expires_at <= now();

  insert into public.bookings(reference, session_id, client_id, party_size, status, price_cents,
                              source, client_notes, admin_override, override_reason,
                              idempotency_key, created_by)
  values (public._gen_reference(), sess.id, p_client_id, p_party_size,
          case when st.auto_confirm or p_source = 'admin' then 'confirmed' else 'pending' end::public.booking_status,
          case when svc.is_group then svc.price_cents * p_party_size else svc.price_cents end,
          p_source, p_client_notes, coalesce(p_override, false),
          case when p_override then p_override_reason end, p_idempotency_key, auth.uid())
  returning * into bk;

  if bk.price_cents = 0 then
    update public.bookings set payment_status = 'paid', paid_with = 'free' where id = bk.id returning * into bk;
  end if;
  if p_notify is not null then
    perform public._enqueue_booking_notifications(bk.id, p_notify);
  end if;
  return bk;
end $$;

-- Public booking (guest or signed-in). With online payment on, the booking
-- is held as 'pending' until Stripe confirms the payment.
create or replace function public.book_session(
  p_service_id      uuid,
  p_starts_at       timestamptz,
  p_full_name       text,
  p_email           text,
  p_phone           text,
  p_party_size      int  default 1,
  p_idempotency_key text default null,
  p_client_notes    text default null
) returns jsonb
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  st        public.business_settings;
  uid       uuid := auth.uid();
  v_email   text;
  v_client  public.clients;
  existing  public.bookings;
  bk        public.bookings;
  token     text;
  pay       boolean;
begin
  p_full_name := btrim(coalesce(p_full_name, ''));
  p_phone     := nullif(btrim(coalesce(p_phone, '')), '');
  if char_length(p_full_name) < 2 or char_length(p_full_name) > 120 then
    perform public._raise('INVALID_NAME', 'Please enter your full name.');
  end if;
  perform public._studio_lock();
  perform public._expire_holds();
  select * into st from public.business_settings where id;
  if p_phone is not null and p_phone !~ '^[0-9+() .-]{6,40}$' then
    perform public._raise('INVALID_PHONE', 'Please enter a valid phone number.');
  end if;

  if p_idempotency_key is not null then
    select * into existing from public.bookings where idempotency_key = p_idempotency_key;
    if found then
      return jsonb_build_object('booking_id', existing.id, 'reference', existing.reference,
                                'status', existing.status, 'duplicate', true,
                                'requires_payment', existing.status = 'pending' and existing.paid_with = 'card',
                                'amount_cents', existing.price_cents, 'hold_expires_at', existing.hold_expires_at);
    end if;
  end if;

  if uid is not null then
    select email into v_email from auth.users where id = uid;
    select * into v_client from public.clients where user_id = uid;
    if not found then
      select * into v_client from public.clients where email = v_email and user_id is null;
      if found then
        update public.clients set user_id = uid where id = v_client.id returning * into v_client;
      else
        insert into public.clients(user_id, full_name, email, phone)
        values (uid, p_full_name, v_email, p_phone) returning * into v_client;
      end if;
    end if;
  else
    v_email := lower(btrim(coalesce(p_email, '')));
    if v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' or char_length(v_email) > 254 then
      perform public._raise('INVALID_EMAIL', 'Please enter a valid email address.');
    end if;
    select * into v_client from public.clients where email = v_email;
    if not found then
      insert into public.clients(full_name, email, phone)
      values (p_full_name, v_email, p_phone) returning * into v_client;
    end if;
  end if;

  bk := public._create_booking(p_service_id, p_starts_at, v_client.id, p_party_size, 'online',
                               false, null, null, left(p_client_notes, 1000), p_idempotency_key, null);
  pay := st.require_online_payment and bk.price_cents > 0;

  token := encode(extensions.gen_random_bytes(24), 'hex');
  if pay then
    update public.bookings
       set status = 'pending', paid_with = 'card', manage_token_hash = public._hash_token(token),
           hold_expires_at = now() + make_interval(mins => st.payment_hold_minutes)
     where id = bk.id returning * into bk;
  else
    update public.bookings
       set paid_with = coalesce(paid_with, 'studio'), manage_token_hash = public._hash_token(token)
     where id = bk.id returning * into bk;
    perform public._enqueue_booking_notifications(bk.id, 'booking_confirmed');
  end if;

  return jsonb_build_object('booking_id', bk.id, 'reference', bk.reference, 'status', bk.status,
                            'manage_token', token, 'duplicate', false, 'requires_payment', pay,
                            'amount_cents', bk.price_cents, 'hold_expires_at', bk.hold_expires_at);
end $$;

-- Signed-in client books using a pack/membership credit. Confirmed instantly.
create or replace function public.book_with_credit(
  p_service_id uuid, p_starts_at timestamptz, p_party_size int default 1, p_idempotency_key text default null
) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  c    public.clients;
  bk   public.bookings;
  cred uuid;
  ex   public.bookings;
begin
  perform public._studio_lock();
  c := public._client_for_user();
  if p_idempotency_key is not null then
    select * into ex from public.bookings where idempotency_key = p_idempotency_key and client_id = c.id;
    if found then
      return jsonb_build_object('booking_id', ex.id, 'reference', ex.reference, 'status', ex.status, 'duplicate', true);
    end if;
  end if;
  perform public._expire_holds();
  cred := public._find_credit(c.id, p_service_id, coalesce(p_party_size, 1), p_starts_at);
  if cred is null then
    perform public._raise('NO_CREDITS', 'You have no valid credits for this session.');
  end if;
  bk := public._create_booking(p_service_id, p_starts_at, c.id, p_party_size, 'online',
                               false, null, null, null, p_idempotency_key, null);
  update public.bookings set status = 'confirmed', paid_with = 'credit', credit_id = cred, payment_status = 'paid'
   where id = bk.id returning * into bk;
  update public.client_credits set credits_used = credits_used + bk.party_size where id = cred;
  perform public._enqueue_booking_notifications(bk.id, 'booking_confirmed');
  return jsonb_build_object('booking_id', bk.id, 'reference', bk.reference, 'status', bk.status, 'duplicate', false);
end $$;

-- =====================================================================
-- Stripe webhook entry points (service role only — never callable by users)
-- =====================================================================
create or replace function public._require_service_role() returns void
language plpgsql set search_path = public, pg_temp as $$
begin
  if coalesce(auth.role(), '') <> 'service_role' then
    perform public._raise('FORBIDDEN', 'Server only.');
  end if;
end $$;

-- Card payment for a booking succeeded. Idempotent per provider reference.
-- If the hold had already expired and the place was given away, returns
-- action = 'refund' so the server refunds the card automatically.
create or replace function public.confirm_booking_payment(p_booking_id uuid, p_amount_cents int, p_provider_ref text)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare bk public.bookings;
begin
  perform public._require_service_role();
  perform public._studio_lock();
  if exists (select 1 from public.payments where provider = 'stripe' and provider_ref = p_provider_ref and kind = 'payment') then
    select * into bk from public.bookings where id = p_booking_id;
    return jsonb_build_object('action', 'none', 'status', bk.status, 'reference', bk.reference);
  end if;
  select * into bk from public.bookings where id = p_booking_id for update;
  if not found then perform public._raise('NOT_FOUND', 'Booking not found.'); end if;

  insert into public.payments(booking_id, kind, amount_cents, method, provider, provider_ref, note)
  values (bk.id, 'payment', p_amount_cents, 'online', 'stripe', p_provider_ref, 'Card payment');

  if bk.status = 'pending' and (bk.hold_expires_at is null or bk.hold_expires_at > now()
                                or public.session_spots_left(bk.session_id) >= bk.party_size) then
    update public.bookings set status = 'confirmed', hold_expires_at = null, paid_with = 'card' where id = bk.id;
    update public.waitlist_entries set status = 'booked' where booking_id = bk.id and status = 'offered';
    perform public._enqueue_booking_notifications(bk.id, 'booking_confirmed');
    return jsonb_build_object('action', 'confirmed', 'reference', bk.reference);
  end if;
  return jsonb_build_object('action', 'refund', 'reference', bk.reference, 'amount_cents', p_amount_cents);
end $$;

create or replace function public.record_card_refund(p_booking_id uuid, p_amount_cents int, p_provider_ref text)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
begin
  perform public._require_service_role();
  insert into public.payments(booking_id, kind, amount_cents, method, provider, provider_ref, note)
  values (p_booking_id, 'refund', p_amount_cents, 'online', 'stripe', p_provider_ref, 'Automatic card refund')
  on conflict do nothing;
end $$;

-- Pack purchase or membership renewal paid. Idempotent per provider reference.
create or replace function public.grant_package_credits(p_client_id uuid, p_package_id uuid, p_amount_cents int, p_provider_ref text)
returns uuid language plpgsql security definer set search_path = public, pg_temp as $$
declare pk public.packages; cid uuid;
begin
  perform public._require_service_role();
  select id into cid from public.client_credits where provider_ref = p_provider_ref;
  if found then return cid; end if;
  select * into pk from public.packages where id = p_package_id;
  if not found then perform public._raise('NOT_FOUND', 'Package not found.'); end if;
  insert into public.client_credits(client_id, package_id, label, credits_total, service_ids, expires_at, source, provider_ref)
  values (p_client_id, pk.id, pk.name, pk.credits, pk.service_ids, now() + make_interval(days => pk.validity_days),
          case when pk.kind = 'membership' then 'membership' else 'purchase' end, p_provider_ref)
  returning id into cid;
  if p_amount_cents > 0 then
    insert into public.payments(client_credit_id, kind, amount_cents, method, provider, provider_ref, note)
    values (cid, 'payment', p_amount_cents, 'online', 'stripe', p_provider_ref, pk.name);
  end if;
  insert into public.notifications(type, recipient_email)
  select 'credits_added', c.email from public.clients c where c.id = p_client_id;
  return cid;
end $$;

-- Owner gives credits manually (e.g. paid in cash, goodwill).
create or replace function public.admin_grant_credits(p_client_id uuid, p_credits int, p_label text,
                                                      p_validity_days int default 90, p_service_ids uuid[] default null)
returns uuid language plpgsql security definer set search_path = public, pg_temp as $$
declare cid uuid;
begin
  if not public.is_admin() then perform public._raise('FORBIDDEN', 'Administrators only.'); end if;
  if p_credits is null or p_credits < 1 then perform public._raise('INVALID_AMOUNT', 'Give at least one credit.'); end if;
  insert into public.client_credits(client_id, label, credits_total, service_ids, expires_at, source, created_by)
  values (p_client_id, coalesce(nullif(btrim(p_label), ''), 'Credits from studio'), p_credits, p_service_ids,
          now() + make_interval(days => coalesce(p_validity_days, 90)), 'admin', auth.uid())
  returning id into cid;
  return cid;
end $$;

-- =====================================================================
-- Cancellation (returns credits; reports card refunds for the server to do)
-- =====================================================================
create or replace function public.cancel_booking(
  p_booking_id   uuid default null,
  p_reference    text default null,
  p_manage_token text default null,
  p_reason       text default null
) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  st      public.business_settings;
  bk      public.bookings;
  sess    public.sessions;
  admin   boolean := public.is_admin();
  allowed boolean := false;
  settle  jsonb;
begin
  perform public._studio_lock();
  select * into st from public.business_settings where id;

  if p_booking_id is not null then
    select * into bk from public.bookings where id = p_booking_id for update;
  elsif p_reference is not null then
    select * into bk from public.bookings where reference = upper(btrim(p_reference)) for update;
  end if;
  if bk.id is null then perform public._raise('NOT_FOUND', 'Booking not found.'); end if;

  if admin then
    allowed := true;
  elsif auth.uid() is not null and exists (select 1 from public.clients c
                                             where c.id = bk.client_id and c.user_id = auth.uid()) then
    allowed := true;
  elsif p_manage_token is not null and bk.manage_token_hash = public._hash_token(p_manage_token) then
    allowed := true;
  end if;
  if not allowed then perform public._raise('NOT_FOUND', 'Booking not found.'); end if;

  if bk.status not in ('pending','confirmed') then
    perform public._raise('NOT_CANCELLABLE', 'This booking can no longer be cancelled.');
  end if;

  select * into sess from public.sessions where id = bk.session_id;
  -- unpaid holds can always be released; paid bookings follow the window
  if not admin and bk.status = 'confirmed'
     and sess.starts_at - make_interval(hours => st.cancellation_window_hours) < now() then
    perform public._raise('LATE_CANCELLATION',
      format('Bookings can only be cancelled online up to %s hours before the session. Please contact the studio.',
             st.cancellation_window_hours));
  end if;

  update public.bookings
     set status = 'cancelled', cancelled_at = now(), cancelled_by = auth.uid(),
         cancel_reason = left(p_reason, 500), hold_expires_at = null
   where id = bk.id;
  update public.notifications set status = 'skipped'
   where booking_id = bk.id and status = 'pending';
  update public.waitlist_entries set status = 'cancelled' where booking_id = bk.id and status in ('offered','waiting');

  settle := public._settle_cancellation(bk.id);
  perform public._release_session_if_empty(bk.session_id);
  if bk.status = 'confirmed' then
    perform public._enqueue_booking_notifications(bk.id, 'booking_cancelled');
  end if;
  perform public._promote_waitlist(bk.session_id);
  return jsonb_build_object('booking_id', bk.id, 'reference', bk.reference, 'status', 'cancelled') || settle;
end $$;

drop function if exists public.admin_cancel_session(uuid, text, boolean);
create function public.admin_cancel_session(p_session_id uuid, p_reason text default null,
                                                       p_send_email boolean default true)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare b record; n int := 0; refunds jsonb := '[]';
begin
  if not public.is_admin() then perform public._raise('FORBIDDEN', 'Administrators only.'); end if;
  perform public._studio_lock();
  for b in select id, status from public.bookings where session_id = p_session_id and status in ('pending','confirmed') for update loop
    update public.bookings set status = 'cancelled', cancelled_at = now(), cancelled_by = auth.uid(),
           cancel_reason = coalesce(left(p_reason, 500), 'Session cancelled by studio'), hold_expires_at = null
     where id = b.id;
    update public.notifications set status = 'skipped' where booking_id = b.id and status = 'pending';
    refunds := refunds || (jsonb_build_object('booking_id', b.id) || public._settle_cancellation(b.id));
    if p_send_email and b.status = 'confirmed' then perform public._enqueue_booking_notifications(b.id, 'booking_cancelled'); end if;
    n := n + 1;
  end loop;
  update public.waitlist_entries set status = 'cancelled' where session_id = p_session_id and status in ('waiting','offered');
  update public.sessions set status = 'cancelled' where id = p_session_id;
  delete from public.session_resources where session_id = p_session_id;
  return jsonb_build_object('cancelled', n, 'settlements', refunds);
end $$;


-- Reschedule keeps how the booking was paid (credit or card).
create or replace function public.reschedule_booking(
  p_booking_id      uuid,
  p_new_starts_at   timestamptz,
  p_new_service_id  uuid    default null,
  p_override        boolean default false,
  p_override_reason text    default null,
  p_send_email      boolean default true
) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  old_bk public.bookings;
  new_bk public.bookings;
  svc_id uuid;
begin
  if not public.is_admin() then perform public._raise('FORBIDDEN', 'Administrators only.'); end if;
  perform public._studio_lock();
  select * into old_bk from public.bookings where id = p_booking_id for update;
  if not found then perform public._raise('NOT_FOUND', 'Booking not found.'); end if;
  if old_bk.status not in ('pending','confirmed') then
    perform public._raise('NOT_RESCHEDULABLE', 'Only active bookings can be rescheduled.');
  end if;
  select service_id into svc_id from public.sessions where id = old_bk.session_id;
  svc_id := coalesce(p_new_service_id, svc_id);

  update public.bookings
     set status = 'cancelled', cancelled_at = now(), cancelled_by = auth.uid(),
         cancel_reason = 'Rescheduled', idempotency_key = null, hold_expires_at = null
   where id = old_bk.id;
  update public.notifications set status = 'skipped'
   where booking_id = old_bk.id and status = 'pending';
  perform public._release_session_if_empty(old_bk.session_id);

  new_bk := public._create_booking(svc_id, p_new_starts_at, old_bk.client_id, old_bk.party_size, 'admin',
                                   p_override, p_override_reason, null, old_bk.client_notes, null,
                                   case when p_send_email then 'booking_rescheduled'::public.notification_type end);

  update public.bookings
     set rescheduled_from = old_bk.id, price_cents = old_bk.price_cents,
         manage_token_hash = old_bk.manage_token_hash,
         paid_with = old_bk.paid_with, credit_id = old_bk.credit_id
   where id = new_bk.id;
  update public.payments set booking_id = new_bk.id where booking_id = old_bk.id;
  perform public._recompute_payment_status(new_bk.id);
  perform public._recompute_payment_status(old_bk.id);
  if old_bk.paid_with = 'credit' then
    update public.bookings set payment_status = 'paid' where id = new_bk.id;
  end if;
  update public.reschedule_requests set status = 'approved', resolved_by = auth.uid(), resolved_at = now()
   where booking_id = old_bk.id and status = 'open';
  perform public._promote_waitlist(old_bk.session_id);

  return jsonb_build_object('booking_id', new_bk.id, 'reference', new_bk.reference,
                            'previous_booking_id', old_bk.id);
end $$;

-- =====================================================================
-- Waitlist API
-- =====================================================================
create or replace function public.join_waitlist(p_session_id uuid, p_party_size int default 1)
returns uuid language plpgsql security definer set search_path = public, pg_temp as $$
declare c public.clients; sess public.sessions; svc public.services; wid uuid;
begin
  perform public._studio_lock();
  c := public._client_for_user();
  select * into sess from public.sessions where id = p_session_id;
  if not found or sess.status <> 'scheduled' or sess.starts_at <= now() then
    perform public._raise('NOT_FOUND', 'Session not found.');
  end if;
  if not (select waitlist_enabled from public.business_settings where id) then
    perform public._raise('WAITLIST_DISABLED', 'The waitlist is not available.');
  end if;
  select * into svc from public.services where id = sess.service_id;
  if p_party_size < 1 or p_party_size > svc.capacity then
    perform public._raise('PARTY_SIZE_INVALID', format('This service allows 1 to %s people.', svc.capacity));
  end if;
  if public.session_spots_left(p_session_id) >= p_party_size then
    perform public._raise('SPOTS_AVAILABLE', 'There are places available — you can book directly.');
  end if;
  if exists (select 1 from public.bookings where session_id = p_session_id and client_id = c.id and status in ('pending','confirmed')) then
    perform public._raise('ALREADY_BOOKED', 'You already have a booking for this session.');
  end if;
  insert into public.waitlist_entries(session_id, client_id, party_size)
  values (p_session_id, c.id, p_party_size)
  on conflict do nothing
  returning id into wid;
  if wid is null then perform public._raise('ALREADY_WAITLISTED', 'You are already on the waitlist.'); end if;
  return wid;
end $$;

create or replace function public.leave_waitlist(p_entry_id uuid) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  update public.waitlist_entries w set status = 'cancelled'
   where w.id = p_entry_id and w.status = 'waiting'
     and (public.is_admin() or exists (select 1 from public.clients c where c.id = w.client_id and c.user_id = auth.uid()));
  if not found then perform public._raise('NOT_FOUND', 'Waitlist entry not found.'); end if;
end $$;

-- =====================================================================
-- RLS & grants for new tables / functions
-- =====================================================================
alter table public.packages         enable row level security;
alter table public.client_credits   enable row level security;
alter table public.waitlist_entries enable row level security;

create policy "public read packages"  on public.packages for select using (active or public.is_admin());
create policy "admin write packages"  on public.packages for all using (public.is_admin()) with check (public.is_admin());
create policy "own credits read"      on public.client_credits for select using (
  public.is_admin() or exists (select 1 from public.clients c where c.id = client_credits.client_id and c.user_id = auth.uid()));
create policy "own waitlist read"     on public.waitlist_entries for select using (
  public.is_admin() or exists (select 1 from public.clients c where c.id = waitlist_entries.client_id and c.user_id = auth.uid()));

revoke all on public.packages, public.client_credits, public.waitlist_entries from anon, authenticated;
grant select on public.packages to anon, authenticated;
grant insert, update, delete on public.packages to authenticated;          -- admin via RLS
grant select on public.client_credits, public.waitlist_entries to authenticated;

revoke execute on all functions in schema public from public, anon, authenticated;
grant execute on function public.is_admin()                                   to anon, authenticated;
grant execute on function public.get_available_slots(uuid, date, date)        to anon, authenticated;
grant execute on function public.book_session(uuid, timestamptz, text, text, text, int, text, text) to anon, authenticated;
grant execute on function public.cancel_booking(uuid, text, text, text)        to anon, authenticated;
grant execute on function public.get_booking_by_token(text, text)             to anon, authenticated;
grant execute on function public.book_with_credit(uuid, timestamptz, int, text) to authenticated;
grant execute on function public.join_waitlist(uuid, int)                     to authenticated;
grant execute on function public.leave_waitlist(uuid)                         to authenticated;
grant execute on function public.request_reschedule(uuid, text)               to authenticated;
grant execute on function public.link_my_client()                             to authenticated;
grant execute on function public.admin_create_booking(uuid, timestamptz, uuid, int, boolean, text, uuid, boolean) to authenticated;
grant execute on function public.reschedule_booking(uuid, timestamptz, uuid, boolean, text, boolean) to authenticated;
grant execute on function public.admin_update_session(uuid, uuid, int, boolean, text) to authenticated;
grant execute on function public.admin_cancel_session(uuid, text, boolean)    to authenticated;
grant execute on function public.create_recurring_series(uuid, int, time, date, date, uuid, int) to authenticated;
grant execute on function public.record_payment(uuid, int, public.payment_method, public.payment_kind, text, timestamptz) to authenticated;
grant execute on function public.admin_grant_credits(uuid, int, text, int, uuid[]) to authenticated;
grant execute on function public.complete_past_bookings()                     to authenticated, service_role;
grant execute on function public.run_maintenance()                            to authenticated, service_role;
grant execute on function public.confirm_booking_payment(uuid, int, text)     to service_role;
grant execute on function public.record_card_refund(uuid, int, text)          to service_role;
grant execute on function public.grant_package_credits(uuid, uuid, int, text) to service_role;

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    alter publication supabase_realtime add table public.waitlist_entries;
  end if;
end $$;
