-- An authorization loses effect when the granting customer or login loses
-- the active link to the unit. Another active owner may then grant access.

create function public.current_architect_authorization(
  p_unit_id uuid, p_architect_user_id uuid
) returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.architect_authorizations consent
    join public.customer_units cu
      on cu.customer_id = consent.granted_by_customer_id
     and cu.unit_id = consent.unit_id and cu.active
    join public.customer_users usr
      on usr.customer_id = cu.customer_id
     and usr.user_id = consent.granted_by_user_id and usr.active
    where consent.unit_id = p_unit_id
      and consent.architect_user_id = p_architect_user_id and consent.active
  );
$$;

revoke all on function public.current_architect_authorization(uuid, uuid)
  from public, anon, authenticated;

create or replace function public.staff_can_access_unit(p_unit_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.staff_users s
    join public.units u on u.id = p_unit_id and u.active
    where s.user_id = (select auth.uid()) and s.active
      and (s.role = 'admin' or (
        s.role = 'architect' and exists (
          select 1 from public.staff_unit_assignments a
          where a.user_id = s.user_id and a.unit_id = p_unit_id and a.active
            and public.current_architect_authorization(p_unit_id, s.user_id)
        )
      ))
  );
$$;

create or replace function public.list_unit_architects(p_unit_id uuid)
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
    select s.user_id, s.name,
      public.current_architect_authorization(a.unit_id, a.user_id)
    from public.staff_unit_assignments a
    join public.staff_users s on s.user_id = a.user_id
      and s.role = 'architect' and s.active
    where a.unit_id = p_unit_id and a.active
    order by s.name, s.user_id;
end;
$$;

create or replace function public.set_architect_authorization(
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
  perform 1 from public.units where id = p_unit_id for update;
  select * into v_row from public.architect_authorizations
    where unit_id = p_unit_id and architect_user_id = p_architect_user_id for update;
  if p_active and (v_row.unit_id is null
    or not public.current_architect_authorization(p_unit_id, p_architect_user_id)) then
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
