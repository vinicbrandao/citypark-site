create schema commercial_sync;
revoke all on schema commercial_sync from public, anon, authenticated;

create table commercial_sync.snapshot (
  singleton boolean primary key default true check (singleton),
  captured_at timestamptz not null,
  units jsonb not null
);

create table commercial_sync.owner_reviews (
  unit_id uuid primary key references public.units(id),
  revision timestamptz not null
);

create function public.sync_commercial_inventory(p_captured_at timestamptz, p_units jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
  inventory jsonb;
  received integer;
  matched integer;
  previous_inventory jsonb;
  previous_capture timestamptz;
begin
  if p_captured_at is null or not isfinite(p_captured_at)
     or p_captured_at > clock_timestamp() + interval '1 minute'
     or p_captured_at < clock_timestamp() - interval '15 minutes' then
    raise exception 'Invalid inventory timestamp' using errcode='22023';
  end if;
  if jsonb_typeof(p_units) is distinct from 'array' then
    raise exception 'Inventory must be an array' using errcode='22023';
  end if;
  received := jsonb_array_length(p_units);
  if received not between 1 and 1500 then
    raise exception 'Invalid inventory size' using errcode='22023';
  end if;

  with source as (
    select regexp_replace(upper(btrim(item->>'unidade')), '[[:space:]]+', '', 'g') as code,
           item->>'status' as status,
           item->>'vendidoEm' as sold_at
    from jsonb_array_elements(p_units) as entries(item)
    where btrim(item->>'unidade') ~* '^[0-9]{3,4}[[:space:]]*[AB]$'
  ), matched_units as (
    select u.code, count(*) as occurrences,
           bool_and(coalesce(s.status = 'vendida', false)) as eligible,
           max(s.sold_at) as sold_at
    from source s join public.units u on u.code = s.code
    group by u.code
  )
  select jsonb_object_agg(code, jsonb_build_object('eligible', occurrences = 1 and eligible, 'soldAt', sold_at)), count(*)
  into inventory, matched from matched_units;

  if matched = 0 then
    raise exception 'No matching units' using errcode='22023';
  end if;

  perform pg_advisory_xact_lock(671101, 1);
  select captured_at, units into previous_capture, previous_inventory from commercial_sync.snapshot;
  if previous_capture >= p_captured_at then
    return jsonb_build_object('saved', false, 'received', received, 'matched', matched);
  end if;

  insert into commercial_sync.owner_reviews(unit_id, revision)
  select u.id, p_captured_at from public.units u
  where previous_inventory->u.code->'eligible' = 'true'::jsonb
    and (
      inventory->u.code->'eligible' is distinct from 'true'::jsonb
      or (inventory->u.code->>'soldAt' is not null
          and (previous_inventory->u.code->>'soldAt') is distinct from (inventory->u.code->>'soldAt'))
    )
  on conflict (unit_id) do update set revision = excluded.revision;

  insert into commercial_sync.snapshot (captured_at, units)
  values (p_captured_at, inventory)
  on conflict (singleton) do update set captured_at = excluded.captured_at, units = excluded.units;

  return jsonb_build_object('saved', true, 'received', received, 'matched', matched);
end;
$$;
revoke all on function public.sync_commercial_inventory(timestamptz, jsonb) from public, anon, authenticated;
grant execute on function public.sync_commercial_inventory(timestamptz, jsonb) to service_role;
-- Enabling the gate is a separate database operation after reconciliation.
create table commercial_sync.settings (
  singleton boolean primary key default true check (singleton),
  enabled boolean not null default false
);
insert into commercial_sync.settings default values;

create function commercial_sync.unit_allowed(p_code text)
returns boolean language sql stable security definer set search_path='' as $$
  select not settings.enabled or coalesce(
    snapshot.units->p_code->'eligible' = 'true'::jsonb
      and not exists (select 1 from commercial_sync.owner_reviews review
        join public.units u on u.id = review.unit_id where u.code = p_code),
    false)
  from commercial_sync.settings settings
  left join commercial_sync.snapshot snapshot using (singleton);
$$;
revoke all on function commercial_sync.unit_allowed(text) from public, anon, authenticated;

create or replace function public.customer_can_access_unit(p_unit_id uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.units u
   join public.customer_units cu on cu.unit_id=u.id and cu.active and cu.ownership_role='owner'
   join public.customer_users usr on usr.customer_id=cu.customer_id and usr.active
   join public.customers c on c.id=cu.customer_id and c.active
   where u.id=p_unit_id and u.active and usr.user_id=(select auth.uid())
     and commercial_sync.unit_allowed(u.code));
$$;

create or replace function public.list_customer_unit_cards()
returns table(id uuid,code text,tower text,tower_code text,floor_label text,termination text,typology text,
 area_m2 numeric,customization_closes_at timestamptz,active boolean,customization_status text)
language sql stable security definer set search_path='' as $$
 select u.id,u.code,u.tower,u.tower_code,u.floor_label,u.termination,u.typology,u.area_m2,
   u.customization_closes_at,u.active and commercial_sync.unit_allowed(u.code),u.customization_status from public.units u
 where public.current_account_active() and exists(select 1 from public.customer_units cu
   join public.customer_users usr on usr.customer_id=cu.customer_id and usr.active
   where cu.unit_id=u.id and cu.active and cu.ownership_role='owner' and usr.user_id=(select auth.uid())) order by u.code;
$$;
create function public.list_commercial_owner_reviews()
returns table(unit_id uuid, revision timestamptz)
language sql stable security definer set search_path='' as $$
  select review.unit_id, review.revision
  from commercial_sync.owner_reviews review
  join public.units u on u.id = review.unit_id
  cross join commercial_sync.settings settings
  join commercial_sync.snapshot snapshot using (singleton)
  where public.current_staff_role() = 'admin' and settings.enabled
    and snapshot.units->u.code->'eligible' = 'true'::jsonb;
$$;

create function public.confirm_commercial_owner(p_unit_id uuid, p_customer_id uuid, p_revision timestamptz)
returns void language plpgsql security definer set search_path='' as $$
declare unit_code text;
begin
  if public.current_staff_role() is distinct from 'admin' then
    raise exception 'Confirmação disponível apenas para administradores.' using errcode='42501';
  end if;
  perform pg_advisory_xact_lock(671101, 1);
  select code into unit_code from public.units where id = p_unit_id for update;
  if not exists (
    select 1 from commercial_sync.snapshot snapshot
    join commercial_sync.settings settings using (singleton)
    where settings.enabled and snapshot.units->unit_code->'eligible' = 'true'::jsonb
  ) or not exists (
    select 1 from public.customer_units cu join public.customers c on c.id = cu.customer_id
    where cu.unit_id = p_unit_id and cu.customer_id = p_customer_id
      and cu.active and cu.ownership_role = 'owner' and c.active
  ) then
    raise exception 'Confira a venda e o cliente atualmente vinculado.' using errcode='22023';
  end if;

  delete from commercial_sync.owner_reviews where unit_id = p_unit_id and revision = p_revision;
  if not found then
    raise exception 'A situação comercial mudou. Atualize a página e confira novamente.' using errcode='22023';
  end if;
  insert into public.unit_activity_events(unit_id, actor_user_id, actor_role, action, details)
  values (p_unit_id, auth.uid(), 'admin', 'commercial_owner_confirmed', jsonb_build_object('customer_id', p_customer_id));
end;
$$;
revoke all on function public.list_commercial_owner_reviews(), public.confirm_commercial_owner(uuid, uuid, timestamptz) from public, anon;
grant execute on function public.list_commercial_owner_reviews(), public.confirm_commercial_owner(uuid, uuid, timestamptz) to authenticated;
