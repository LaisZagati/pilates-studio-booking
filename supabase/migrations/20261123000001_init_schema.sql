-- =====================================================================
-- Pilates Studio Booking System — Phase 1: schema, booking engine, RLS
-- Target: Supabase (PostgreSQL 15+)
-- =====================================================================

create schema if not exists extensions;
create extension if not exists btree_gist with schema extensions;
create extension if not exists citext     with schema extensions;
create extension if not exists pgcrypto   with schema extensions;

-- ---------------------------------------------------------------------
-- Enums
-- ---------------------------------------------------------------------
create type public.booking_status      as enum ('pending','confirmed','cancelled','completed','no_show');
create type public.session_status      as enum ('scheduled','cancelled','completed');
create type public.payment_status      as enum ('unpaid','partial','paid','refunded');
create type public.payment_method      as enum ('cash','card_terminal','bank_transfer','online','other');
create type public.payment_kind        as enum ('payment','refund');
create type public.resource_kind       as enum ('reformer','mat_space');
create type public.block_kind          as enum ('block','holiday','appointment');
create type public.notification_type   as enum ('booking_confirmed','booking_cancelled','booking_rescheduled','booking_reminder','owner_new_booking');
create type public.notification_status as enum ('pending','sent','failed','skipped');
create type public.request_status      as enum ('open','approved','declined');

-- ---------------------------------------------------------------------
-- Generic updated_at trigger
-- ---------------------------------------------------------------------
create or replace function public.tg_set_updated_at() returns trigger
language plpgsql set search_path = public, pg_temp as $$
begin
  new.updated_at := now();
  return new;
end $$;

-- ---------------------------------------------------------------------
-- Business settings (single row)
-- ---------------------------------------------------------------------
create table public.business_settings (
  id                        boolean primary key default true check (id),
  studio_name               text not null default 'Pilates Studio',
  tagline                   text,
  logo_url                  text,
  address                   text,
  contact_email             text,
  contact_phone             text,
  instagram_url             text,
  timezone                  text not null default 'Europe/Madrid',
  currency                  text not null default 'EUR',
  min_advance_minutes       int  not null default 120  check (min_advance_minutes >= 0),
  max_advance_days          int  not null default 60   check (max_advance_days between 1 and 365),
  buffer_minutes            int  not null default 0    check (buffer_minutes between 0 and 120),
  slot_interval_minutes     int           default null check (slot_interval_minutes is null or slot_interval_minutes between 5 and 240),
  cancellation_window_hours int  not null default 24   check (cancellation_window_hours between 0 and 720),
  auto_confirm              boolean not null default true,
  booking_policy            text,
  cancellation_policy       text,
  updated_at                timestamptz not null default now()
);
create trigger business_settings_updated before update on public.business_settings
  for each row execute function public.tg_set_updated_at();

create table public.notification_settings (
  id                     boolean primary key default true check (id),
  owner_email            text,
  send_confirmations     boolean not null default true,
  send_cancellations     boolean not null default true,
  send_reschedules       boolean not null default true,
  send_reminders         boolean not null default true,
  reminder_hours_before  int     not null default 24 check (reminder_hours_before between 1 and 168),
  notify_owner_new       boolean not null default true,
  from_name              text,
  updated_at             timestamptz not null default now()
);
create trigger notification_settings_updated before update on public.notification_settings
  for each row execute function public.tg_set_updated_at();

-- ---------------------------------------------------------------------
-- Users, administrators, clients
-- ---------------------------------------------------------------------
create table public.profiles (
  id          uuid primary key references auth.users(id) on delete cascade,
  full_name   text check (char_length(full_name) <= 120),
  phone       text check (char_length(phone) <= 40),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create trigger profiles_updated before update on public.profiles
  for each row execute function public.tg_set_updated_at();

create table public.admins (
  user_id     uuid primary key references auth.users(id) on delete cascade,
  created_at  timestamptz not null default now()
);

create table public.clients (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid unique references auth.users(id) on delete set null,
  full_name   text not null check (char_length(full_name) between 1 and 120),
  email       extensions.citext not null unique check (char_length(email) <= 254 and email ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
  phone       text check (char_length(phone) <= 40),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create trigger clients_updated before update on public.clients
  for each row execute function public.tg_set_updated_at();

-- Private notes about clients: admin only (kept out of the clients row so
-- clients can never read them).
create table public.client_notes (
  id          uuid primary key default gen_random_uuid(),
  client_id   uuid not null references public.clients(id) on delete cascade,
  body        text not null check (char_length(body) between 1 and 4000),
  created_by  uuid references auth.users(id) on delete set null,
  created_at  timestamptz not null default now()
);
create index client_notes_client_idx on public.client_notes(client_id);

-- ---------------------------------------------------------------------
-- Instructors
-- ---------------------------------------------------------------------
create table public.instructors (
  id          uuid primary key default gen_random_uuid(),
  full_name   text not null check (char_length(full_name) between 1 and 120),
  email       text,
  phone       text,
  bio         text,
  photo_url   text,
  active      boolean not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create trigger instructors_updated before update on public.instructors
  for each row execute function public.tg_set_updated_at();

create table public.instructor_availability (
  id             uuid primary key default gen_random_uuid(),
  instructor_id  uuid not null references public.instructors(id) on delete cascade,
  weekday        smallint not null check (weekday between 0 and 6), -- 0 = Sunday
  start_time     time not null,
  end_time       time not null,
  check (end_time > start_time)
);
create index instructor_availability_idx on public.instructor_availability(instructor_id, weekday);

-- ---------------------------------------------------------------------
-- Services and equipment
-- ---------------------------------------------------------------------
create table public.services (
  id                  uuid primary key default gen_random_uuid(),
  slug                text not null unique check (slug ~ '^[a-z0-9-]+$'),
  name                text not null check (char_length(name) between 1 and 80),
  short_description   text,
  description         text,
  duration_minutes    int  not null check (duration_minutes between 10 and 480),
  price_cents         int  not null check (price_cents >= 0),
  capacity            int  not null check (capacity between 1 and 50),
  reformers_required  int  not null default 0 check (reformers_required >= 0),
  uses_mat_space      boolean not null default false,
  -- group = several separate clients can join one session (Mat).
  -- not group = one booking takes the whole session (Private, Duet).
  is_group            boolean not null default false,
  image_url           text,
  sort_order          int not null default 0,
  active              boolean not null default true,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);
create trigger services_updated before update on public.services
  for each row execute function public.tg_set_updated_at();

-- Each physical piece of equipment / space is a row. Add a third reformer by
-- inserting a row — no code change needed.
create table public.resources (
  id          uuid primary key default gen_random_uuid(),
  name        text not null unique,
  kind        public.resource_kind not null,
  active      boolean not null default true,
  created_at  timestamptz not null default now()
);

-- Opening hours / bookable windows. service_id null = applies to all
-- services. If a service has any rules of its own, only those are used.
create table public.availability_rules (
  id          uuid primary key default gen_random_uuid(),
  service_id  uuid references public.services(id) on delete cascade,
  weekday     smallint not null check (weekday between 0 and 6), -- 0 = Sunday
  start_time  time not null,
  end_time    time not null,
  check (end_time > start_time)
);
create index availability_rules_idx on public.availability_rules(weekday, service_id);
create index availability_rules_service_idx on public.availability_rules(service_id);

create table public.blocked_slots (
  id           uuid primary key default gen_random_uuid(),
  kind         public.block_kind not null default 'block',
  starts_at    timestamptz not null,
  ends_at      timestamptz not null,
  resource_id  uuid references public.resources(id) on delete cascade, -- null = whole studio
  title        text,
  reason       text,
  created_by   uuid references auth.users(id) on delete set null,
  created_at   timestamptz not null default now(),
  check (ends_at > starts_at)
);
create index blocked_slots_range_idx on public.blocked_slots using gist (tstzrange(starts_at, ends_at));
create index blocked_slots_resource_idx on public.blocked_slots(resource_id);

-- ---------------------------------------------------------------------
-- Sessions (a time slot of a service) and their equipment reservations
-- ---------------------------------------------------------------------
create table public.recurring_series (
  id             uuid primary key default gen_random_uuid(),
  service_id     uuid not null references public.services(id),
  instructor_id  uuid references public.instructors(id) on delete set null,
  weekday        smallint not null check (weekday between 0 and 6),
  start_time     time not null,
  starts_on      date not null,
  ends_on        date not null,
  capacity       int check (capacity is null or capacity between 1 and 50),
  created_by     uuid references auth.users(id) on delete set null,
  created_at     timestamptz not null default now(),
  check (ends_on >= starts_on and ends_on <= starts_on + 366)
);

create table public.sessions (
  id             uuid primary key default gen_random_uuid(),
  service_id     uuid not null references public.services(id),
  instructor_id  uuid references public.instructors(id) on delete set null,
  series_id      uuid references public.recurring_series(id) on delete set null,
  starts_at      timestamptz not null,
  ends_at        timestamptz not null,
  capacity       int not null check (capacity between 1 and 50),
  status         public.session_status not null default 'scheduled',
  notes          text,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  check (ends_at > starts_at),
  -- An instructor can never teach two overlapping sessions.
  constraint sessions_instructor_no_overlap exclude using gist (
    instructor_id with =,
    tstzrange(starts_at, ends_at) with &&
  ) where (status = 'scheduled' and instructor_id is not null)
);
create index sessions_starts_idx on public.sessions(starts_at);
create index sessions_service_starts_idx on public.sessions(service_id, starts_at) where status = 'scheduled';
create index sessions_series_idx on public.sessions(series_id);
create trigger sessions_updated before update on public.sessions
  for each row execute function public.tg_set_updated_at();

-- THE equipment guarantee: a resource (e.g. "Reformer 1") can only be held
-- by one session at any instant (buffer included). This is enforced by the
-- database itself, so no code path — and no race — can ever put more
-- clients on reformers than physically exist.
create table public.session_resources (
  session_id   uuid not null references public.sessions(id) on delete cascade,
  resource_id  uuid not null references public.resources(id),
  during       tstzrange not null,
  primary key (session_id, resource_id),
  constraint session_resources_no_overlap exclude using gist (
    resource_id with =,
    during with &&
  )
);

-- ---------------------------------------------------------------------
-- Bookings
-- ---------------------------------------------------------------------
create table public.bookings (
  id                 uuid primary key default gen_random_uuid(),
  reference          text not null unique,
  session_id         uuid not null references public.sessions(id),
  client_id          uuid not null references public.clients(id),
  party_size         int  not null default 1 check (party_size between 1 and 50),
  status             public.booking_status not null default 'confirmed',
  price_cents        int  not null check (price_cents >= 0),
  payment_status     public.payment_status not null default 'unpaid',
  source             text not null default 'online' check (source in ('online','admin')),
  client_notes       text check (char_length(client_notes) <= 1000),
  admin_override     boolean not null default false,
  override_reason    text,
  idempotency_key    text unique check (char_length(idempotency_key) <= 100),
  manage_token_hash  text,
  rescheduled_from   uuid references public.bookings(id),
  cancelled_at       timestamptz,
  cancel_reason      text,
  cancelled_by       uuid references auth.users(id) on delete set null,
  created_by         uuid references auth.users(id) on delete set null,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);
create index bookings_session_idx on public.bookings(session_id);
create index bookings_client_idx  on public.bookings(client_id, created_at desc);
create index bookings_status_idx  on public.bookings(status);
-- A client can't hold two active bookings in the same session.
create unique index bookings_one_active_per_client_session
  on public.bookings(session_id, client_id) where status in ('pending','confirmed');
create trigger bookings_updated before update on public.bookings
  for each row execute function public.tg_set_updated_at();

create table public.reschedule_requests (
  id           uuid primary key default gen_random_uuid(),
  booking_id   uuid not null references public.bookings(id) on delete cascade,
  message      text check (char_length(message) <= 1000),
  status       public.request_status not null default 'open',
  requested_by uuid references auth.users(id) on delete set null,
  resolved_by  uuid references auth.users(id) on delete set null,
  created_at   timestamptz not null default now(),
  resolved_at  timestamptz
);
create index reschedule_requests_open_idx on public.reschedule_requests(status, created_at);
create index reschedule_requests_booking_idx on public.reschedule_requests(booking_id);

-- ---------------------------------------------------------------------
-- Payments (manual ledger; online provider can write here later)
-- ---------------------------------------------------------------------
create table public.payments (
  id            uuid primary key default gen_random_uuid(),
  booking_id    uuid not null references public.bookings(id) on delete cascade,
  kind          public.payment_kind not null default 'payment',
  amount_cents  int not null check (amount_cents > 0),
  method        public.payment_method not null,
  note          text,
  provider      text,              -- future: 'stripe' etc.
  provider_ref  text,              -- future: provider payment id
  paid_at       timestamptz not null default now(),
  recorded_by   uuid references auth.users(id) on delete set null,
  created_at    timestamptz not null default now()
);
create index payments_booking_idx on public.payments(booking_id);
create index payments_paid_at_idx on public.payments(paid_at);

-- ---------------------------------------------------------------------
-- Notifications outbox (processed server-side by the email worker)
-- ---------------------------------------------------------------------
create table public.notifications (
  id               uuid primary key default gen_random_uuid(),
  type             public.notification_type not null,
  booking_id       uuid references public.bookings(id) on delete cascade,
  recipient_email  text not null,
  status           public.notification_status not null default 'pending',
  scheduled_for    timestamptz not null default now(),
  attempts         int not null default 0,
  last_error       text,
  sent_at          timestamptz,
  created_at       timestamptz not null default now()
);
create index notifications_due_idx on public.notifications(scheduled_for) where status = 'pending';
create index notifications_booking_idx on public.notifications(booking_id);

-- =====================================================================
-- Helper functions
-- =====================================================================
create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
  select exists (select 1 from public.admins where user_id = auth.uid());
$$;

create or replace function public._raise(p_code text, p_message text) returns void
language plpgsql set search_path = public, pg_temp as $$
begin
  raise exception '%', p_code using errcode = 'P0001', hint = p_message;
end $$;

create or replace function public._gen_reference() returns text
language plpgsql volatile set search_path = public, pg_temp as $$
declare
  alphabet constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  ref text;
begin
  loop
    ref := 'PS-';
    for i in 1..6 loop
      ref := ref || substr(alphabet, 1 + floor(random() * length(alphabet))::int, 1);
    end loop;
    exit when not exists (select 1 from public.bookings where reference = ref);
  end loop;
  return ref;
end $$;

create or replace function public._hash_token(p_token text) returns text
language sql immutable set search_path = public, extensions, pg_temp as $$
  select encode(extensions.digest(p_token, 'sha256'), 'hex');
$$;

-- Serialises every write to the booking calendar. A boutique studio has a
-- low write rate, so a single transaction-scoped lock is simple and safe.
create or replace function public._studio_lock() returns void
language sql set search_path = public, pg_temp as $$ select pg_advisory_xact_lock(727274001); $$;

create or replace function public.session_seats_used(p_session_id uuid) returns int
language sql stable security definer set search_path = public, pg_temp as $$
  select coalesce(sum(party_size), 0)::int
  from public.bookings
  where session_id = p_session_id and status in ('pending','confirmed','completed');
$$;

-- How many people could still book this service at this start time,
-- considering equipment, blocks and existing sessions. 0 = unavailable.
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

  -- whole-studio block (holiday, closure, owner appointment)
  if exists (select 1 from public.blocked_slots b
             where b.resource_id is null
               and tstzrange(b.starts_at, b.ends_at) && tstzrange(p_starts, v_end)) then
    return 0;
  end if;

  -- an existing group session at exactly this time can be joined
  if svc.is_group then
    select * into sess from public.sessions s
     where s.service_id = svc.id and s.starts_at = p_starts and s.status = 'scheduled'
     limit 1;
    if found then
      return greatest(sess.capacity - public.session_seats_used(sess.id), 0);
    end if;
  end if;

  -- otherwise a new session would be needed: is the equipment free?
  if svc.reformers_required > 0 then
    select count(*) into free_count
      from public.resources r
     where r.kind = 'reformer' and r.active
       and not exists (select 1 from public.session_resources sr
                        where sr.resource_id = r.id and sr.during && rng)
       and not exists (select 1 from public.blocked_slots b
                        where b.resource_id = r.id
                          and tstzrange(b.starts_at, b.ends_at) && rng);
    if free_count < svc.reformers_required then return 0; end if;
  end if;

  if svc.uses_mat_space then
    select count(*) into free_count
      from public.resources r
     where r.kind = 'mat_space' and r.active
       and not exists (select 1 from public.session_resources sr
                        where sr.resource_id = r.id and sr.during && rng)
       and not exists (select 1 from public.blocked_slots b
                        where b.resource_id = r.id
                          and tstzrange(b.starts_at, b.ends_at) && rng);
    if free_count < 1 then return 0; end if;
  end if;

  return svc.capacity;
end $$;

-- =====================================================================
-- Public availability (safe for anonymous visitors: times + spots only)
-- =====================================================================
create or replace function public.get_available_slots(p_service_id uuid, p_from date, p_to date)
returns table (starts_at timestamptz, ends_at timestamptz, spots_left int)
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
  step  := coalesce(st.slot_interval_minutes, svc.duration_minutes + st.buffer_minutes);
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
          starts_at := v_start;
          ends_at := v_start + make_interval(mins => svc.duration_minutes);
          spots_left := spots;
          return next;
        end if;
      end loop;
    end loop;
  end loop;

  -- Scheduled group classes (e.g. recurring Mat) that sit off the grid
  if svc.is_group then
    for r in
      select s.id, s.starts_at, s.ends_at, s.capacity from public.sessions s
       where s.service_id = svc.id and s.status = 'scheduled'
         and s.starts_at >= greatest(v_min, (p_from::timestamp at time zone st.timezone))
         and s.starts_at <  least(v_max, ((p_to + 1)::timestamp at time zone st.timezone))
       order by s.starts_at
    loop
      continue when r.starts_at = any(seen);
      continue when exists (select 1 from public.blocked_slots b where b.resource_id is null
                            and tstzrange(b.starts_at, b.ends_at) && tstzrange(r.starts_at, r.ends_at));
      spots := r.capacity - public.session_seats_used(r.id);
      if spots > 0 then
        starts_at := r.starts_at; ends_at := r.ends_at; spots_left := spots;
        return next;
      end if;
    end loop;
  end if;
end $$;

-- =====================================================================
-- Notification outbox helpers
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
  or (p_type = 'booking_rescheduled' and coalesce(ns.send_reschedules, true)) then
    insert into public.notifications(type, booking_id, recipient_email) values (p_type, b.id, b.email);
  end if;

  if p_type in ('booking_confirmed','booking_rescheduled') then
    if coalesce(ns.send_reminders, true) then
      insert into public.notifications(type, booking_id, recipient_email, scheduled_for)
      select 'booking_reminder', b.id, b.email,
             b.starts_at - make_interval(hours => coalesce(ns.reminder_hours_before, 24))
      where b.starts_at - make_interval(hours => coalesce(ns.reminder_hours_before, 24)) > now();
    end if;
  end if;

  if p_type = 'booking_confirmed' and coalesce(ns.notify_owner_new, true) and ns.owner_email is not null then
    insert into public.notifications(type, booking_id, recipient_email) values ('owner_new_booking', b.id, ns.owner_email);
  end if;
end $$;

-- =====================================================================
-- Core booking engine (internal; called by the public API functions)
-- =====================================================================
create or replace function public._allocate_resources(p_session_id uuid) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  sess  public.sessions;
  svc   public.services;
  buf   int;
  rng   tstzrange;
  got   int;
begin
  select * into sess from public.sessions where id = p_session_id;
  select * into svc  from public.services where id = sess.service_id;
  select buffer_minutes into buf from public.business_settings where id;
  rng := tstzrange(sess.starts_at, sess.ends_at + make_interval(mins => coalesce(buf, 0)));

  if svc.reformers_required > 0 then
    insert into public.session_resources(session_id, resource_id, during)
    select sess.id, r.id, rng
      from public.resources r
     where r.kind = 'reformer' and r.active
       and not exists (select 1 from public.session_resources sr where sr.resource_id = r.id and sr.during && rng)
       and not exists (select 1 from public.blocked_slots b where b.resource_id = r.id
                         and tstzrange(b.starts_at, b.ends_at) && rng)
     order by r.name
     limit svc.reformers_required;
    get diagnostics got = row_count;
    if got < svc.reformers_required then
      perform public._raise('NO_EQUIPMENT', 'Not enough reformers are free at this time.');
    end if;
  end if;

  if svc.uses_mat_space then
    insert into public.session_resources(session_id, resource_id, during)
    select sess.id, r.id, rng
      from public.resources r
     where r.kind = 'mat_space' and r.active
       and not exists (select 1 from public.session_resources sr where sr.resource_id = r.id and sr.during && rng)
       and not exists (select 1 from public.blocked_slots b where b.resource_id = r.id
                         and tstzrange(b.starts_at, b.ends_at) && rng)
     order by r.name
     limit 1;
    get diagnostics got = row_count;
    if got < 1 then
      perform public._raise('NO_EQUIPMENT', 'The mat studio is already in use at this time.');
    end if;
  end if;
end $$;

-- Releases an on-demand session (and its equipment) once nobody is booked.
create or replace function public._release_session_if_empty(p_session_id uuid) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if not exists (select 1 from public.bookings
                  where session_id = p_session_id and status in ('pending','confirmed')) then
    update public.sessions set status = 'cancelled'
     where id = p_session_id and series_id is null and status = 'scheduled';
    if found then
      delete from public.session_resources where session_id = p_session_id;
    end if;
  end if;
end $$;

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
  used     int;
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

  -- Normal rules: the start time must be a currently offered slot with room.
  -- (Owner override skips opening hours, advance windows and blocks — but
  -- NEVER the physical equipment limit, which the database enforces.)
  if not p_override then
    v_local := (p_starts_at at time zone st.timezone)::date;
    if not exists (select 1 from public.get_available_slots(svc.id, v_local, v_local) g
                    where g.starts_at = p_starts_at and g.spots_left >= p_party_size) then
      perform public._raise('SLOT_UNAVAILABLE', 'Sorry, that time is no longer available. Please choose another.');
    end if;
  end if;

  if svc.is_group then
    select * into sess from public.sessions s
     where s.service_id = svc.id and s.starts_at = p_starts_at and s.status = 'scheduled'
     limit 1 for update;
  end if;

  if sess.id is null then
    insert into public.sessions(service_id, instructor_id, starts_at, ends_at, capacity)
    values (svc.id, p_instructor_id, p_starts_at,
            p_starts_at + make_interval(mins => svc.duration_minutes), svc.capacity)
    returning * into sess;
    perform public._allocate_resources(sess.id);
  else
    used := public.session_seats_used(sess.id);
    if used + p_party_size > sess.capacity and not p_override then
      perform public._raise('SESSION_FULL', 'This class is full.');
    end if;
  end if;

  if exists (select 1 from public.bookings where session_id = sess.id and client_id = p_client_id
              and status in ('pending','confirmed')) then
    perform public._raise('ALREADY_BOOKED', 'You already have a booking for this session.');
  end if;

  insert into public.bookings(reference, session_id, client_id, party_size, status, price_cents,
                              source, client_notes, admin_override, override_reason,
                              idempotency_key, created_by)
  values (public._gen_reference(), sess.id, p_client_id, p_party_size,
          case when st.auto_confirm or p_source = 'admin' then 'confirmed' else 'pending' end::public.booking_status,
          -- group classes are priced per person; Private/Duet per session
          case when svc.is_group then svc.price_cents * p_party_size else svc.price_cents end,
          p_source, p_client_notes, coalesce(p_override, false),
          case when p_override then p_override_reason end, p_idempotency_key, auth.uid())
  returning * into bk;

  if bk.price_cents = 0 then
    update public.bookings set payment_status = 'paid' where id = bk.id returning * into bk;
  end if;

  if p_notify is not null then
    perform public._enqueue_booking_notifications(bk.id, p_notify);
  end if;
  return bk;
end $$;

-- =====================================================================
-- PUBLIC API (callable from the app through Supabase RPC)
-- =====================================================================

-- Client / guest booking. Returns the reference and, once, a private
-- manage token for guests (stored only as a hash).
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
  uid       uuid := auth.uid();
  v_email   text;
  v_client  public.clients;
  existing  public.bookings;
  bk        public.bookings;
  token     text;
begin
  p_full_name := btrim(coalesce(p_full_name, ''));
  p_phone     := nullif(btrim(coalesce(p_phone, '')), '');
  if char_length(p_full_name) < 2 or char_length(p_full_name) > 120 then
    perform public._raise('INVALID_NAME', 'Please enter your full name.');
  end if;
  -- Take the studio lock first so duplicate submissions and the guest
  -- client upsert are serialised too.
  perform public._studio_lock();
  if p_phone is not null and p_phone !~ '^[0-9+() .-]{6,40}$' then
    perform public._raise('INVALID_PHONE', 'Please enter a valid phone number.');
  end if;

  -- Duplicate submission (double tap, retry): return the original booking.
  if p_idempotency_key is not null then
    select * into existing from public.bookings where idempotency_key = p_idempotency_key;
    if found then
      return jsonb_build_object('booking_id', existing.id, 'reference', existing.reference,
                                'status', existing.status, 'duplicate', true);
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
                               false, null, null, left(p_client_notes, 1000), p_idempotency_key,
                               'booking_confirmed');

  token := encode(extensions.gen_random_bytes(24), 'hex');
  update public.bookings set manage_token_hash = public._hash_token(token) where id = bk.id;

  return jsonb_build_object('booking_id', bk.id, 'reference', bk.reference, 'status', bk.status,
                            'manage_token', token, 'duplicate', false);
end $$;

-- Owner creates a booking. p_override lets the owner book outside normal
-- rules (opening hours, notice period, blocks, full Mat class).
create or replace function public.admin_create_booking(
  p_service_id      uuid,
  p_starts_at       timestamptz,
  p_client_id       uuid,
  p_party_size      int     default 1,
  p_override        boolean default false,
  p_override_reason text    default null,
  p_instructor_id   uuid    default null,
  p_send_email      boolean default true
) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare bk public.bookings;
begin
  if not public.is_admin() then perform public._raise('FORBIDDEN', 'Administrators only.'); end if;
  if not exists (select 1 from public.clients where id = p_client_id) then
    perform public._raise('CLIENT_NOT_FOUND', 'Client not found.');
  end if;
  if p_override and coalesce(btrim(p_override_reason), '') = '' then
    perform public._raise('OVERRIDE_REASON_REQUIRED', 'Please give a reason for overriding the booking rules.');
  end if;
  bk := public._create_booking(p_service_id, p_starts_at, p_client_id, p_party_size, 'admin',
                               p_override, p_override_reason, p_instructor_id, null, null,
                               case when p_send_email then 'booking_confirmed'::public.notification_type end);
  return jsonb_build_object('booking_id', bk.id, 'reference', bk.reference, 'status', bk.status);
end $$;

-- Cancel: admin any time; signed-in client their own; guest with reference +
-- manage token. Clients/guests must respect the cancellation window.
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
  if not admin and sess.starts_at - make_interval(hours => st.cancellation_window_hours) < now() then
    perform public._raise('LATE_CANCELLATION',
      format('Bookings can only be cancelled online up to %s hours before the session. Please contact the studio.',
             st.cancellation_window_hours));
  end if;

  update public.bookings
     set status = 'cancelled', cancelled_at = now(), cancelled_by = auth.uid(),
         cancel_reason = left(p_reason, 500)
   where id = bk.id;
  update public.notifications set status = 'skipped'
   where booking_id = bk.id and type = 'booking_reminder' and status = 'pending';

  perform public._release_session_if_empty(bk.session_id);
  perform public._enqueue_booking_notifications(bk.id, 'booking_cancelled');
  return jsonb_build_object('booking_id', bk.id, 'reference', bk.reference, 'status', 'cancelled');
end $$;

-- Owner reschedules (atomically: frees the old slot, books the new one,
-- moves payments). If the new slot fails, nothing changes.
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
         cancel_reason = 'Rescheduled', idempotency_key = null
   where id = old_bk.id;
  update public.notifications set status = 'skipped'
   where booking_id = old_bk.id and type = 'booking_reminder' and status = 'pending';
  perform public._release_session_if_empty(old_bk.session_id);

  new_bk := public._create_booking(svc_id, p_new_starts_at, old_bk.client_id, old_bk.party_size, 'admin',
                                   p_override, p_override_reason, null, old_bk.client_notes, null,
                                   case when p_send_email then 'booking_rescheduled'::public.notification_type end);

  update public.bookings
     set rescheduled_from = old_bk.id, price_cents = old_bk.price_cents,
         manage_token_hash = old_bk.manage_token_hash
   where id = new_bk.id;
  update public.payments set booking_id = new_bk.id where booking_id = old_bk.id;
  perform public._recompute_payment_status(new_bk.id);
  perform public._recompute_payment_status(old_bk.id);
  update public.reschedule_requests set status = 'approved', resolved_by = auth.uid(), resolved_at = now()
   where booking_id = old_bk.id and status = 'open';

  return jsonb_build_object('booking_id', new_bk.id, 'reference', new_bk.reference,
                            'previous_booking_id', old_bk.id);
end $$;

-- Client asks the studio to move a booking (owner then reschedules).
create or replace function public.request_reschedule(p_booking_id uuid, p_message text)
returns uuid language plpgsql security definer set search_path = public, pg_temp as $$
declare rid uuid;
begin
  if auth.uid() is null or not exists (
       select 1 from public.bookings b join public.clients c on c.id = b.client_id
        where b.id = p_booking_id and c.user_id = auth.uid() and b.status in ('pending','confirmed')) then
    perform public._raise('NOT_FOUND', 'Booking not found.');
  end if;
  if exists (select 1 from public.reschedule_requests where booking_id = p_booking_id and status = 'open') then
    perform public._raise('REQUEST_EXISTS', 'You already have an open reschedule request for this booking.');
  end if;
  insert into public.reschedule_requests(booking_id, message, requested_by)
  values (p_booking_id, left(p_message, 1000), auth.uid()) returning id into rid;
  return rid;
end $$;

-- Owner edits a session: instructor, capacity (can't go below booked seats).
create or replace function public.admin_update_session(
  p_session_id uuid, p_instructor_id uuid default null, p_capacity int default null,
  p_clear_instructor boolean default false, p_notes text default null
) returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare used int;
begin
  if not public.is_admin() then perform public._raise('FORBIDDEN', 'Administrators only.'); end if;
  perform public._studio_lock();
  if p_capacity is not null then
    used := public.session_seats_used(p_session_id);
    if p_capacity < used then
      perform public._raise('CAPACITY_BELOW_BOOKED', format('%s spots are already booked.', used));
    end if;
  end if;
  update public.sessions
     set capacity      = coalesce(p_capacity, capacity),
         instructor_id = case when p_clear_instructor then null else coalesce(p_instructor_id, instructor_id) end,
         notes         = coalesce(p_notes, notes)
   where id = p_session_id;
  if not found then perform public._raise('NOT_FOUND', 'Session not found.'); end if;
end $$;

-- Owner cancels a whole session (all its bookings).
create or replace function public.admin_cancel_session(p_session_id uuid, p_reason text default null,
                                                       p_send_email boolean default true)
returns int language plpgsql security definer set search_path = public, pg_temp as $$
declare b record; n int := 0;
begin
  if not public.is_admin() then perform public._raise('FORBIDDEN', 'Administrators only.'); end if;
  perform public._studio_lock();
  for b in select id from public.bookings where session_id = p_session_id and status in ('pending','confirmed') for update loop
    update public.bookings set status = 'cancelled', cancelled_at = now(), cancelled_by = auth.uid(),
           cancel_reason = coalesce(left(p_reason, 500), 'Session cancelled by studio')
     where id = b.id;
    update public.notifications set status = 'skipped'
     where booking_id = b.id and type = 'booking_reminder' and status = 'pending';
    if p_send_email then perform public._enqueue_booking_notifications(b.id, 'booking_cancelled'); end if;
    n := n + 1;
  end loop;
  update public.sessions set status = 'cancelled' where id = p_session_id;
  delete from public.session_resources where session_id = p_session_id;
  return n;
end $$;

-- Owner creates a recurring class (e.g. Mat every Tuesday 19:00).
-- Dates that clash with equipment, blocks or instructors are skipped and
-- returned so the owner can see them.
create or replace function public.create_recurring_series(
  p_service_id uuid, p_weekday int, p_start_time time, p_starts_on date, p_ends_on date,
  p_instructor_id uuid default null, p_capacity int default null
) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare
  st      public.business_settings;
  svc     public.services;
  sid     uuid;
  d       date;
  v_start timestamptz;
  sess_id uuid;
  created int := 0;
  skipped jsonb := '[]';
begin
  if not public.is_admin() then perform public._raise('FORBIDDEN', 'Administrators only.'); end if;
  perform public._studio_lock();
  select * into st from public.business_settings where id;
  select * into svc from public.services where id = p_service_id;
  if not found then perform public._raise('NOT_FOUND', 'Service not found.'); end if;

  insert into public.recurring_series(service_id, instructor_id, weekday, start_time, starts_on, ends_on, capacity, created_by)
  values (p_service_id, p_instructor_id, p_weekday, p_start_time, p_starts_on, p_ends_on, p_capacity, auth.uid())
  returning id into sid;

  for d in select g::date from generate_series(p_starts_on::timestamp, p_ends_on::timestamp, interval '1 day') g
            where extract(dow from g)::int = p_weekday loop
    v_start := (d + p_start_time)::timestamp at time zone st.timezone;
    begin
      if exists (select 1 from public.blocked_slots b where b.resource_id is null
                  and tstzrange(b.starts_at, b.ends_at) && tstzrange(v_start, v_start + make_interval(mins => svc.duration_minutes))) then
        perform public._raise('BLOCKED', 'Studio closed');
      end if;
      insert into public.sessions(service_id, instructor_id, series_id, starts_at, ends_at, capacity)
      values (svc.id, p_instructor_id, sid, v_start, v_start + make_interval(mins => svc.duration_minutes),
              coalesce(p_capacity, svc.capacity))
      returning id into sess_id;
      perform public._allocate_resources(sess_id);
      created := created + 1;
    exception when others then
      skipped := skipped || jsonb_build_object('date', d, 'reason', coalesce(nullif(sqlerrm, ''), 'conflict'));
    end;
  end loop;
  return jsonb_build_object('series_id', sid, 'created', created, 'skipped', skipped);
end $$;

-- Links a signed-in, email-verified user to their earlier guest bookings.
create or replace function public.link_my_client() returns uuid
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  uid uuid := auth.uid();
  u   record;
  cid uuid;
begin
  if uid is null then return null; end if;
  select id into cid from public.clients where user_id = uid;
  if found then return cid; end if;
  select email, email_confirmed_at, raw_user_meta_data into u from auth.users where id = uid;
  if u.email_confirmed_at is null then return null; end if;
  update public.clients set user_id = uid where email = u.email and user_id is null returning id into cid;
  if cid is null then
    insert into public.clients(user_id, full_name, email, phone)
    values (uid, coalesce(nullif(u.raw_user_meta_data->>'full_name', ''), split_part(u.email, '@', 1)),
            u.email, nullif(u.raw_user_meta_data->>'phone', ''))
    on conflict (email) do nothing
    returning id into cid;
  end if;
  return cid;
end $$;

-- =====================================================================
-- Payments
-- =====================================================================
create or replace function public._recompute_payment_status(p_booking_id uuid) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  paid int; refunded int; price int; net int; ps public.payment_status;
begin
  select price_cents into price from public.bookings where id = p_booking_id;
  if price is null then return; end if;
  select coalesce(sum(amount_cents) filter (where kind = 'payment'), 0),
         coalesce(sum(amount_cents) filter (where kind = 'refund'), 0)
    into paid, refunded
    from public.payments where booking_id = p_booking_id;
  net := paid - refunded;
  ps := case
          when refunded > 0 and net <= 0 then 'refunded'
          when price = 0 or net >= price then 'paid'
          when net > 0 then 'partial'
          else 'unpaid'
        end;
  update public.bookings set payment_status = ps where id = p_booking_id and payment_status <> ps;
end $$;

create or replace function public.tg_payments_recompute() returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  perform public._recompute_payment_status(coalesce(new.booking_id, old.booking_id));
  if tg_op = 'UPDATE' and old.booking_id <> new.booking_id then
    perform public._recompute_payment_status(old.booking_id);
  end if;
  return null;
end $$;
create trigger payments_recompute after insert or update or delete on public.payments
  for each row execute function public.tg_payments_recompute();

create or replace function public.record_payment(
  p_booking_id uuid, p_amount_cents int, p_method public.payment_method,
  p_kind public.payment_kind default 'payment', p_note text default null, p_paid_at timestamptz default now()
) returns uuid language plpgsql security definer set search_path = public, pg_temp as $$
declare pid uuid; paid int; refunded int;
begin
  if not public.is_admin() then perform public._raise('FORBIDDEN', 'Administrators only.'); end if;
  if p_method = 'online' then
    perform public._raise('ONLINE_NOT_ENABLED', 'Online payments are not enabled yet.');
  end if;
  if p_amount_cents is null or p_amount_cents <= 0 then
    perform public._raise('INVALID_AMOUNT', 'Amount must be greater than zero.');
  end if;
  if p_kind = 'refund' then
    select coalesce(sum(amount_cents) filter (where kind = 'payment'), 0),
           coalesce(sum(amount_cents) filter (where kind = 'refund'), 0)
      into paid, refunded from public.payments where booking_id = p_booking_id;
    if refunded + p_amount_cents > paid then
      perform public._raise('REFUND_TOO_LARGE', 'A refund cannot be larger than the amount paid.');
    end if;
  end if;
  insert into public.payments(booking_id, kind, amount_cents, method, note, paid_at, recorded_by)
  values (p_booking_id, p_kind, p_amount_cents, p_method, left(p_note, 500), coalesce(p_paid_at, now()), auth.uid())
  returning id into pid;
  return pid;
end $$;

-- Marks finished sessions/bookings as completed (run by cron or the owner).
create or replace function public.complete_past_bookings() returns int
language plpgsql security definer set search_path = public, pg_temp as $$
declare n int;
begin
  if not public.is_admin() and coalesce(auth.role(), '') <> 'service_role' then
    perform public._raise('FORBIDDEN', 'Administrators only.');
  end if;
  update public.bookings b set status = 'completed'
    from public.sessions s
   where s.id = b.session_id and s.ends_at < now() and b.status = 'confirmed';
  get diagnostics n = row_count;
  update public.sessions set status = 'completed' where ends_at < now() and status = 'scheduled';
  return n;
end $$;

-- =====================================================================
-- New auth user -> profile
-- =====================================================================
create or replace function public.tg_handle_new_user() returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  insert into public.profiles(id, full_name, phone)
  values (new.id, left(new.raw_user_meta_data->>'full_name', 120), left(new.raw_user_meta_data->>'phone', 40))
  on conflict (id) do nothing;
  return new;
end $$;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.tg_handle_new_user();

-- =====================================================================
-- Admin calendar view (RLS of the caller applies: security_invoker)
-- =====================================================================
create view public.admin_calendar with (security_invoker = true) as
select b.id            as booking_id,
       b.reference,
       b.status        as booking_status,
       b.payment_status,
       b.party_size,
       b.price_cents,
       b.source,
       b.admin_override,
       s.id            as session_id,
       s.starts_at,
       s.ends_at,
       s.capacity,
       s.status        as session_status,
       sv.id           as service_id,
       sv.name         as service_name,
       sv.slug         as service_slug,
       c.id            as client_id,
       c.full_name     as client_name,
       c.email         as client_email,
       c.phone         as client_phone,
       i.full_name     as instructor_name
  from public.bookings b
  join public.sessions s  on s.id = b.session_id
  join public.services sv on sv.id = s.service_id
  join public.clients c   on c.id = b.client_id
  left join public.instructors i on i.id = s.instructor_id;

-- =====================================================================
-- Row Level Security
-- =====================================================================
alter table public.business_settings       enable row level security;
alter table public.notification_settings   enable row level security;
alter table public.profiles                enable row level security;
alter table public.admins                  enable row level security;
alter table public.clients                 enable row level security;
alter table public.client_notes            enable row level security;
alter table public.instructors             enable row level security;
alter table public.instructor_availability enable row level security;
alter table public.services                enable row level security;
alter table public.resources               enable row level security;
alter table public.availability_rules      enable row level security;
alter table public.blocked_slots           enable row level security;
alter table public.recurring_series        enable row level security;
alter table public.sessions                enable row level security;
alter table public.session_resources       enable row level security;
alter table public.bookings                enable row level security;
alter table public.reschedule_requests     enable row level security;
alter table public.payments                enable row level security;
alter table public.notifications           enable row level security;

-- Public catalogue
create policy "public read settings"     on public.business_settings for select using (true);
create policy "admin update settings"    on public.business_settings for update using (public.is_admin()) with check (public.is_admin());
create policy "public read services"     on public.services for select using (active or public.is_admin());
create policy "admin write services"     on public.services for all using (public.is_admin()) with check (public.is_admin());
create policy "public read resources"    on public.resources for select using (true);
create policy "admin write resources"    on public.resources for all using (public.is_admin()) with check (public.is_admin());
create policy "public read rules"        on public.availability_rules for select using (true);
create policy "admin write rules"        on public.availability_rules for all using (public.is_admin()) with check (public.is_admin());
create policy "public read instructors"  on public.instructors for select using (active or public.is_admin());
create policy "admin write instructors"  on public.instructors for all using (public.is_admin()) with check (public.is_admin());
create policy "public read instr avail"  on public.instructor_availability for select using (true);
create policy "admin write instr avail"  on public.instructor_availability for all using (public.is_admin()) with check (public.is_admin());

-- Admin-only
create policy "admin notification settings" on public.notification_settings for all using (public.is_admin()) with check (public.is_admin());
create policy "admin blocked slots"      on public.blocked_slots    for all using (public.is_admin()) with check (public.is_admin());
create policy "admin recurring"          on public.recurring_series for all using (public.is_admin()) with check (public.is_admin());
create policy "admin session resources"  on public.session_resources for select using (public.is_admin());
create policy "admin client notes"       on public.client_notes     for all using (public.is_admin()) with check (public.is_admin());
create policy "admin notifications"      on public.notifications    for select using (public.is_admin());

-- Own records
create policy "own admin row"            on public.admins   for select using (user_id = auth.uid() or public.is_admin());
create policy "own profile read"         on public.profiles for select using (id = auth.uid() or public.is_admin());
create policy "own profile update"       on public.profiles for update using (id = auth.uid()) with check (id = auth.uid());

create policy "own client read"          on public.clients for select using (user_id = auth.uid() or public.is_admin());
create policy "own client update"        on public.clients for update using (user_id = auth.uid() or public.is_admin())
                                                       with check (user_id = auth.uid() or public.is_admin());
create policy "admin client insert"      on public.clients for insert with check (public.is_admin());
create policy "admin client delete"      on public.clients for delete using (public.is_admin());

create policy "own bookings read" on public.bookings for select using (
  public.is_admin() or exists (select 1 from public.clients c where c.id = bookings.client_id and c.user_id = auth.uid()));
create policy "admin bookings notes" on public.bookings for update using (public.is_admin()) with check (public.is_admin());

create policy "own sessions read" on public.sessions for select using (
  public.is_admin() or exists (select 1 from public.bookings b join public.clients c on c.id = b.client_id
                                where b.session_id = sessions.id and c.user_id = auth.uid()));

create policy "own payments read" on public.payments for select using (
  public.is_admin() or exists (select 1 from public.bookings b join public.clients c on c.id = b.client_id
                                where b.id = payments.booking_id and c.user_id = auth.uid()));

create policy "own reschedule read" on public.reschedule_requests for select using (
  public.is_admin() or requested_by = auth.uid());
create policy "admin reschedule update" on public.reschedule_requests for update using (public.is_admin()) with check (public.is_admin());

-- =====================================================================
-- Privileges: table writes for booking-engine tables go ONLY through the
-- functions above. Column grants limit what clients can edit on themselves.
-- =====================================================================
revoke all on all tables in schema public from anon, authenticated;

grant select on public.business_settings, public.services, public.resources, public.availability_rules,
                public.instructors, public.instructor_availability to anon, authenticated;

grant select on public.profiles, public.admins, public.clients, public.client_notes, public.blocked_slots,
                public.recurring_series, public.sessions, public.session_resources, public.bookings,
                public.reschedule_requests, public.payments, public.notifications,
                public.notification_settings, public.admin_calendar to authenticated;

grant update (full_name, phone) on public.profiles to authenticated;
grant update (full_name, phone) on public.clients  to authenticated;
grant insert, delete            on public.clients  to authenticated;           -- admin via RLS
grant update (client_notes)     on public.bookings to authenticated;           -- admin via RLS
grant update (status, resolved_by, resolved_at) on public.reschedule_requests to authenticated; -- admin via RLS
grant update on public.business_settings, public.notification_settings to authenticated; -- admin via RLS
grant insert, update, delete on public.services, public.resources, public.availability_rules,
                                public.instructors, public.instructor_availability,
                                public.blocked_slots, public.client_notes to authenticated; -- admin via RLS

-- Functions: nothing is callable unless granted here.
revoke execute on all functions in schema public from public, anon, authenticated;
grant execute on function public.is_admin()                                   to anon, authenticated;
grant execute on function public.get_available_slots(uuid, date, date)        to anon, authenticated;
grant execute on function public.book_session(uuid, timestamptz, text, text, text, int, text, text) to anon, authenticated;
grant execute on function public.cancel_booking(uuid, text, text, text)        to anon, authenticated;
grant execute on function public.request_reschedule(uuid, text)               to authenticated;
grant execute on function public.link_my_client()                             to authenticated;
grant execute on function public.admin_create_booking(uuid, timestamptz, uuid, int, boolean, text, uuid, boolean) to authenticated;
grant execute on function public.reschedule_booking(uuid, timestamptz, uuid, boolean, text, boolean) to authenticated;
grant execute on function public.admin_update_session(uuid, uuid, int, boolean, text) to authenticated;
grant execute on function public.admin_cancel_session(uuid, text, boolean)    to authenticated;
grant execute on function public.create_recurring_series(uuid, int, time, date, date, uuid, int) to authenticated;
grant execute on function public.record_payment(uuid, int, public.payment_method, public.payment_kind, text, timestamptz) to authenticated;
grant execute on function public.complete_past_bookings()                     to authenticated, service_role;
grant execute on function public.session_seats_used(uuid)                     to authenticated;

-- Realtime for the admin dashboard (Supabase only)
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    alter publication supabase_realtime add table public.bookings, public.sessions, public.blocked_slots;
  end if;
end $$;
