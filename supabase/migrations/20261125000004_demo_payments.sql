-- =====================================================================
-- Demo payment mode: the full pay-to-book flow without a payment provider.
-- Demo payments are recorded honestly (provider 'demo', method 'other',
-- note "Demo payment — no money taken") and can only happen while
-- business_settings.payment_mode = 'demo'. Switching to 'stripe' turns
-- every demo function off.
-- =====================================================================

alter table public.business_settings
  add column if not exists payment_mode text not null default 'demo'
    check (payment_mode in ('demo','stripe','studio'));

update public.business_settings set payment_hold_minutes = 30 where id;   -- Stripe Checkout's minimum

create or replace function public._require_demo_mode() returns void
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if (select payment_mode from public.business_settings where id) <> 'demo' then
    perform public._raise('DEMO_DISABLED', 'Demo payments are switched off.');
  end if;
end $$;

-- Booking lookup for the payment page: by guest token, or by the signed-in owner.
create or replace function public.get_payment_details(p_reference text, p_token text default null)
returns table (
  reference text, status public.booking_status, payment_status public.payment_status,
  service_name text, starts_at timestamptz, ends_at timestamptz, party_size int,
  price_cents int, hold_expires_at timestamptz, paid_with public.paid_with, payment_mode text
)
language sql stable security definer set search_path = public, pg_temp as $$
  select b.reference, b.status, b.payment_status, sv.name, s.starts_at, s.ends_at, b.party_size,
         b.price_cents, b.hold_expires_at, b.paid_with, st.payment_mode
    from public.bookings b
    join public.sessions s  on s.id = b.session_id
    join public.services sv on sv.id = s.service_id
    join public.clients c   on c.id = b.client_id
    cross join public.business_settings st
   where b.reference = upper(btrim(p_reference))
     and ((p_token is not null and char_length(p_token) between 16 and 128 and b.manage_token_hash = public._hash_token(p_token))
          or (auth.uid() is not null and c.user_id = auth.uid()));
$$;

-- "Pay" on the demo payment page. p_succeed = false simulates a declined card (nothing changes).
create or replace function public.demo_pay_booking(p_reference text, p_token text default null, p_succeed boolean default true)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare bk public.bookings; ok boolean;
begin
  perform public._require_demo_mode();
  perform public._studio_lock();
  select b.* into bk from public.bookings b join public.clients c on c.id = b.client_id
   where b.reference = upper(btrim(p_reference))
     and ((p_token is not null and b.manage_token_hash = public._hash_token(p_token))
          or (auth.uid() is not null and c.user_id = auth.uid()))
   for update of b;
  if bk.id is null then perform public._raise('NOT_FOUND', 'Booking not found.'); end if;
  if bk.status = 'confirmed' and bk.payment_status = 'paid' then
    return jsonb_build_object('status', 'confirmed', 'reference', bk.reference, 'already_paid', true);
  end if;
  if bk.status <> 'pending' then
    perform public._raise('HOLD_EXPIRED', 'This booking is no longer waiting for payment. Please book again.');
  end if;
  ok := bk.hold_expires_at is null or bk.hold_expires_at > now()
        or public.session_spots_left(bk.session_id) >= bk.party_size;
  if not ok then
    perform public._raise('HOLD_EXPIRED', 'Your place was released because payment took too long. Please book again.');
  end if;
  if not p_succeed then
    return jsonb_build_object('status', 'declined', 'reference', bk.reference);
  end if;

  insert into public.payments(booking_id, kind, amount_cents, method, provider, provider_ref, note)
  values (bk.id, 'payment', greatest(bk.price_cents, 1), 'other', 'demo', 'demo_' || bk.id, 'Demo payment — no money taken');
  update public.bookings set status = 'confirmed', hold_expires_at = null, paid_with = 'card' where id = bk.id;
  update public.waitlist_entries set status = 'booked' where booking_id = bk.id and status = 'offered';
  perform public._enqueue_booking_notifications(bk.id, 'booking_confirmed');
  return jsonb_build_object('status', 'confirmed', 'reference', bk.reference, 'already_paid', false);
end $$;

-- Buy a pack / membership period in demo mode (signed-in clients).
create or replace function public.demo_buy_package(p_package_id uuid)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare c public.clients; pk public.packages; cid uuid;
begin
  perform public._require_demo_mode();
  c := public._client_for_user();
  select * into pk from public.packages where id = p_package_id and active;
  if not found then perform public._raise('NOT_FOUND', 'This pack is not available.'); end if;
  insert into public.client_credits(client_id, package_id, label, credits_total, service_ids, expires_at, source, provider_ref)
  values (c.id, pk.id, pk.name, pk.credits, pk.service_ids, now() + make_interval(days => pk.validity_days),
          case when pk.kind = 'membership' then 'membership' else 'purchase' end, 'demo_' || gen_random_uuid())
  returning id into cid;
  if pk.price_cents > 0 then
    insert into public.payments(client_credit_id, kind, amount_cents, method, provider, provider_ref, note)
    values (cid, 'payment', pk.price_cents, 'other', 'demo', 'demo_' || cid, pk.name || ' — demo payment, no money taken');
  end if;
  insert into public.notifications(type, recipient_email) values ('credits_added', c.email);
  return jsonb_build_object('credit_id', cid, 'credits', pk.credits,
                            'expires_at', now() + make_interval(days => pk.validity_days));
end $$;

revoke execute on function public._require_demo_mode() from public, anon, authenticated;
grant execute on function public.get_payment_details(text, text)          to anon, authenticated;
grant execute on function public.demo_pay_booking(text, text, boolean)    to anon, authenticated;
grant execute on function public.demo_buy_package(uuid)                   to authenticated;
