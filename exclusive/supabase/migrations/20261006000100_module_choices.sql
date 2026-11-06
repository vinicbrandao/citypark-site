-- New module-scoped configuration. Legacy drafts and prototype combinations
-- remain separate until the UI and existing records can be migrated safely.

create table public.base_plan_option_availability (
  base_plan_id uuid not null references public.base_plans(id),
  option_id uuid not null references public.customization_options(id),
  primary key (base_plan_id, option_id)
);
create index base_plan_option_availability_option_idx
  on public.base_plan_option_availability(option_id, base_plan_id);

-- Negative pair rules cover catalog incompatibilities that a single option's
-- availability cannot express. Store each unordered pair only once.
create table public.base_plan_option_exclusions (
  base_plan_id uuid not null references public.base_plans(id),
  first_option_id uuid not null,
  second_option_id uuid not null,
  primary key (base_plan_id, first_option_id, second_option_id),
  foreign key (base_plan_id, first_option_id)
    references public.base_plan_option_availability(base_plan_id, option_id),
  foreign key (base_plan_id, second_option_id)
    references public.base_plan_option_availability(base_plan_id, option_id),
  check (first_option_id < second_option_id)
);

create table public.unit_module_states (
  unit_id uuid not null references public.units(id),
  module_code text not null references public.customization_modules(code),
  revision integer not null default 0 check (revision >= 0),
  updated_by uuid references auth.users(id),
  updated_at timestamptz not null default now(),
  primary key (unit_id, module_code)
);

create table public.unit_module_selections (
  unit_id uuid not null,
  module_code text not null,
  group_id uuid not null references public.customization_groups(id),
  option_id uuid not null,
  updated_by uuid not null references auth.users(id),
  updated_at timestamptz not null default now(),
  primary key (unit_id, group_id),
  foreign key (unit_id, module_code)
    references public.unit_module_states(unit_id, module_code),
  foreign key (group_id, option_id)
    references public.customization_options(group_id, id)
);
create index unit_module_selections_module_idx
  on public.unit_module_selections(unit_id, module_code);

create table public.unit_module_history (
  unit_id uuid not null,
  module_code text not null,
  revision integer not null check (revision > 0),
  base_plan_id uuid not null references public.base_plans(id),
  selections jsonb not null check (jsonb_typeof(selections) = 'object'),
  actor_user_id uuid not null references auth.users(id),
  actor_customer_id uuid,
  actor_ownership_role text,
  actor_staff_role text,
  created_at timestamptz not null default now(),
  primary key (unit_id, module_code, revision),
  foreign key (unit_id, module_code)
    references public.unit_module_states(unit_id, module_code),
  foreign key (actor_customer_id, unit_id)
    references public.customer_units(customer_id, unit_id),
  check (
    (actor_customer_id is not null
      and actor_ownership_role in ('owner', 'co_owner')
      and actor_staff_role is null)
    or (actor_customer_id is null and actor_ownership_role is null
      and actor_staff_role in ('admin', 'architect'))
  )
);
create index unit_module_history_actor_idx
  on public.unit_module_history(actor_user_id, created_at desc);

alter table public.base_plan_option_availability enable row level security;
alter table public.base_plan_option_exclusions enable row level security;
alter table public.unit_module_states enable row level security;
alter table public.unit_module_selections enable row level security;
alter table public.unit_module_history enable row level security;

revoke all on public.base_plan_option_availability,
  public.base_plan_option_exclusions, public.unit_module_states,
  public.unit_module_selections, public.unit_module_history
  from public, anon, authenticated;
grant select on public.base_plan_option_availability,
  public.base_plan_option_exclusions, public.unit_module_states,
  public.unit_module_selections, public.unit_module_history
  to authenticated;
grant all on public.base_plan_option_availability,
  public.base_plan_option_exclusions, public.unit_module_states,
  public.unit_module_selections, public.unit_module_history
  to service_role;

create policy readable_base_plan_option_availability
  on public.base_plan_option_availability for select to authenticated
  using (exists (
    select 1 from public.base_plans p
    where p.id = base_plan_option_availability.base_plan_id
  ));
create policy readable_base_plan_option_exclusions
  on public.base_plan_option_exclusions for select to authenticated
  using (exists (
    select 1 from public.base_plans p
    where p.id = base_plan_option_exclusions.base_plan_id
  ));
create policy readable_unit_module_states
  on public.unit_module_states for select to authenticated
  using (exists (select 1 from public.units u where u.id = unit_module_states.unit_id));
create policy readable_unit_module_selections
  on public.unit_module_selections for select to authenticated
  using (exists (select 1 from public.units u where u.id = unit_module_selections.unit_id));
create policy readable_unit_module_history
  on public.unit_module_history for select to authenticated
  using (exists (select 1 from public.units u where u.id = unit_module_history.unit_id));

-- p_selections maps group UUIDs to option UUIDs for exactly one module.
-- Missing groups are allowed while the customer is still drafting.
create function public.save_unit_module_choices(
  p_customer_id uuid,
  p_unit_id uuid,
  p_module_code text,
  p_selections jsonb,
  p_expected_revision integer
) returns public.unit_module_states
language plpgsql security definer set search_path = '' as $$
declare
  v_state public.unit_module_states;
  v_base_plan_id uuid;
  v_role text;
  v_staff_role text;
  v_key text;
  v_value text;
  v_count integer;
  v_valid_count integer;
  v_window public.unit_module_windows;
  v_saved_at timestamptz;
begin
  if (select auth.uid()) is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if p_unit_id is null or p_module_code is null
    or p_expected_revision is null or p_expected_revision < 0
    or jsonb_typeof(p_selections) is distinct from 'object' then
    raise exception 'Invalid module choices' using errcode = '22023';
  end if;

  -- Authorizations and assignments also lock the unit when changed.
  perform 1 from public.units where id = p_unit_id and active for update;
  if not found then
    raise exception 'Unit access denied' using errcode = '42501';
  end if;
  if p_customer_id is null then
    v_staff_role := public.current_staff_role();
    if v_staff_role is null or not public.staff_can_access_unit(p_unit_id) then
      raise exception 'Unit access denied' using errcode = '42501';
    end if;
  else
    select cu.ownership_role into v_role
    from public.customer_units cu
    join public.customer_users usr
      on usr.customer_id = cu.customer_id and usr.active
    where cu.customer_id = p_customer_id and cu.unit_id = p_unit_id
      and cu.active and usr.user_id = (select auth.uid());
    if v_role is null or v_role not in ('owner', 'co_owner') then
      raise exception 'Unit access denied' using errcode = '42501';
    end if;
  end if;

  select a.base_plan_id into v_base_plan_id
  from public.unit_base_plan_assignments a
  join public.base_plans p on p.id = a.base_plan_id and p.status = 'active'
  where a.unit_id = p_unit_id
  for share of a, p;
  if v_base_plan_id is null
    or not exists (select 1 from public.customization_modules m
                   where m.code = p_module_code and m.active)
    or not exists (select 1 from public.customization_groups g
                   where g.module_code = p_module_code and g.status = 'active') then
    raise exception 'Module catalog unavailable' using errcode = '22023';
  end if;

  for v_key, v_value in select key, value from jsonb_each_text(p_selections) loop
    if jsonb_typeof(p_selections->v_key) <> 'string'
      or v_key !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
      or v_value !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
      raise exception 'Invalid module option' using errcode = '22023';
    end if;
  end loop;
  select count(*) into v_count from jsonb_each(p_selections);
  select count(*) into v_valid_count
  from jsonb_each_text(p_selections) chosen(group_key, option_key)
  join public.customization_groups g
    on g.id = chosen.group_key::uuid
    and g.module_code = p_module_code and g.status = 'active'
  join public.customization_options o
    on o.id = chosen.option_key::uuid
    and o.group_id = g.id and o.status = 'active'
  join public.base_plan_option_availability a
    on a.base_plan_id = v_base_plan_id and a.option_id = o.id;
  if v_count <> v_valid_count then
    raise exception 'Option unavailable for module or plan' using errcode = '22023';
  end if;
  -- Check new choices together with unchanged choices of other modules.
  if exists (
    with chosen_options as (
      select value::uuid as option_id from jsonb_each_text(p_selections)
      union all
      select s.option_id from public.unit_module_selections s
      where s.unit_id = p_unit_id and s.module_code <> p_module_code
    )
    select 1 from public.base_plan_option_exclusions e
    join chosen_options first_choice on first_choice.option_id = e.first_option_id
    join chosen_options second_choice on second_choice.option_id = e.second_option_id
    where e.base_plan_id = v_base_plan_id
  ) then
    raise exception 'Incompatible module options' using errcode = '22023';
  end if;

  insert into public.unit_module_states(unit_id, module_code)
  values (p_unit_id, p_module_code) on conflict do nothing;
  select * into v_state from public.unit_module_states
    where unit_id = p_unit_id and module_code = p_module_code for update;
  if v_state.revision <> p_expected_revision then
    raise exception 'Module changed in another session' using errcode = '40001';
  end if;
  select * into v_window from public.unit_module_windows
    where unit_id = p_unit_id and module_code = p_module_code for share;
  v_saved_at := clock_timestamp();
  if v_window.unit_id is null or v_window.status <> 'active'
    or v_saved_at < v_window.opens_at or v_saved_at >= v_window.closes_at then
    raise exception 'Module window closed' using errcode = '42501';
  end if;

  delete from public.unit_module_selections
    where unit_id = p_unit_id and module_code = p_module_code;
  insert into public.unit_module_selections
    (unit_id, module_code, group_id, option_id, updated_by, updated_at)
  select p_unit_id, p_module_code, chosen.group_key::uuid,
    chosen.option_key::uuid, (select auth.uid()), v_saved_at
  from jsonb_each_text(p_selections) chosen(group_key, option_key);
  update public.unit_module_states
    set revision = revision + 1, updated_by = (select auth.uid()),
      updated_at = v_saved_at
    where unit_id = p_unit_id and module_code = p_module_code
    returning * into v_state;
  insert into public.unit_module_history
    (unit_id, module_code, revision, base_plan_id, selections,
     actor_user_id, actor_customer_id, actor_ownership_role,
     actor_staff_role, created_at)
  values (p_unit_id, p_module_code, v_state.revision, v_base_plan_id,
    p_selections, (select auth.uid()), p_customer_id, v_role,
    v_staff_role, v_saved_at);
  return v_state;
end;
$$;

revoke all on function public.save_unit_module_choices(uuid, uuid, text, jsonb, integer)
  from public, anon;
grant execute on function public.save_unit_module_choices(uuid, uuid, text, jsonb, integer)
  to authenticated;
