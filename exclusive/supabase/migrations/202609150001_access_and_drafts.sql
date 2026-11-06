-- Access is granted by the team, never by a public signup or client UPDATE.
create table public.customers (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  created_at timestamptz not null default now()
);
create table public.customer_users (
  customer_id uuid not null references public.customers(id),
  user_id uuid not null references auth.users(id) on delete cascade,
  active boolean not null default true,
  primary key (customer_id, user_id)
);
create index customer_users_user_idx on public.customer_users(user_id);
create table public.units (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  tower text not null,
  floor_label text not null,
  termination text not null,
  typology text not null,
  active boolean not null default true,
  created_at timestamptz not null default now()
);
create table public.customer_units (
  customer_id uuid not null references public.customers(id),
  unit_id uuid not null references public.units(id),
  active boolean not null default true,
  primary key (customer_id, unit_id)
);
create index customer_units_unit_idx on public.customer_units(unit_id);
create table public.unit_drafts (
  unit_id uuid primary key references public.units(id),
  selections jsonb not null default '{}'::jsonb check (jsonb_typeof(selections) = 'object'),
  revision integer not null default 1 check (revision > 0),
  updated_by uuid not null references auth.users(id),
  updated_at timestamptz not null default now()
);

alter table public.customers enable row level security;
alter table public.customer_users enable row level security;
alter table public.units enable row level security;
alter table public.customer_units enable row level security;
alter table public.unit_drafts enable row level security;

revoke all on public.customers, public.customer_users, public.units, public.customer_units, public.unit_drafts from anon, authenticated;
grant select on public.customers, public.customer_users, public.units, public.customer_units, public.unit_drafts to authenticated;
grant all on public.customers, public.customer_users, public.units, public.customer_units, public.unit_drafts to service_role;

create policy own_customer_links on public.customer_users for select to authenticated
  using (user_id = (select auth.uid()) and active);
create policy own_customers on public.customers for select to authenticated
  using (exists (select 1 from public.customer_users cu where cu.customer_id = customers.id));
create policy own_unit_links on public.customer_units for select to authenticated
  using (active and exists (select 1 from public.customer_users cu where cu.customer_id = customer_units.customer_id));
create policy own_units on public.units for select to authenticated
  using (active and exists (select 1 from public.customer_units cu where cu.unit_id = units.id));
create policy own_drafts on public.unit_drafts for select to authenticated
  using (exists (select 1 from public.units u where u.id = unit_drafts.unit_id));

-- Atomic save with optimistic locking. Prices and confirmed status are not client inputs.
create function public.save_unit_draft(p_unit_id uuid, p_selections jsonb, p_expected_revision integer)
returns public.unit_drafts
language plpgsql security definer set search_path = '' as $$
declare
  result public.unit_drafts;
  item record;
begin
  if auth.uid() is null or not exists (
    select 1 from public.units u
    join public.customer_units cu on cu.unit_id = u.id and cu.active
    join public.customer_users usr on usr.customer_id = cu.customer_id and usr.active
    where u.id = p_unit_id and u.active and usr.user_id = auth.uid()
  ) then raise exception 'Unit access denied' using errcode = '42501'; end if;
  if p_expected_revision is null or p_expected_revision < 0
     or p_selections is null or jsonb_typeof(p_selections) <> 'object' then
    raise exception 'Invalid draft' using errcode = '22023';
  end if;
  -- Initial catalog allowlist; migrate to a versioned catalog before confirmation.
  for item in select * from jsonb_each(p_selections) loop
    if not (case item.key
      when 'socialPlant' then item.value in ('null'::jsonb, '"social-standard"', '"social-veranda"', '"social-full"')
      when 'suitePlant' then item.value in ('null'::jsonb, '"suite-standard"', '"suite-closet"', '"suite-office"')
      when 'counter' then item.value in ('"counter-standard"'::jsonb, '"counter-extended"')
      when 'stone' then item.value in ('"sao-marco"'::jsonb, '"bellagio"')
      when 'rodamao' then item.value in ('"padrao"'::jsonb, '"60"')
      when 'service' then item.value in ('"service-no"'::jsonb, '"service-yes"')
      else false end) then raise exception 'Invalid selection' using errcode = '22023'; end if;
  end loop;
  if not (p_selections ?& array['socialPlant','suitePlant','counter','stone','rodamao','service']) then
    raise exception 'Incomplete draft' using errcode = '22023';
  end if;
  if p_expected_revision = 0 then
    insert into public.unit_drafts(unit_id, selections, updated_by)
    values (p_unit_id, p_selections, auth.uid())
    on conflict (unit_id) do nothing returning * into result;
  else
    update public.unit_drafts
    set selections = p_selections, revision = revision + 1, updated_by = auth.uid(), updated_at = now()
    where unit_id = p_unit_id and revision = p_expected_revision returning * into result;
  end if;
  if result.unit_id is null then raise exception 'Draft changed in another session' using errcode = '40001'; end if;
  return result;
end;
$$;
revoke all on function public.save_unit_draft(uuid, jsonb, integer) from public, anon;
grant execute on function public.save_unit_draft(uuid, jsonb, integer) to authenticated;
