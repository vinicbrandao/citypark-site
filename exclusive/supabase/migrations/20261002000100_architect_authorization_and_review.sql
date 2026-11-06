-- A team assignment and a customer's authorization are separate requirements.
-- Existing assignments are intentionally not backfilled as customer consent.

create table public.architect_authorizations (
  unit_id uuid not null references public.units(id),
  architect_user_id uuid not null references public.staff_users(user_id),
  granted_by_customer_id uuid not null,
  granted_by_user_id uuid not null references auth.users(id),
  active boolean not null default true,
  granted_at timestamptz not null default now(),
  revoked_by_user_id uuid references auth.users(id),
  revoked_at timestamptz,
  updated_at timestamptz not null default now(),
  primary key (unit_id, architect_user_id),
  foreign key (granted_by_customer_id, unit_id)
    references public.customer_units(customer_id, unit_id),
  check ((active and revoked_at is null and revoked_by_user_id is null)
    or (not active and revoked_at is not null and revoked_by_user_id is not null))
);

create index architect_authorizations_architect_active_idx
  on public.architect_authorizations(architect_user_id, unit_id) where active;

create table public.architect_authorization_events (
  id bigint generated always as identity primary key,
  unit_id uuid not null references public.units(id),
  architect_user_id uuid not null references public.staff_users(user_id),
  actor_customer_id uuid not null,
  actor_user_id uuid not null references auth.users(id),
  action text not null check (action in ('granted', 'revoked')),
  created_at timestamptz not null default now(),
  foreign key (actor_customer_id, unit_id)
    references public.customer_units(customer_id, unit_id)
);

create index architect_authorization_events_unit_idx
  on public.architect_authorization_events(unit_id, created_at desc, id desc);

alter table public.architect_authorizations enable row level security;

alter table public.architect_authorization_events enable row level security;

revoke all on public.architect_authorizations, public.architect_authorization_events
  from anon, authenticated;

grant select on public.architect_authorizations, public.architect_authorization_events
  to authenticated;

grant all on public.architect_authorizations, public.architect_authorization_events
  to service_role;

create policy readable_architect_authorizations on public.architect_authorizations
  for select to authenticated using (
    architect_user_id = (select auth.uid())
    or (select public.current_staff_role()) = 'admin'
    or exists (
      select 1 from public.customer_units cu
      join public.customer_users usr on usr.customer_id = cu.customer_id and usr.active
      join public.units u on u.id = cu.unit_id and u.active
      where cu.unit_id = architect_authorizations.unit_id and cu.active
        and usr.user_id = (select auth.uid())
    )
  );

create policy readable_architect_authorization_events on public.architect_authorization_events
  for select to authenticated using (
    architect_user_id = (select auth.uid())
    or (select public.current_staff_role()) = 'admin'
    or exists (
      select 1 from public.customer_units cu
      join public.customer_users usr on usr.customer_id = cu.customer_id and usr.active
      join public.units u on u.id = cu.unit_id and u.active
      where cu.unit_id = architect_authorization_events.unit_id and cu.active
        and usr.user_id = (select auth.uid())
    )
  );

create or replace function public.staff_can_access_unit(p_unit_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.staff_users s
    join public.units u on u.id = p_unit_id and u.active
    where s.user_id = (select auth.uid()) and s.active
      and (s.role = 'admin' or (
        s.role = 'architect' and exists (
          select 1 from public.staff_unit_assignments a
          join public.architect_authorizations consent
            on consent.unit_id = a.unit_id
           and consent.architect_user_id = a.user_id and consent.active
          where a.user_id = s.user_id and a.unit_id = p_unit_id and a.active
        )
      ))
  );
$$;

-- Only eligible, assigned architects are offered to the customer.
create function public.list_unit_architects(p_unit_id uuid)
returns table (user_id uuid, name text, authorized boolean)
language plpgsql stable security definer set search_path = '' as $$
begin
  if not exists (
    select 1 from public.customer_units cu
    join public.customer_users usr on usr.customer_id = cu.customer_id and usr.active
    join public.units u on u.id = cu.unit_id and u.active
    where cu.unit_id = p_unit_id and cu.active
      and cu.ownership_role in ('owner', 'co_owner')
      and usr.user_id = (select auth.uid())
  ) then
    raise exception 'Unit access denied' using errcode = '42501';
  end if;
  return query
    select s.user_id, s.name, coalesce(consent.active, false)
    from public.staff_unit_assignments a
    join public.staff_users s on s.user_id = a.user_id
      and s.role = 'architect' and s.active
    left join public.architect_authorizations consent
      on consent.unit_id = a.unit_id and consent.architect_user_id = a.user_id
    where a.unit_id = p_unit_id and a.active
    order by s.name, s.user_id;
end;
$$;

revoke all on function public.list_unit_architects(uuid) from public, anon;

grant execute on function public.list_unit_architects(uuid) to authenticated;

create function public.set_architect_authorization(
  p_customer_id uuid, p_unit_id uuid, p_architect_user_id uuid, p_active boolean
) returns public.architect_authorizations
language plpgsql security definer set search_path = '' as $$
declare
  v_role text;
  v_row public.architect_authorizations;
begin
  select cu.ownership_role into v_role
  from public.customer_units cu
  join public.customer_users usr on usr.customer_id = cu.customer_id and usr.active
  join public.units u on u.id = cu.unit_id and u.active
  where cu.customer_id = p_customer_id and cu.unit_id = p_unit_id
    and cu.active and usr.user_id = (select auth.uid());
  if v_role not in ('owner', 'co_owner') or v_role is null then
    raise exception 'Unit access denied' using errcode = '42501';
  end if;
  if p_active is null then
    raise exception 'Invalid authorization state' using errcode = '22023';
  end if;
  if p_active and not exists (
    select 1 from public.staff_unit_assignments a
    join public.staff_users s on s.user_id = a.user_id
    where a.unit_id = p_unit_id and a.user_id = p_architect_user_id
      and a.active and s.active and s.role = 'architect'
  ) then
    raise exception 'Architect is not assigned to unit' using errcode = '22023';
  end if;
  -- Serialize changes to the same unit, including owner/co-owner actions.
  perform 1 from public.units where id = p_unit_id for update;
  select * into v_row from public.architect_authorizations
    where unit_id = p_unit_id and architect_user_id = p_architect_user_id for update;
  if p_active and (v_row.unit_id is null or not v_row.active) then
    insert into public.architect_authorizations
      (unit_id, architect_user_id, granted_by_customer_id, granted_by_user_id,
       active, granted_at, revoked_by_user_id, revoked_at, updated_at)
    values (p_unit_id, p_architect_user_id, p_customer_id, (select auth.uid()),
            true, now(), null, null, now())
    on conflict (unit_id, architect_user_id) do update
      set granted_by_customer_id = excluded.granted_by_customer_id,
          granted_by_user_id = excluded.granted_by_user_id,
          active = true, granted_at = now(), revoked_by_user_id = null,
          revoked_at = null, updated_at = now()
    returning * into v_row;
    insert into public.architect_authorization_events
      (unit_id, architect_user_id, actor_customer_id, actor_user_id, action)
    values (p_unit_id, p_architect_user_id, p_customer_id,
            (select auth.uid()), 'granted');
  elsif not p_active and v_row.unit_id is not null and v_row.active then
    update public.architect_authorizations
      set active = false, revoked_by_user_id = (select auth.uid()),
          revoked_at = now(), updated_at = now()
      where unit_id = p_unit_id and architect_user_id = p_architect_user_id
      returning * into v_row;
    insert into public.architect_authorization_events
      (unit_id, architect_user_id, actor_customer_id, actor_user_id, action)
    values (p_unit_id, p_architect_user_id, p_customer_id,
            (select auth.uid()), 'revoked');
  end if;
  return v_row;
end;
$$;

revoke all on function public.set_architect_authorization(uuid, uuid, uuid, boolean)
  from public, anon;

grant execute on function public.set_architect_authorization(uuid, uuid, uuid, boolean)
  to authenticated;

-- A review references the immutable snapshot of exactly one saved revision.
create table public.configuration_reviews (
  unit_id uuid not null,
  revision integer not null check (revision > 0),
  decision text not null check (decision in ('approved', 'changes_requested')),
  note text check (note is null or length(note) <= 2000),
  reviewer_user_id uuid not null references public.staff_users(user_id),
  reviewed_at timestamptz not null default now(),
  primary key (unit_id, revision),
  foreign key (unit_id, revision)
    references public.customization_history(unit_id, revision),
  check (decision <> 'changes_requested' or (note is not null and length(btrim(note)) > 0))
);

create index configuration_reviews_reviewer_idx
  on public.configuration_reviews(reviewer_user_id, reviewed_at desc);

alter table public.configuration_reviews enable row level security;

revoke all on public.configuration_reviews from anon, authenticated;

grant select on public.configuration_reviews to authenticated;

grant all on public.configuration_reviews to service_role;

create policy readable_configuration_reviews on public.configuration_reviews
  for select to authenticated using (
    exists (select 1 from public.units u where u.id = configuration_reviews.unit_id)
  );

create function public.review_unit_configuration(
  p_unit_id uuid, p_expected_revision integer, p_decision text, p_note text default null
) returns public.configuration_reviews
language plpgsql security definer set search_path = '' as $$
declare
  v_state public.unit_configuration_state;
  v_review public.configuration_reviews;
  v_note text;
begin
  if (select public.current_staff_role()) is distinct from 'architect'
    or not public.staff_can_access_unit(p_unit_id) then
    raise exception 'Technical review denied' using errcode = '42501';
  end if;
  v_note := nullif(btrim(p_note), '');
  if p_expected_revision is null or p_expected_revision <= 0
    or p_decision not in ('approved', 'changes_requested') or p_decision is null
    or length(v_note) > 2000
    or (p_decision = 'changes_requested' and v_note is null) then
    raise exception 'Invalid review' using errcode = '22023';
  end if;
  select * into v_state from public.unit_configuration_state
    where unit_id = p_unit_id for update;
  if v_state.unit_id is null or v_state.revision <> p_expected_revision then
    raise exception 'Configuration changed in another session' using errcode = '40001';
  end if;
  if v_state.status <> 'draft' or v_state.plan_id is null
    or not exists (
      select 1 from public.customization_history h
      where h.unit_id = p_unit_id and h.revision = p_expected_revision
        and h.selection_format = 'catalog_ids'
    ) then
    raise exception 'Complete saved configuration required' using errcode = '22023';
  end if;
  if exists (select 1 from public.configuration_reviews
             where unit_id = p_unit_id and revision = p_expected_revision) then
    raise exception 'Revision already reviewed' using errcode = '23505';
  end if;
  insert into public.configuration_reviews
    (unit_id, revision, decision, note, reviewer_user_id)
  values (p_unit_id, p_expected_revision, p_decision, v_note, (select auth.uid()))
  returning * into v_review;
  return v_review;
end;
$$;

revoke all on function public.review_unit_configuration(uuid, integer, text, text)
  from public, anon;

grant execute on function public.review_unit_configuration(uuid, integer, text, text)
  to authenticated;
