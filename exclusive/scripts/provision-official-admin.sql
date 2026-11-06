-- Approval required: grant application Admin to the official mailbox only.
-- Target: Supabase project grfmiuopojbxxbdymqax (CityPark Exclusive).
-- Create the Auth account through Supabase Auth first; this script sets no password.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '15s';
do $official_admin$
declare
  account_id uuid;
  account_count integer;
begin
  select count(*) into account_count from auth.users
    where lower(email) = 'exclusive@planoaengenharia.com.br';
  if account_count <> 1 then
    raise exception 'Expected exactly one official Auth account; no role assigned';
  end if;
  select id into strict account_id from auth.users
    where lower(email) = 'exclusive@planoaengenharia.com.br';
  if exists (select 1 from public.customer_users where user_id = account_id) then
    raise exception 'Official account has a customer link; review before granting Admin';
  end if;
  if exists (select 1 from public.staff_users where user_id = account_id
    and (role <> 'admin' or not active)) then
    raise exception 'Official account has a different or inactive staff role; review required';
  end if;
  insert into public.staff_users(user_id, name, role, active)
    values (account_id, 'Admin Exclusive', 'admin', true)
    on conflict (user_id) do nothing;
end;
$official_admin$;
commit;
select s.role, s.active from public.staff_users s
  join auth.users u on u.id = s.user_id
  where lower(u.email) = 'exclusive@planoaengenharia.com.br';
