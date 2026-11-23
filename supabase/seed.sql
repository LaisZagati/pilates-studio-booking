-- Initial studio data. Everything here is editable later from /admin.
insert into public.business_settings (id, studio_name, tagline, address, contact_email, contact_phone,
  timezone, currency, min_advance_minutes, max_advance_days, buffer_minutes, cancellation_window_hours,
  booking_policy, cancellation_policy)
values (true, 'Pilates Studio', 'Boutique reformer & mat Pilates',
  'Calle Ejemplo 1, Valencia', 'hello@example.com', '+34 600 000 000',
  'Europe/Madrid', 'EUR', 120, 60, 0, 24,
  'Please arrive 5 minutes early. Grip socks are required on the reformer.',
  'Free cancellation up to 24 hours before your session. Later cancellations may be charged in full.')
on conflict (id) do nothing;

insert into public.notification_settings (id, owner_email) values (true, null)
on conflict (id) do nothing;

insert into public.resources (name, kind) values
  ('Reformer 1', 'reformer'),
  ('Reformer 2', 'reformer'),
  ('Mat studio', 'mat_space')
on conflict (name) do nothing;

insert into public.services (slug, name, short_description, description, duration_minutes, price_cents,
                             capacity, reformers_required, uses_mat_space, is_group, sort_order)
values
  ('private-reformer', 'Private Reformer Pilates', 'One-to-one session on the reformer.',
   'A fully personalised 60-minute reformer session with your instructor’s complete attention.',
   60, 6500, 1, 1, false, false, 1),
  ('duet-reformer', 'Duet Reformer Pilates', 'Train side by side with a friend or partner.',
   'A 60-minute semi-private session for two, using both reformers.',
   60, 9000, 2, 2, false, false, 2),
  ('mat-pilates', 'Mat Pilates', 'Small-group mat class, up to four people.',
   'A 60-minute mat class in a small group of up to four, focused on control, breath and core strength.',
   60, 2000, 4, 0, true, true, 3)
on conflict (slug) do nothing;

-- Opening hours (studio-wide): Mon–Fri 07:00–21:00, Sat 09:00–14:00
insert into public.availability_rules (service_id, weekday, start_time, end_time)
select null, h.wd, h.st::time, h.en::time
from (select wd, '07:00' st, '21:00' en from generate_series(1, 5) wd
      union all select 6, '09:00', '14:00') h
where not exists (select 1 from public.availability_rules);
