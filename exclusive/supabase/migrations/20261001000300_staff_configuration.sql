-- Staff edits the same unit configuration as customers. Architects are scoped
-- to explicit assignments; admins can attend any active unit.

create table public.staff_unit_assignments (
  user_id uuid not null references public.staff_users(user_id) on delete cascade,
  unit_id uuid not null references public.units(id),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  primary key (user_id, unit_id)
);

create index staff_unit_assignments_unit_idx
  on public.staff_unit_assignments(unit_id, user_id) where active;

alter table public.staff_unit_assignments enable row level security;

revoke all on public.staff_unit_assignments from anon, authenticated;

grant select on public.staff_unit_assignments to authenticated;

grant all on public.staff_unit_assignments to service_role;

create policy readable_staff_assignments on public.staff_unit_assignments
  for select to authenticated using (
    (select public.current_staff_role()) = 'admin'
    or (user_id = (select auth.uid()) and (select public.current_staff_role()) = 'architect')
  );

create function public.staff_can_access_unit(p_unit_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.staff_users s
    where s.user_id = (select auth.uid()) and s.active
      and (s.role = 'admin' or (
        s.role = 'architect' and exists (
          select 1 from public.staff_unit_assignments a
          where a.user_id = s.user_id and a.unit_id = p_unit_id and a.active
        )
      ))
  );
$$;

revoke all on function public.staff_can_access_unit(uuid) from public, anon;

grant execute on function public.staff_can_access_unit(uuid) to authenticated;

drop policy staff_units on public.units;

create policy staff_units on public.units for select to authenticated
  using (active and public.staff_can_access_unit(id));

drop policy staff_drafts on public.unit_drafts;

create policy staff_drafts on public.unit_drafts for select to authenticated
  using (public.staff_can_access_unit(unit_id));

drop policy staff_history on public.draft_history;

create policy staff_history on public.draft_history for select to authenticated
  using (public.staff_can_access_unit(unit_id));

-- The legacy RPC remains available during migration, but cannot be used by an
-- architect to bypass the new assignment rule.
create function public.guard_legacy_architect_draft()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if (select public.current_staff_role()) = 'architect'
    and not public.staff_can_access_unit(new.unit_id) then
    raise exception 'Unit access denied' using errcode = '42501';
  end if;
  return new;
end;
$$;

revoke all on function public.guard_legacy_architect_draft() from public, anon, authenticated;

create trigger guard_legacy_architect_draft_before_write
  before insert or update on public.unit_drafts
  for each row execute function public.guard_legacy_architect_draft();

-- The customer_id on a current choice identifies the active purchasing link
-- represented by the choice. updated_by and history identify the actual actor.
alter table public.customer_customizations
  add column updated_by uuid references auth.users(id);

update public.customer_customizations cc
  set updated_by = h.actor_user_id
  from public.customization_history h
  where h.unit_id = cc.unit_id and h.revision = cc.revision;

create function public.record_customization_actor()
returns trigger language plpgsql set search_path = '' as $$
begin
  if new.updated_by is null then new.updated_by = (select auth.uid()); end if;
  return new;
end;
$$;

revoke all on function public.record_customization_actor() from public, anon, authenticated;

create trigger record_customization_actor_before_insert
  before insert on public.customer_customizations
  for each row execute function public.record_customization_actor();

alter table public.customization_history
  alter column actor_customer_id drop not null,
  alter column actor_ownership_role drop not null,
  add column actor_staff_role text check (actor_staff_role in ('admin', 'architect')),
  add constraint customization_history_actor_kind_check check (
    (actor_customer_id is not null and actor_ownership_role is not null and actor_staff_role is null)
    or (actor_customer_id is null and actor_ownership_role is null and actor_staff_role is not null)
  );

create function public.save_staff_unit_configuration(
  p_unit_id uuid,
  p_plan_id uuid,
  p_option_ids uuid[],
  p_partial_selections jsonb,
  p_expected_revision integer
) returns public.unit_configuration_state
language plpgsql security definer set search_path = '' as $$
declare
  v_state public.unit_configuration_state;
  v_staff_role text;
  v_customer_id uuid;
  v_count integer;
  v_distinct_groups integer;
  v_selections jsonb;
  v_key text;
  v_value jsonb;
begin
  v_staff_role := public.current_staff_role();
  if v_staff_role not in ('admin', 'architect') or v_staff_role is null
    or not public.staff_can_access_unit(p_unit_id)
    or not exists (select 1 from public.units u where u.id = p_unit_id and u.active) then
    raise exception 'Unit access denied' using errcode = '42501';
  end if;
  if p_expected_revision is null or p_expected_revision < 0 then
    raise exception 'Invalid revision' using errcode = '22023';
  end if;
  select cu.customer_id into v_customer_id
  from public.customer_units cu
  where cu.unit_id = p_unit_id and cu.active
  order by (cu.ownership_role = 'owner') desc, cu.created_at, cu.customer_id
  limit 1;
  if v_customer_id is null then
    raise exception 'Unit has no active purchasing link' using errcode = '22023';
  end if;

  if p_plan_id is null then
    if p_option_ids is not null or jsonb_typeof(p_partial_selections) is distinct from 'object'
      or not (p_partial_selections ?& array['socialPlant','suitePlant','counter','stone','rodamao','service'])
      or (select count(*) from jsonb_object_keys(p_partial_selections)) <> 6
      or (p_partial_selections->'socialPlant' <> 'null'::jsonb
        and p_partial_selections->'suitePlant' <> 'null'::jsonb) then
      raise exception 'Invalid partial configuration' using errcode = '22023';
    end if;
    for v_key, v_value in select key, value from jsonb_each(p_partial_selections) loop
      if v_key in ('socialPlant', 'suitePlant') then
        if jsonb_typeof(v_value) not in ('null', 'string') then
          raise exception 'Invalid plant choice' using errcode = '22023';
        end if;
      elsif jsonb_typeof(v_value) <> 'string' then
        raise exception 'Invalid material choice' using errcode = '22023';
      end if;
    end loop;
    if not exists (
      select 1 from public.unit_plans up
      join public.plans p on p.id = up.plan_id and p.status = 'active'
      where up.unit_id = p_unit_id and up.status = 'available'
        and (p_partial_selections->'socialPlant' = 'null'::jsonb or exists (
          select 1 from public.plan_features pf
          where pf.plan_id = up.plan_id and pf.feature_key = 'social'
            and pf.feature_value->>'choice' = p_partial_selections->>'socialPlant'
        ))
        and (p_partial_selections->'suitePlant' = 'null'::jsonb or exists (
          select 1 from public.plan_features pf
          where pf.plan_id = up.plan_id and pf.feature_key = 'suite'
            and pf.feature_value->>'choice' = p_partial_selections->>'suitePlant'
        ))
        and not exists (
          select 1 from jsonb_each_text(p_partial_selections) as chosen(key, value)
          where chosen.key in ('counter','stone','rodamao','service')
            and not exists (
              select 1 from public.customization_groups g
              join public.customization_options o on o.group_id = g.id
              join public.option_compatibilities oc on oc.option_id = o.id
              where g.code = chosen.key and g.status = 'active'
                and o.code = chosen.value and o.status = 'active'
                and oc.plan_id = up.plan_id
            )
        )
    ) then
      raise exception 'Choices are not available together for this unit'
        using errcode = '22023';
    end if;
    v_selections := p_partial_selections;
  else
    if p_partial_selections is not null or p_option_ids is null or not exists (
      select 1 from public.unit_plans up
      join public.plans p on p.id = up.plan_id
      where up.unit_id = p_unit_id and up.plan_id = p_plan_id
        and up.status = 'available' and p.status = 'active'
    ) then
      raise exception 'Invalid or unavailable plan' using errcode = '22023';
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
  if not exists (
    select 1 from public.customization_windows w
    where w.unit_id = p_unit_id and w.status = 'active'
      and clock_timestamp() >= w.opens_at and clock_timestamp() < w.closes_at
  ) then
    raise exception 'Customization window closed' using errcode = '42501';
  end if;

  delete from public.customer_customizations where unit_id = p_unit_id;
  update public.unit_configuration_state
    set plan_id = p_plan_id,
        draft_selections = case when p_plan_id is null then p_partial_selections else '{}'::jsonb end,
        revision = revision + 1, updated_by = (select auth.uid()), updated_at = now()
    where unit_id = p_unit_id returning * into v_state;
  if p_plan_id is not null then
    insert into public.customer_customizations
      (unit_id, group_id, option_id, plan_id, customer_id, revision, updated_by)
    select p_unit_id, o.group_id, o.id, p_plan_id, v_customer_id,
      v_state.revision, (select auth.uid())
    from unnest(p_option_ids) as selected(option_id)
    join public.customization_options o on o.id = selected.option_id;
  end if;
  insert into public.customization_history
    (unit_id, revision, plan_id, selections, actor_customer_id,
     actor_user_id, actor_ownership_role, actor_staff_role, action, selection_format)
  values (p_unit_id, v_state.revision, p_plan_id, v_selections, null,
          (select auth.uid()), null, v_staff_role, 'draft_saved',
          case when p_plan_id is null then 'ui_draft' else 'catalog_ids' end);
  return v_state;
end;
$$;

revoke all on function public.save_staff_unit_configuration(uuid, uuid, uuid[], jsonb, integer)
  from public, anon;

grant execute on function public.save_staff_unit_configuration(uuid, uuid, uuid[], jsonb, integer)
  to authenticated;
