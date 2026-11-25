-- EXAMPLE timetable and packs so the site has something to book.
-- Replace from /admin once the timetable editor is live. Safe to re-run:
-- it only adds weeks/packs that are missing.
do $$
declare
  st     public.business_settings;
  plan   record;
  d      date;
  v_start timestamptz;
  sid    uuid;
  sess   uuid;
  first_day date;
  last_day  date;
begin
  select * into st from public.business_settings where id;
  first_day := (now() at time zone st.timezone)::date + 1;
  last_day  := first_day + 55;

  for plan in
    select s.id as service_id, s.duration_minutes, s.capacity, t.wd, t.tm::time as tm
      from public.services s
      join (values
        ('mat-pilates', 1, '19:00'), ('mat-pilates', 3, '19:00'), ('mat-pilates', 6, '10:00'),
        ('private-reformer', 1, '09:00'), ('private-reformer', 2, '09:00'), ('private-reformer', 3, '09:00'),
        ('private-reformer', 4, '09:00'), ('private-reformer', 5, '09:00'),
        ('private-reformer', 1, '10:00'), ('private-reformer', 3, '10:00'), ('private-reformer', 5, '10:00'),
        ('private-reformer', 2, '17:00'), ('private-reformer', 4, '17:00'),
        ('duet-reformer', 2, '18:00'), ('duet-reformer', 4, '18:00'), ('duet-reformer', 6, '11:00')
      ) as t(slug, wd, tm) on t.slug = s.slug
  loop
    insert into public.recurring_series(service_id, weekday, start_time, starts_on, ends_on)
    values (plan.service_id, plan.wd, plan.tm, first_day, last_day) returning id into sid;
    for d in select g::date from generate_series(first_day::timestamp, last_day::timestamp, interval '1 day') g
              where extract(dow from g)::int = plan.wd loop
      v_start := (d + plan.tm)::timestamp at time zone st.timezone;
      continue when exists (select 1 from public.sessions x where x.service_id = plan.service_id
                              and x.starts_at = v_start and x.status = 'scheduled');
      begin
        insert into public.sessions(service_id, series_id, starts_at, ends_at, capacity)
        values (plan.service_id, sid, v_start, v_start + make_interval(mins => plan.duration_minutes), plan.capacity)
        returning id into sess;
        perform public._allocate_resources(sess);
      exception when others then null;   -- clash: skip that date
      end;
    end loop;
  end loop;
end $$;

insert into public.packages(name, description, kind, credits, price_cents, validity_days, service_ids, sort_order)
select v.name, v.description, v.kind, v.credits, v.price_cents, v.validity_days,
       array(select id from public.services where slug = v.slug), v.sort_order
  from (values
    ('Mat 5-class pack',  'Five Mat Pilates classes. Valid 3 months.',  'pack',        5,  9000, 90,  'mat-pilates', 1),
    ('Mat 10-class pack', 'Ten Mat Pilates classes. Valid 4 months.',   'pack',       10, 17000, 120, 'mat-pilates', 2),
    ('Mat membership',    'Eight Mat classes every month.',             'membership',  8, 14000, 31,  'mat-pilates', 3),
    ('Private 5-session pack', 'Five Private Reformer sessions. Valid 3 months.', 'pack', 5, 30000, 90, 'private-reformer', 4)
  ) as v(name, description, kind, credits, price_cents, validity_days, slug, sort_order)
 where not exists (select 1 from public.packages p where p.name = v.name);
