-- Permite salvar progresso antes de escolher as duas partes da planta.
-- A configuração normalizada continua sendo criada pela função anterior
-- quando a escolha da planta estiver completa.

alter table public.unit_configuration_state
  add column draft_selections jsonb not null default '{}'::jsonb
    check (jsonb_typeof(draft_selections) = 'object');

alter table public.unit_configuration_state
  drop constraint unit_configuration_state_check;

alter table public.unit_configuration_state
  add constraint unit_configuration_state_plan_revision_check
    check (revision > 0 or plan_id is null);

alter table public.customization_history
  alter column plan_id drop not null;

alter table public.customization_history
  add column selection_format text not null default 'catalog_ids'
    check (selection_format in ('catalog_ids', 'ui_draft'));

create function public.clear_completed_ui_draft()
returns trigger language plpgsql set search_path = '' as $$
begin
  if new.plan_id is not null then
    new.draft_selections = '{}'::jsonb;
  end if;
  return new;
end;
$$;

revoke all on function public.clear_completed_ui_draft() from public, anon, authenticated;

create trigger clear_completed_ui_draft_before_write
  before insert or update on public.unit_configuration_state
  for each row execute function public.clear_completed_ui_draft();

create function public.save_partial_unit_configuration(
  p_customer_id uuid,
  p_unit_id uuid,
  p_selections jsonb,
  p_expected_revision integer
) returns public.unit_configuration_state
language plpgsql security definer set search_path = '' as $$
declare
  v_state public.unit_configuration_state;
  v_role text;
  v_key text;
  v_value jsonb;
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
  if v_role is null or v_role not in ('owner', 'co_owner') then
    raise exception 'Unit access denied' using errcode = '42501';
  end if;
  if p_expected_revision is null or p_expected_revision < 0
    or jsonb_typeof(p_selections) is distinct from 'object' then
    raise exception 'Invalid partial configuration' using errcode = '22023';
  end if;
  if not (p_selections ?& array['socialPlant','suitePlant','counter','stone','rodamao','service'])
    or (select count(*) from jsonb_object_keys(p_selections)) <> 6
    or (p_selections->'socialPlant' <> 'null'::jsonb
      and p_selections->'suitePlant' <> 'null'::jsonb) then
    raise exception 'Expected six selections with an incomplete plant' using errcode = '22023';
  end if;
  for v_key, v_value in select key, value from jsonb_each(p_selections) loop
    if v_key in ('socialPlant', 'suitePlant') then
      if jsonb_typeof(v_value) not in ('null', 'string') then
        raise exception 'Invalid plant choice' using errcode = '22023';
      end if;
    elsif jsonb_typeof(v_value) <> 'string' then
      raise exception 'Invalid material choice' using errcode = '22023';
    end if;
  end loop;

  -- Todos os materiais devem caber em pelo menos uma planta disponível que
  -- respeite as partes da planta já escolhidas.
  if not exists (
    select 1 from public.unit_plans up
    join public.plans p on p.id = up.plan_id and p.status = 'active'
    where up.unit_id = p_unit_id and up.status = 'available'
      and (p_selections->'socialPlant' = 'null'::jsonb or exists (
        select 1 from public.plan_features pf
        where pf.plan_id = up.plan_id and pf.feature_key = 'social'
          and pf.feature_value->>'choice' = p_selections->>'socialPlant'
      ))
      and (p_selections->'suitePlant' = 'null'::jsonb or exists (
        select 1 from public.plan_features pf
        where pf.plan_id = up.plan_id and pf.feature_key = 'suite'
          and pf.feature_value->>'choice' = p_selections->>'suitePlant'
      ))
      and not exists (
        select 1 from jsonb_each_text(p_selections) as chosen(key, value)
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
    set plan_id = null, draft_selections = p_selections,
        revision = revision + 1, updated_by = (select auth.uid()),
        updated_at = now()
    where unit_id = p_unit_id returning * into v_state;
  insert into public.customization_history
    (unit_id, revision, plan_id, selections, actor_customer_id,
     actor_user_id, actor_ownership_role, action, selection_format)
  values (p_unit_id, v_state.revision, null, p_selections,
          p_customer_id, (select auth.uid()), v_role, 'draft_saved', 'ui_draft');
  return v_state;
end;
$$;

revoke all on function public.save_partial_unit_configuration(uuid, uuid, jsonb, integer)
  from public, anon;

grant execute on function public.save_partial_unit_configuration(uuid, uuid, jsonb, integer)
  to authenticated;
