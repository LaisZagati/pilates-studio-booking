-- Phase 2/3: homepage content fields + guest booking lookup by reference + token.
alter table public.business_settings
  add column if not exists hero_image_url text,
  add column if not exists about_text     text,
  add column if not exists maps_url       text;

-- Guests open their booking from the emailed link (reference + private token).
-- Returns only that booking's display details, and only with the right token.
create or replace function public.get_booking_by_token(p_reference text, p_token text)
returns table (
  reference     text,
  status        public.booking_status,
  service_name  text,
  starts_at     timestamptz,
  ends_at       timestamptz,
  party_size    int,
  price_cents   int,
  client_name   text,
  can_cancel    boolean
)
language sql stable security definer set search_path = public, pg_temp as $$
  select b.reference, b.status, sv.name, s.starts_at, s.ends_at, b.party_size, b.price_cents, c.full_name,
         (b.status in ('pending','confirmed')
          and s.starts_at - make_interval(hours => st.cancellation_window_hours) > now())
    from public.bookings b
    join public.sessions s  on s.id = b.session_id
    join public.services sv on sv.id = s.service_id
    join public.clients c   on c.id = b.client_id
    cross join public.business_settings st
   where b.reference = upper(btrim(p_reference))
     and p_token is not null and char_length(p_token) between 16 and 128
     and b.manage_token_hash = public._hash_token(p_token);
$$;
revoke execute on function public.get_booking_by_token(text, text) from public;
grant execute on function public.get_booking_by_token(text, text) to anon, authenticated;

update public.business_settings
   set about_text = coalesce(about_text,
     'A calm, light-filled boutique studio with two reformers and a small mat room. Every session is taught in a small group or one-to-one, so your instructor can focus on your alignment, breath and progress.')
 where id;
