-- Catálogo, configuração efetiva por unidade e trilha de alterações.
-- O rascunho legado (unit_drafts) continua disponível durante a migração da UI.

create table public.plans (
  id uuid primary key default gen_random_uuid(),
  code text not null unique check (length(btrim(code)) > 0),
  name text not null check (length(btrim(name)) > 0),
  description text,
  status text not null default 'active' check (status in ('active', 'archived')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.unit_plans (
  unit_id uuid not null references public.units(id),
  plan_id uuid not null references public.plans(id),
  status text not null default 'available' check (status in ('available', 'unavailable')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (unit_id, plan_id)
);

create index unit_plans_plan_idx on public.unit_plans(plan_id, unit_id);

create table public.plan_features (
  plan_id uuid not null references public.plans(id),
  feature_key text not null check (length(btrim(feature_key)) > 0),
  feature_value jsonb not null check (jsonb_typeof(feature_value) = 'object'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (plan_id, feature_key)
);

create table public.customization_groups (
  id uuid primary key default gen_random_uuid(),
  code text not null unique check (length(btrim(code)) > 0),
  name text not null check (length(btrim(name)) > 0),
  sort_order integer not null default 0,
  status text not null default 'active' check (status in ('active', 'archived')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.customization_options (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.customization_groups(id),
  code text not null check (length(btrim(code)) > 0),
  name text not null check (length(btrim(name)) > 0),
  description text,
  sort_order integer not null default 0,
  status text not null default 'active' check (status in ('active', 'archived')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (group_id, code),
  unique (group_id, id)
);

create index customization_options_group_idx on public.customization_options(group_id, sort_order);

create table public.option_compatibilities (
  plan_id uuid not null references public.plans(id),
  option_id uuid not null references public.customization_options(id),
  created_at timestamptz not null default now(),
  primary key (plan_id, option_id)
);

create index option_compatibilities_option_idx on public.option_compatibilities(option_id, plan_id);

-- Uma janela por unidade; períodos futuros podem ser substituídos pela equipe.
create table public.customization_windows (
  unit_id uuid primary key references public.units(id),
  opens_at timestamptz not null,
  closes_at timestamptz not null,
  status text not null default 'active' check (status in ('active', 'suspended')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (opens_at < closes_at)
);

-- Há uma configuração compartilhada por unidade. O vínculo que realizou cada
-- escolha fica em customer_customizations; owner/co_owner têm a mesma regra.
create table public.unit_configuration_state (
  unit_id uuid primary key references public.units(id),
  plan_id uuid,
  status text not null default 'draft' check (status in ('draft', 'submitted', 'locked')),
  revision integer not null default 0 check (revision >= 0),
  updated_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (unit_id, plan_id),
  foreign key (unit_id, plan_id) references public.unit_plans(unit_id, plan_id),
  check ((revision = 0 and plan_id is null) or (revision > 0 and plan_id is not null))
);

create table public.customer_customizations (
  unit_id uuid not null,
  group_id uuid not null references public.customization_groups(id),
  option_id uuid not null,
  plan_id uuid not null,
  customer_id uuid not null,
  revision integer not null check (revision > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (unit_id, group_id),
  foreign key (customer_id, unit_id) references public.customer_units(customer_id, unit_id),
  foreign key (group_id, option_id) references public.customization_options(group_id, id),
  foreign key (unit_id, plan_id) references public.unit_configuration_state(unit_id, plan_id)
    deferrable initially deferred,
  foreign key (plan_id, option_id) references public.option_compatibilities(plan_id, option_id)
    deferrable initially deferred
);

create index customer_customizations_customer_idx on public.customer_customizations(customer_id, unit_id);

create index customer_customizations_option_idx on public.customer_customizations(option_id);

create table public.customization_history (
  unit_id uuid not null references public.units(id),
  revision integer not null check (revision > 0),
  plan_id uuid not null,
  selections jsonb not null check (jsonb_typeof(selections) = 'object'),
  actor_customer_id uuid not null,
  actor_user_id uuid not null references auth.users(id),
  actor_ownership_role text not null check (actor_ownership_role in ('owner', 'co_owner')),
  action text not null check (action in ('draft_saved')),
  created_at timestamptz not null default now(),
  primary key (unit_id, revision),
  foreign key (unit_id, plan_id) references public.unit_plans(unit_id, plan_id),
  foreign key (actor_customer_id, unit_id) references public.customer_units(customer_id, unit_id)
);

create index customization_history_actor_idx on public.customization_history(actor_customer_id, created_at desc);

-- Acesso de leitura segue o vínculo ativo cliente-usuário-unidade existente.
-- Escrita pelo cliente ocorre somente pela função transacional abaixo.
alter table public.plans enable row level security;

alter table public.unit_plans enable row level security;

alter table public.plan_features enable row level security;

alter table public.customization_groups enable row level security;

alter table public.customization_options enable row level security;

alter table public.option_compatibilities enable row level security;

alter table public.customization_windows enable row level security;

alter table public.unit_configuration_state enable row level security;

alter table public.customer_customizations enable row level security;

alter table public.customization_history enable row level security;

revoke all on public.plans, public.unit_plans, public.plan_features,
  public.customization_groups, public.customization_options, public.option_compatibilities,
  public.customization_windows, public.unit_configuration_state,
  public.customer_customizations, public.customization_history from anon, authenticated;

grant select on public.plans, public.unit_plans, public.plan_features,
  public.customization_groups, public.customization_options, public.option_compatibilities,
  public.customization_windows, public.unit_configuration_state,
  public.customer_customizations, public.customization_history to authenticated;

grant all on public.plans, public.unit_plans, public.plan_features,
  public.customization_groups, public.customization_options, public.option_compatibilities,
  public.customization_windows, public.unit_configuration_state,
  public.customer_customizations, public.customization_history to service_role;

create policy readable_unit_plans on public.unit_plans for select to authenticated
  using (exists (select 1 from public.units u where u.id = unit_plans.unit_id));

create policy readable_plans on public.plans for select to authenticated
  using (exists (select 1 from public.unit_plans up where up.plan_id = plans.id));

create policy readable_plan_features on public.plan_features for select to authenticated
  using (exists (select 1 from public.plans p where p.id = plan_features.plan_id));

create policy readable_compatibilities on public.option_compatibilities for select to authenticated
  using (exists (select 1 from public.unit_plans up where up.plan_id = option_compatibilities.plan_id));

create policy readable_options on public.customization_options for select to authenticated
  using (exists (select 1 from public.option_compatibilities oc where oc.option_id = customization_options.id));

create policy readable_groups on public.customization_groups for select to authenticated
  using (exists (select 1 from public.customization_options o where o.group_id = customization_groups.id));

create policy readable_windows on public.customization_windows for select to authenticated
  using (exists (select 1 from public.units u where u.id = customization_windows.unit_id));

create policy readable_configuration on public.unit_configuration_state for select to authenticated
  using (exists (select 1 from public.units u where u.id = unit_configuration_state.unit_id));

create policy readable_customizations on public.customer_customizations for select to authenticated
  using (exists (select 1 from public.units u where u.id = customer_customizations.unit_id));

create policy readable_customization_history on public.customization_history for select to authenticated
  using (exists (select 1 from public.units u where u.id = customization_history.unit_id));

-- Substitui integralmente as escolhas de uma unidade em uma única transação.
-- A revisão impede sobrescrita silenciosa entre sessões e coproprietários.
create function public.save_unit_configuration(
  p_customer_id uuid,
  p_unit_id uuid,
  p_plan_id uuid,
  p_option_ids uuid[],
  p_expected_revision integer
) returns public.unit_configuration_state
language plpgsql security definer set search_path = '' as $$
declare
  v_state public.unit_configuration_state;
  v_role text;
  v_count integer;
  v_distinct_groups integer;
  v_selections jsonb;
begin
  if (select auth.uid()) is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select cu.ownership_role into v_role
  from public.customer_units cu
  join public.customer_users usr on usr.customer_id = cu.customer_id and usr.active
  join public.units u on u.id = cu.unit_id and u.active
  where cu.customer_id = p_customer_id and cu.unit_id = p_unit_id
    and cu.active and usr.user_id = (select auth.uid());
  if v_role not in ('owner', 'co_owner') or v_role is null then
    raise exception 'Unit access denied' using errcode = '42501';
  end if;
  if p_plan_id is null or p_option_ids is null or p_expected_revision is null
      or p_expected_revision < 0 then
    raise exception 'Invalid configuration' using errcode = '22023';
  end if;
  if not exists (
    select 1 from public.unit_plans up
    join public.plans p on p.id = up.plan_id
    where up.unit_id = p_unit_id and up.plan_id = p_plan_id
      and up.status = 'available' and p.status = 'active'
  ) then
    raise exception 'Plan unavailable for unit' using errcode = '22023';
  end if;
  if not exists (
    select 1 from public.customization_windows w
    where w.unit_id = p_unit_id and w.status = 'active'
      and statement_timestamp() >= w.opens_at and statement_timestamp() < w.closes_at
  ) then
    raise exception 'Customization window closed' using errcode = '42501';
  end if;

  select count(*), count(distinct o.group_id),
         coalesce(jsonb_object_agg(o.group_id::text, o.id::text), '{}'::jsonb)
    into v_count, v_distinct_groups, v_selections
  from unnest(p_option_ids) as selected(option_id)
  join public.customization_options o on o.id = selected.option_id and o.status = 'active'
  join public.customization_groups g on g.id = o.group_id and g.status = 'active'
  join public.option_compatibilities oc on oc.option_id = o.id and oc.plan_id = p_plan_id;
  if v_count <> cardinality(p_option_ids) or v_count <> v_distinct_groups then
    raise exception 'Invalid or duplicate customization option' using errcode = '22023';
  end if;

  insert into public.unit_configuration_state(unit_id)
    values (p_unit_id) on conflict (unit_id) do nothing;
  select * into v_state from public.unit_configuration_state
    where unit_id = p_unit_id for update;
  if v_state.revision <> p_expected_revision then
    raise exception 'Configuration changed in another session' using errcode = '40001';
  end if;
  if v_state.status <> 'draft' then
    raise exception 'Configuration is not editable' using errcode = '42501';
  end if;

  delete from public.customer_customizations where unit_id = p_unit_id;
  update public.unit_configuration_state
    set plan_id = p_plan_id, revision = revision + 1,
        updated_by = (select auth.uid()), updated_at = now()
    where unit_id = p_unit_id returning * into v_state;
  insert into public.customer_customizations
    (unit_id, group_id, option_id, plan_id, customer_id, revision)
  select p_unit_id, o.group_id, o.id, p_plan_id, p_customer_id, v_state.revision
  from unnest(p_option_ids) as selected(option_id)
  join public.customization_options o on o.id = selected.option_id;
  insert into public.customization_history
    (unit_id, revision, plan_id, selections, actor_customer_id,
     actor_user_id, actor_ownership_role, action)
  values (p_unit_id, v_state.revision, p_plan_id, v_selections,
          p_customer_id, (select auth.uid()), v_role, 'draft_saved');
  return v_state;
end;
$$;

revoke all on function public.save_unit_configuration(uuid, uuid, uuid, uuid[], integer)
  from public, anon;

grant execute on function public.save_unit_configuration(uuid, uuid, uuid, uuid[], integer)
  to authenticated;
