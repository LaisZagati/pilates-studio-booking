-- Run once in the Supabase SQL editor after creating your own account
-- (Authentication → Users → Add user, or sign up on the site).
insert into public.admins (user_id)
select id from auth.users where email = 'YOUR-EMAIL@example.com'
on conflict do nothing;
