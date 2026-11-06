-- Requirements of 27/10/2026. Contract/PDF issuance is intentionally deferred.
-- Historical drafts, proposals and authorizations are retained as legacy data.

alter table public.units add column customization_status text not null default 'pending'
  check (customization_status in ('pending', 'completed'));
alter table public.units add constraint units_completed_is_inactive
  check (customization_status <> 'completed' or not active);

-- Do not guess the owner if an existing unit has ambiguous ownership.
do $$ begin
  if exists (select 1 from public.customer_units where active and ownership_role = 'owner'
    group by unit_id having count(*) > 1) or exists (
    select 1 from public.customer_units co where co.active and co.ownership_role = 'co_owner'
    and not exists (select 1 from public.customer_units ow
      where ow.unit_id = co.unit_id and ow.active and ow.ownership_role = 'owner')
  ) then raise exception 'Resolve ambiguous customer ownership before this migration'; end if;
end $$;
-- Preserve the old links for audit/FKs, while removing their access.
update public.customer_units set active = false where ownership_role = 'co_owner' and active;
alter table public.customer_units add constraint customer_units_active_owner_only
  check (not active or ownership_role = 'owner');
create unique index customer_units_one_active_customer on public.customer_units(unit_id) where active;
create unique index customer_users_one_active_account on public.customer_users(customer_id) where active;
create unique index customer_users_one_active_customer on public.customer_users(user_id) where active;

create or replace function public.staff_can_access_unit(p_unit_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.units where id = p_unit_id)
    and public.current_staff_role() in ('architect', 'admin');
$$;

create function public.customer_can_access_unit(p_unit_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.units u
    join public.customer_units cu on cu.unit_id = u.id and cu.active and cu.ownership_role = 'owner'
    join public.customer_users usr on usr.customer_id = cu.customer_id and usr.active
    where u.id = p_unit_id and u.active and usr.user_id = (select auth.uid())
  );
$$;
revoke all on function public.customer_can_access_unit(uuid) from public, anon;
grant execute on function public.customer_can_access_unit(uuid) to authenticated;

drop policy own_units on public.units;
create policy own_units on public.units for select to authenticated
  using (public.customer_can_access_unit(id));
drop policy own_unit_links on public.customer_units;
create policy own_unit_links on public.customer_units for select to authenticated
  using (active and ownership_role = 'owner' and exists (
    select 1 from public.customer_users usr
    where usr.customer_id = customer_units.customer_id and usr.active and usr.user_id = (select auth.uid())
  ));
drop policy staff_units on public.units;
create policy staff_units on public.units for select to authenticated
  using (public.staff_can_access_unit(id));
create policy staff_customers on public.customers for select to authenticated
  using ((select public.current_staff_role()) in ('architect', 'admin'));
create policy staff_customer_links on public.customer_units for select to authenticated
  using ((select public.current_staff_role()) in ('architect', 'admin'));
create policy admin_customer_accounts on public.customer_users for select to authenticated
  using ((select public.current_staff_role()) = 'admin');

-- A module without a window has no time limit. Existing explicit windows remain.
drop policy readable_modules on public.customization_modules;
create policy readable_modules on public.customization_modules for select to authenticated using (active);

create table public.base_plan_option_defaults (
  base_plan_id uuid not null,
  group_id uuid not null,
  option_id uuid not null,
  primary key (base_plan_id, group_id),
  foreign key (base_plan_id, option_id) references public.base_plan_option_availability(base_plan_id, option_id),
  foreign key (group_id, option_id) references public.customization_options(group_id, id)
);
create table public.base_plan_option_requirements (
  base_plan_id uuid not null,
  option_id uuid not null,
  required_option_id uuid not null,
  primary key (base_plan_id, option_id, required_option_id),
  foreign key (base_plan_id, option_id) references public.base_plan_option_availability(base_plan_id, option_id),
  foreign key (base_plan_id, required_option_id) references public.base_plan_option_availability(base_plan_id, option_id),
  check (option_id <> required_option_id)
);
alter table public.base_plan_option_defaults enable row level security;
alter table public.base_plan_option_requirements enable row level security;
revoke all on public.base_plan_option_defaults, public.base_plan_option_requirements from public, anon, authenticated;
grant select on public.base_plan_option_defaults, public.base_plan_option_requirements to authenticated;
grant all on public.base_plan_option_defaults, public.base_plan_option_requirements to service_role;
create policy readable_option_defaults on public.base_plan_option_defaults for select to authenticated
  using (exists (select 1 from public.base_plans p where p.id = base_plan_id));
create policy readable_option_requirements on public.base_plan_option_requirements for select to authenticated
  using (exists (select 1 from public.base_plans p where p.id = base_plan_id));

-- Only explicit demonstration defaults; no official catalog data is inferred.
insert into public.base_plan_option_defaults(base_plan_id, group_id, option_id)
select a.base_plan_id, o.group_id, o.id
from public.base_plan_option_availability a
join public.base_plans p on p.id = a.base_plan_id and p.code like 'DEMO-%'
join public.customization_options o on o.id = a.option_id
join public.customization_groups g on g.id = o.group_id
where (g.code in ('DEMO-AREA-SOCIAL','DEMO-SUITE-MASTER','DEMO-BANCADA','DEMO-RODAMAO','DEMO-SERVICO') and o.code = 'padrao')
   or (g.code = 'DEMO-GRANITO' and o.code = 'sao-marco');

create function public.current_actor_name() returns text
language sql stable security definer set search_path = '' as $$
  select coalesce(
    (select name from public.staff_users where user_id = (select auth.uid()) and active),
    (select c.name from public.customers c join public.customer_users u on u.customer_id = c.id
      where u.user_id = (select auth.uid()) and u.active limit 1), 'Usuário');
$$;
revoke all on function public.current_actor_name() from public, anon, authenticated;

create table public.unit_activity_events (
  id bigint generated always as identity primary key,
  unit_id uuid not null references public.units(id),
  actor_user_id uuid not null references auth.users(id),
  actor_role text not null check (actor_role in ('customer','architect','admin')),
  actor_name text not null default public.current_actor_name(),
  action text not null,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default clock_timestamp()
);
create index unit_activity_events_unit_time on public.unit_activity_events(unit_id, created_at desc, id desc);
alter table public.unit_activity_events enable row level security;
revoke all on public.unit_activity_events from public, anon, authenticated;
grant select on public.unit_activity_events to authenticated;
grant all on public.unit_activity_events to service_role;
grant usage, select on sequence public.unit_activity_events_id_seq to service_role;
create policy staff_activity_events on public.unit_activity_events for select to authenticated
  using ((select public.current_staff_role()) in ('architect','admin'));

create function public.record_unit_access(p_unit_id uuid) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if (select auth.uid()) is null or not (
    coalesce(public.staff_can_access_unit(p_unit_id), false) or public.customer_can_access_unit(p_unit_id)
  ) then raise exception 'Unit access denied' using errcode = '42501'; end if;
  insert into public.unit_activity_events(unit_id, actor_user_id, actor_role, action)
  values(p_unit_id, (select auth.uid()), coalesce(public.current_staff_role(), 'customer'), 'unit_opened');
end; $$;

create function public.set_unit_active(p_unit_id uuid, p_active boolean) returns public.units
language plpgsql security definer set search_path = '' as $$
declare v_unit public.units;
begin
  if (select public.current_staff_role()) not in ('architect','admin') or public.current_staff_role() is null
    then raise exception 'Staff access required' using errcode = '42501'; end if;
  if p_active is null then raise exception 'Invalid unit status' using errcode = '22023'; end if;
  select * into v_unit from public.units where id = p_unit_id for update;
  if not found then raise exception 'Unit not found' using errcode = '22023'; end if;
  if p_active and v_unit.customization_status = 'completed' and public.current_staff_role() <> 'admin'
    then raise exception 'Only admin can reopen completed unit' using errcode = '42501'; end if;
  if v_unit.active is distinct from p_active then
    update public.units set active = p_active,
      customization_status = case when p_active then 'pending' else customization_status end
      where id = p_unit_id returning * into v_unit;
    insert into public.unit_activity_events(unit_id, actor_user_id, actor_role, action, details)
    values(p_unit_id, (select auth.uid()), public.current_staff_role(), 'unit_status_changed',
      jsonb_build_object('active', p_active, 'customization_status', v_unit.customization_status));
  end if;
  return v_unit;
end; $$;

create function public.set_unit_deadline(p_unit_id uuid, p_closes_at timestamptz) returns void
language plpgsql security definer set search_path = '' as $$
declare v_previous timestamptz;
begin
  if public.current_staff_role() is distinct from 'admin'
    then raise exception 'Admin required' using errcode = '42501'; end if;
  select customization_closes_at into v_previous from public.units where id = p_unit_id for update;
  if not found then raise exception 'Unit not found' using errcode = '22023'; end if;
  update public.units set customization_closes_at = p_closes_at where id = p_unit_id;
  if v_previous is distinct from p_closes_at then
    insert into public.unit_activity_events(unit_id, actor_user_id, actor_role, action, details)
    values(p_unit_id, (select auth.uid()), 'admin', 'unit_deadline_changed',
      jsonb_build_object('previous', v_previous, 'closes_at', p_closes_at));
  end if;
end; $$;

create function public.set_module_deadline(p_unit_id uuid, p_module_code text, p_closes_at timestamptz) returns void
language plpgsql security definer set search_path = '' as $$
declare v_previous timestamptz;
begin
  if public.current_staff_role() is distinct from 'admin'
    then raise exception 'Admin required' using errcode = '42501'; end if;
  perform 1 from public.units where id = p_unit_id for update;
  if not found or not exists (select 1 from public.customization_modules where code = p_module_code and active)
    then raise exception 'Unit or module not found' using errcode = '22023'; end if;
  select closes_at into v_previous from public.unit_module_windows
    where unit_id = p_unit_id and module_code = p_module_code;
  if p_closes_at is null then
    delete from public.unit_module_windows where unit_id = p_unit_id and module_code = p_module_code;
  else
    insert into public.unit_module_windows(unit_id, module_code, opens_at, closes_at, status)
    values(p_unit_id, p_module_code, least(clock_timestamp(), p_closes_at) - interval '1 second', p_closes_at, 'active')
    on conflict (unit_id, module_code) do update set opens_at = excluded.opens_at,
      closes_at = excluded.closes_at, status = 'active', updated_at = clock_timestamp();
  end if;
  if v_previous is distinct from p_closes_at then
    insert into public.unit_activity_events(unit_id, actor_user_id, actor_role, action, details)
    values(p_unit_id, (select auth.uid()), 'admin', 'module_deadline_changed',
      jsonb_build_object('module_code', p_module_code, 'previous', v_previous, 'closes_at', p_closes_at));
  end if;
end; $$;

create function public.set_unit_customer(p_unit_id uuid, p_customer_id uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare v_previous uuid;
begin
  if public.current_staff_role() is distinct from 'admin'
    then raise exception 'Admin required' using errcode = '42501'; end if;
  perform 1 from public.units where id = p_unit_id for update;
  if not found or (p_customer_id is not null and not exists (select 1 from public.customers where id = p_customer_id))
    then raise exception 'Unit or customer not found' using errcode = '22023'; end if;
  select customer_id into v_previous from public.customer_units where unit_id = p_unit_id and active;
  update public.customer_units set active = false where unit_id = p_unit_id and active;
  if p_customer_id is not null then
    insert into public.customer_units(customer_id, unit_id, ownership_role, active)
    values(p_customer_id, p_unit_id, 'owner', true) on conflict(customer_id, unit_id)
    do update set ownership_role = 'owner', active = true;
  end if;
  if v_previous is distinct from p_customer_id then
    insert into public.unit_activity_events(unit_id, actor_user_id, actor_role, action, details)
    values(p_unit_id, (select auth.uid()), 'admin', 'unit_customer_changed',
      jsonb_build_object('previous_customer_id', v_previous, 'customer_id', p_customer_id));
  end if;
end; $$;

create function public.manage_unit(p_unit_id uuid, p_customer_id uuid,
  p_closes_at timestamptz, p_module_deadlines jsonb) returns void
language plpgsql security definer set search_path = '' as $$
declare v_module text; v_date text;
begin
  if public.current_staff_role() is distinct from 'admin'
    then raise exception 'Admin required' using errcode = '42501'; end if;
  if jsonb_typeof(p_module_deadlines) is distinct from 'object'
    then raise exception 'Invalid module deadlines' using errcode = '22023'; end if;
  perform public.set_unit_customer(p_unit_id, p_customer_id);
  perform public.set_unit_deadline(p_unit_id, p_closes_at);
  for v_module, v_date in select key, value from jsonb_each_text(p_module_deadlines) loop
    perform public.set_module_deadline(p_unit_id, v_module, v_date::timestamptz);
  end loop;
end; $$;

-- Validates an entire transient session without storing its choices.
create function public.validate_unit_session(p_unit_id uuid, p_selections jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_plan uuid; v_choices jsonb; v_count integer;
begin
  if (select auth.uid()) is null or not (coalesce(public.staff_can_access_unit(p_unit_id), false)
    or public.customer_can_access_unit(p_unit_id))
    then raise exception 'Unit access denied' using errcode = '42501'; end if;
  if jsonb_typeof(p_selections) is distinct from 'object'
    then raise exception 'Invalid session choices' using errcode = '22023'; end if;
  select a.base_plan_id into v_plan from public.unit_base_plan_assignments a
    join public.base_plans p on p.id = a.base_plan_id and p.status = 'active' where a.unit_id = p_unit_id;
  if v_plan is null then raise exception 'Base plan not assigned' using errcode = '22023'; end if;
  select coalesce(jsonb_object_agg(group_id::text, option_id::text), '{}'::jsonb) into v_choices
    from public.base_plan_option_defaults where base_plan_id = v_plan;
  v_choices := v_choices || p_selections;
  if exists (select 1 from jsonb_each(v_choices) e where jsonb_typeof(e.value) <> 'string'
    or e.key !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    or (e.value #>> '{}') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')
    then raise exception 'Invalid session option' using errcode = '22023'; end if;
  select count(*) into v_count from jsonb_each_text(v_choices) e
    join public.customization_options o on o.id = e.value::uuid and o.group_id = e.key::uuid and o.status = 'active'
    join public.customization_groups g on g.id = o.group_id and g.status = 'active'
    join public.customization_modules m on m.code = g.module_code and m.active
    join public.base_plan_option_availability a on a.option_id = o.id and a.base_plan_id = v_plan;
  if v_count <> (select count(*) from jsonb_each(v_choices)) then
    raise exception 'Option unavailable for base plan' using errcode = '22023'; end if;
  if exists (select 1 from public.customization_groups g
    join public.customization_modules m on m.code = g.module_code and m.active
    where g.status = 'active' and g.required_for_submission
      and exists (select 1 from public.customization_options o join public.base_plan_option_availability a
        on a.option_id = o.id and a.base_plan_id = v_plan where o.group_id = g.id and o.status = 'active')
      and not (v_choices ? g.id::text)) then
    raise exception 'Required choices are incomplete' using errcode = '22023'; end if;
  if exists (select 1 from public.base_plan_option_exclusions e where e.base_plan_id = v_plan
    and exists (select 1 from jsonb_each_text(v_choices) c where c.value::uuid = e.first_option_id)
    and exists (select 1 from jsonb_each_text(v_choices) c where c.value::uuid = e.second_option_id))
    or exists (select 1 from public.base_plan_option_requirements r where r.base_plan_id = v_plan
      and exists (select 1 from jsonb_each_text(v_choices) c where c.value::uuid = r.option_id)
      and not exists (select 1 from jsonb_each_text(v_choices) c where c.value::uuid = r.required_option_id))
    then raise exception 'Incompatible session choices' using errcode = '22023'; end if;
  if exists (select 1 from public.units where id = p_unit_id
    and customization_closes_at is not null and clock_timestamp() >= customization_closes_at)
    or exists (select 1 from public.unit_module_windows w
      join public.customization_groups g on g.module_code = w.module_code
      where w.unit_id = p_unit_id and v_choices ? g.id::text
        and (w.status <> 'active' or clock_timestamp() < w.opens_at or clock_timestamp() >= w.closes_at))
    then raise exception 'Customization deadline closed' using errcode = '42501'; end if;
  return v_choices;
end; $$;

revoke all on function public.record_unit_access(uuid), public.set_unit_active(uuid, boolean),
  public.set_unit_deadline(uuid, timestamptz), public.set_module_deadline(uuid, text, timestamptz),
  public.set_unit_customer(uuid, uuid), public.validate_unit_session(uuid, jsonb) from public, anon;
revoke all on function public.manage_unit(uuid, uuid, timestamptz, jsonb) from public, anon;
grant execute on function public.record_unit_access(uuid), public.set_unit_active(uuid, boolean),
  public.set_unit_deadline(uuid, timestamptz), public.set_module_deadline(uuid, text, timestamptz),
  public.set_unit_customer(uuid, uuid), public.validate_unit_session(uuid, jsonb) to authenticated;
grant execute on function public.manage_unit(uuid, uuid, timestamptz, jsonb) to authenticated;

-- New sessions never write drafts/proposals or request a technical opinion.
revoke execute on function public.save_unit_module_choices(uuid, uuid, text, jsonb, integer),
  public.submit_unit_proposal(uuid, uuid, jsonb), public.review_unit_proposal(uuid, integer, text, text),
  public.review_unit_configuration(uuid, integer, text, text) from authenticated;
