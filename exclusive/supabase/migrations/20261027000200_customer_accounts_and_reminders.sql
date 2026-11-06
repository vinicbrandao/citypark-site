-- Admin-only account registration; Auth user creation runs in a server function.
create function public.find_customer_auth_user(p_email text) returns uuid
language plpgsql security definer set search_path = '' as $$
begin
  if public.current_staff_role() is distinct from 'admin' then
    raise exception 'Admin required' using errcode = '42501'; end if;
  return (select id from auth.users where lower(email) = lower(btrim(p_email)) limit 1);
end; $$;

alter table public.unit_activity_events alter column unit_id drop not null;
create function public.register_customer_account(p_name text, p_email text) returns uuid
language plpgsql security definer set search_path = '' as $$
declare v_user uuid; v_customer uuid; v_email text := lower(btrim(p_email)); v_name text := btrim(p_name);
begin
  if public.current_staff_role() is distinct from 'admin' then
    raise exception 'Admin required' using errcode = '42501'; end if;
  if v_name is null or length(v_name) not between 1 and 200 or v_email is null
    or length(v_email) > 254 or v_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then
    raise exception 'Invalid customer profile' using errcode = '22023'; end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_email, 0));
  v_user := public.find_customer_auth_user(v_email);
  if v_user is null then raise exception 'Auth account not provisioned' using errcode = '22023'; end if;
  if exists(select 1 from public.staff_users where user_id = v_user) then
    raise exception 'Staff account cannot be a customer account' using errcode = '22023'; end if;
  select customer_id into v_customer from public.customer_users where user_id = v_user and active;
  if v_customer is null then
    insert into public.customers(name,email) values(v_name,v_email) returning id into v_customer;
    insert into public.customer_users(customer_id,user_id,active) values(v_customer,v_user,true);
  else
    update public.customers set name = v_name, email = v_email where id = v_customer;
  end if;
  insert into public.unit_activity_events(actor_user_id,actor_role,action,details)
  values((select auth.uid()),'admin','customer_registered',jsonb_build_object('customer_id',v_customer));
  return v_customer;
end; $$;
revoke all on function public.find_customer_auth_user(text), public.register_customer_account(text,text) from public, anon;
grant execute on function public.find_customer_auth_user(text), public.register_customer_account(text,text) to authenticated;

-- Queue with one reminder per unit/module/date/milestone/customer. No provider
-- credentials or scheduler secrets belong in migrations or the frontend.
create table public.deadline_notifications (
  id uuid primary key default gen_random_uuid(),
  unit_id uuid not null references public.units(id),
  customer_id uuid not null references public.customers(id),
  scope text not null,
  deadline timestamptz not null,
  due_date date not null,
  days_before integer not null check(days_before in (15,10,5,1)),
  recipient text not null,
  unit_code text not null,
  module_name text,
  status text not null default 'pending' check(status in ('pending','sending','sent','failed')),
  attempts integer not null default 0,
  lease_until timestamptz,
  last_error text,
  sent_at timestamptz,
  created_at timestamptz not null default clock_timestamp(),
  unique(unit_id,customer_id,scope,deadline,days_before)
);
alter table public.deadline_notifications enable row level security;
revoke all on public.deadline_notifications from public, anon, authenticated;
grant select on public.deadline_notifications to authenticated;
grant all on public.deadline_notifications to service_role;
create policy admin_deadline_notifications on public.deadline_notifications for select to authenticated
  using ((select public.current_staff_role()) = 'admin');

create function public.claim_deadline_notifications(p_limit integer default 50)
returns setof public.deadline_notifications
language plpgsql security definer set search_path = '' as $$
declare v_today date := (clock_timestamp() at time zone 'America/Sao_Paulo')::date;
begin
  if p_limit not between 1 and 100 then raise exception 'Invalid batch size'; end if;
  insert into public.deadline_notifications(unit_id,customer_id,scope,deadline,due_date,days_before,recipient,unit_code,module_name)
  select u.id,cu.customer_id,d.scope,d.deadline,v_today,
    (d.deadline at time zone 'America/Sao_Paulo')::date-v_today,au.email,u.code,d.module_name
  from public.units u
  join public.customer_units cu on cu.unit_id=u.id and cu.active and cu.ownership_role='owner'
  join public.customer_users usr on usr.customer_id=cu.customer_id and usr.active
  join auth.users au on au.id=usr.user_id and au.email is not null
  cross join lateral (
    select 'unit'::text as scope,u.customization_closes_at as deadline,null::text as module_name
    union all
    select 'module:'||w.module_code,w.closes_at,m.name from public.unit_module_windows w
      join public.customization_modules m on m.code=w.module_code and m.active
      where w.unit_id=u.id and w.status='active'
  ) d
  where u.active and u.customization_status='pending' and d.deadline is not null
    and (d.deadline at time zone 'America/Sao_Paulo')::date-v_today in (15,10,5,1)
  on conflict(unit_id,customer_id,scope,deadline,days_before) do nothing;

  return query with batch as (
    select n.id from public.deadline_notifications n
    join public.units u on u.id=n.unit_id and u.active and u.customization_status='pending'
    join public.customer_units cu on cu.unit_id=u.id and cu.customer_id=n.customer_id and cu.active
    where n.due_date=v_today and n.attempts<5 and n.status<>'sent'
      and (n.lease_until is null or n.lease_until<clock_timestamp())
      and ((n.scope='unit' and u.customization_closes_at=n.deadline) or exists(
        select 1 from public.unit_module_windows w where w.unit_id=n.unit_id
          and n.scope='module:'||w.module_code and w.status='active' and w.closes_at=n.deadline))
    order by n.created_at for update of n skip locked limit p_limit
  ) update public.deadline_notifications n set status='sending',attempts=n.attempts+1,
      lease_until=clock_timestamp()+interval '10 minutes'
    from batch where n.id=batch.id returning n.*;
end; $$;

create function public.finish_deadline_notification(p_id uuid,p_success boolean,p_error text default null)
returns void language sql security definer set search_path = '' as $$
  update public.deadline_notifications set status=case when p_success then 'sent' else 'failed' end,
    sent_at=case when p_success then clock_timestamp() else null end,
    last_error=case when p_success then null else left(p_error,1000) end,
    lease_until=case when p_success then null else clock_timestamp()+interval '10 minutes' end
  where id=p_id and status='sending';
$$;
revoke all on function public.claim_deadline_notifications(integer),public.finish_deadline_notification(uuid,boolean,text)
  from public,anon,authenticated;
grant execute on function public.claim_deadline_notifications(integer),public.finish_deadline_notification(uuid,boolean,text) to service_role;
