-- Unit metadata for the customer selection screen. Null means not registered;
-- do not infer either field from the unit code or a module window.
alter table public.units
  add column area_m2 numeric(8,2),
  add column customization_closes_at timestamptz,
  add constraint units_area_m2_positive check (area_m2 is null or area_m2 > 0);

comment on column public.units.area_m2 is 'Apartment area in m², supplied by the team.';
comment on column public.units.customization_closes_at is
  'Exclusive final cutoff for all unit choices and proposal submissions. Module windows may close earlier.';

-- Both RPCs already lock the unit row. Checking immediately before the history
-- or submitted snapshot is inserted rolls back the whole RPC if time has run out.
create function public.guard_unit_customization_deadline()
returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  v_unit_id uuid;
  v_closes_at timestamptz;
begin
  if tg_table_name = 'unit_module_history' then
    v_unit_id := new.unit_id;
  else
    select p.unit_id into v_unit_id from public.unit_proposals p
      where p.id = new.proposal_id;
  end if;
  select u.customization_closes_at into v_closes_at
    from public.units u where u.id = v_unit_id;
  if v_closes_at is not null and clock_timestamp() >= v_closes_at then
    raise exception 'Unit customization deadline reached' using errcode = '42501';
  end if;
  return new;
end;
$$;

revoke all on function public.guard_unit_customization_deadline()
  from public, anon, authenticated;

create trigger guard_unit_final_deadline_on_choices
  before insert on public.unit_module_history
  for each row execute function public.guard_unit_customization_deadline();

create trigger guard_unit_final_deadline_on_submission
  before insert on public.unit_proposal_versions
  for each row execute function public.guard_unit_customization_deadline();
