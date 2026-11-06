-- Customers may see the status card of their inactive units, while the units
-- RLS and configurator RPCs continue to require an active unit.
create function public.list_customer_unit_cards()
returns table (
  id uuid, code text, tower text, tower_code text, floor_label text,
  termination text, typology text, area_m2 numeric,
  customization_closes_at timestamptz, active boolean, customization_status text
)
language sql stable security definer set search_path = '' as $$
  select u.id,u.code,u.tower,u.tower_code,u.floor_label,u.termination,u.typology,
    u.area_m2,u.customization_closes_at,u.active,u.customization_status
  from public.units u
  where exists (
    select 1 from public.customer_units cu
    join public.customer_users usr on usr.customer_id=cu.customer_id and usr.active
    where cu.unit_id=u.id and cu.active and cu.ownership_role='owner'
      and usr.user_id=(select auth.uid())
  )
  order by u.code;
$$;
revoke all on function public.list_customer_unit_cards() from public,anon;
grant execute on function public.list_customer_unit_cards() to authenticated;
