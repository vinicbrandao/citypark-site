\set ON_ERROR_STOP on
-- Run through psql against the local Supabase DB. All fixtures are rolled back.
begin;

do $$
begin
  if has_function_privilege('authenticated',
      'public.save_unit_draft(uuid,jsonb,integer)', 'EXECUTE')
    or has_function_privilege('authenticated',
      'public.save_unit_configuration(uuid,uuid,uuid,uuid[],integer)', 'EXECUTE')
    or has_function_privilege('authenticated',
      'public.save_partial_unit_configuration(uuid,uuid,jsonb,integer)', 'EXECUTE')
    or has_function_privilege('authenticated',
      'public.save_staff_unit_configuration(uuid,uuid,uuid[],jsonb,integer)', 'EXECUTE') then
    raise exception 'legacy configuration write is still executable';
  end if;
end $$;

select u.id as source_unit_id from public.units u where u.code = '1401A' \gset
select cu.customer_id as owner_customer_id, usr.user_id as owner_user_id
from public.customer_units cu
join public.customer_users usr on usr.customer_id = cu.customer_id and usr.active
where cu.unit_id = :'source_unit_id'::uuid and cu.ownership_role = 'owner' and cu.active \gset
select cu.customer_id as co_customer_id, usr.user_id as co_user_id
from public.customer_units cu
join public.customer_users usr on usr.customer_id = cu.customer_id and usr.active
where cu.unit_id = :'source_unit_id'::uuid and cu.ownership_role = 'co_owner' and cu.active \gset
select cu.customer_id as outsider_customer_id, usr.user_id as outsider_user_id
from public.customer_units cu
join public.customer_users usr on usr.customer_id = cu.customer_id and usr.active
join public.units u on u.id = cu.unit_id and u.code = '1209A'
where cu.active limit 1 \gset
select s.user_id as architect_user_id
from public.staff_users s
join public.staff_unit_assignments a on a.user_id = s.user_id and a.active
where a.unit_id = :'source_unit_id'::uuid and s.role = 'architect' and s.active
  and public.current_architect_authorization(a.unit_id, s.user_id)
limit 1 \gset

-- A fresh unit keeps this test independent from persisted demo proposals.
insert into public.units(code, tower, floor_label, termination, typology)
select 'LOCAL-TEST-' || gen_random_uuid()::text, tower, floor_label, termination, typology
from public.units where id = :'source_unit_id'::uuid
returning id as unit_id \gset
insert into public.customer_units(customer_id, unit_id, ownership_role)
values (:'owner_customer_id'::uuid, :'unit_id'::uuid, 'owner'),
       (:'co_customer_id'::uuid, :'unit_id'::uuid, 'co_owner');
insert into public.staff_unit_assignments(user_id, unit_id)
values (:'architect_user_id'::uuid, :'unit_id'::uuid);
insert into public.architect_authorizations
  (unit_id, architect_user_id, granted_by_customer_id, granted_by_user_id)
values (:'unit_id'::uuid, :'architect_user_id'::uuid,
        :'owner_customer_id'::uuid, :'owner_user_id'::uuid);

insert into public.base_plans(code, name)
values ('module-test-' || gen_random_uuid()::text, 'Temporary test plan')
returning id as plan_id \gset
insert into public.unit_base_plan_assignments(unit_id, base_plan_id)
values (:'unit_id'::uuid, :'plan_id'::uuid);
insert into public.customization_modules(code, name)
values ('materials_test', 'Temporary materials');
insert into public.customization_groups(code, name, module_code)
values ('module-test-' || gen_random_uuid()::text, 'Temporary plant group', 'planta')
returning id as plant_group_id \gset
insert into public.customization_groups(code, name, module_code)
values ('module-test-' || gen_random_uuid()::text, 'Temporary materials group', 'materials_test')
returning id as material_group_id \gset
insert into public.customization_options(group_id, code, name)
values (:'plant_group_id'::uuid, 'option', 'Temporary plant option')
returning id as plant_option_id \gset
insert into public.customization_options(group_id, code, name)
values (:'material_group_id'::uuid, 'good', 'Compatible material')
returning id as material_good_id \gset
insert into public.customization_options(group_id, code, name)
values (:'material_group_id'::uuid, 'bad', 'Incompatible material')
returning id as material_bad_id \gset
insert into public.base_plan_option_availability(base_plan_id, option_id)
values (:'plan_id'::uuid, :'plant_option_id'::uuid),
       (:'plan_id'::uuid, :'material_good_id'::uuid),
       (:'plan_id'::uuid, :'material_bad_id'::uuid);
insert into public.base_plan_option_exclusions
  (base_plan_id, first_option_id, second_option_id)
values (:'plan_id'::uuid,
        least(:'plant_option_id'::uuid, :'material_bad_id'::uuid),
        greatest(:'plant_option_id'::uuid, :'material_bad_id'::uuid));
insert into public.unit_module_windows(unit_id, module_code, opens_at, closes_at)
values (:'unit_id'::uuid, 'planta', clock_timestamp() - interval '1 day',
        clock_timestamp() + interval '1 day'),
       (:'unit_id'::uuid, 'materials_test', clock_timestamp() - interval '1 day',
        clock_timestamp() + interval '1 day');

select set_config('test.unit_id', :'unit_id', true);
select set_config('test.owner_customer_id', :'owner_customer_id', true);
select set_config('test.co_customer_id', :'co_customer_id', true);
select set_config('test.outsider_customer_id', :'outsider_customer_id', true);
select set_config('test.plant_group_id', :'plant_group_id', true);
select set_config('test.plant_option_id', :'plant_option_id', true);
select set_config('test.material_group_id', :'material_group_id', true);
select set_config('test.material_good_id', :'material_good_id', true);
select set_config('test.material_bad_id', :'material_bad_id', true);
select set_config('test.plan_id', :'plan_id', true);

set role authenticated;
select set_config('request.jwt.claim.sub', :'owner_user_id', true);
do $$
declare saved public.unit_module_states;
begin
  saved := public.save_unit_module_choices(
    current_setting('test.owner_customer_id')::uuid,
    current_setting('test.unit_id')::uuid, 'planta',
    jsonb_build_object(current_setting('test.plant_group_id'),
                       current_setting('test.plant_option_id')), 0);
  if saved.revision <> 1 then raise exception 'owner save revision'; end if;
  if (select count(*) from public.unit_module_history
      where unit_id = current_setting('test.unit_id')::uuid) <> 1 then
    raise exception 'history missing';
  end if;
end $$;

select set_config('request.jwt.claim.sub', :'co_user_id', true);
do $$
begin
  begin
    perform public.save_unit_module_choices(
      current_setting('test.co_customer_id')::uuid,
      current_setting('test.unit_id')::uuid, 'planta', '{}'::jsonb, 0);
    raise exception 'stale revision was accepted';
  exception when sqlstate '40001' then null;
  end;
  perform public.save_unit_module_choices(
    current_setting('test.co_customer_id')::uuid,
    current_setting('test.unit_id')::uuid, 'planta',
    jsonb_build_object(current_setting('test.plant_group_id'),
                       current_setting('test.plant_option_id')), 1);
end $$;

select set_config('request.jwt.claim.sub', :'outsider_user_id', true);
do $$
begin
  if (select count(*) from public.unit_module_states
      where unit_id = current_setting('test.unit_id')::uuid) <> 0
    or (select count(*) from public.base_plan_option_availability
        where base_plan_id = current_setting('test.plan_id')::uuid) <> 0 then
    raise exception 'RLS leaked another unit';
  end if;
  begin
    perform public.save_unit_module_choices(
      current_setting('test.outsider_customer_id')::uuid,
      current_setting('test.unit_id')::uuid, 'planta', '{}'::jsonb, 2);
    raise exception 'unrelated client could save';
  exception when sqlstate '42501' then null;
  end;
end $$;

select set_config('request.jwt.claim.sub', :'architect_user_id', true);
do $$
declare saved public.unit_module_states;
begin
  saved := public.save_unit_module_choices(
    null, current_setting('test.unit_id')::uuid, 'planta',
    jsonb_build_object(current_setting('test.plant_group_id'),
                       current_setting('test.plant_option_id')), 2);
  if saved.revision <> 3 then raise exception 'architect save revision'; end if;
end $$;
reset role;
update public.architect_authorizations
set active = false, revoked_by_user_id = :'owner_user_id'::uuid,
    revoked_at = clock_timestamp(), updated_at = clock_timestamp()
where unit_id = :'unit_id'::uuid
  and architect_user_id = :'architect_user_id'::uuid;
set role authenticated;
select set_config('request.jwt.claim.sub', :'architect_user_id', true);
do $$
begin
  begin
    perform public.save_unit_module_choices(
      null, current_setting('test.unit_id')::uuid, 'planta', '{}'::jsonb, 3);
    raise exception 'revoked architect could save';
  exception when sqlstate '42501' then null;
  end;
end $$;

select set_config('request.jwt.claim.sub', :'owner_user_id', true);
do $$
begin
  begin
    perform public.save_unit_module_choices(
      current_setting('test.owner_customer_id')::uuid,
      current_setting('test.unit_id')::uuid, 'materials_test',
      jsonb_build_object(current_setting('test.material_group_id'),
                         current_setting('test.material_bad_id')), 0);
    raise exception 'incompatible material was accepted';
  exception when sqlstate '22023' then null;
  end;
  perform public.save_unit_module_choices(
    current_setting('test.owner_customer_id')::uuid,
    current_setting('test.unit_id')::uuid, 'materials_test',
    jsonb_build_object(current_setting('test.material_group_id'),
                       current_setting('test.material_good_id')), 0);
end $$;
reset role;

update public.unit_module_windows
set closes_at = clock_timestamp() - interval '1 second'
where unit_id = :'unit_id'::uuid and module_code = 'planta';

set role authenticated;
select set_config('request.jwt.claim.sub', :'owner_user_id', true);
do $$
begin
  begin
    perform public.save_unit_module_choices(
      current_setting('test.owner_customer_id')::uuid,
      current_setting('test.unit_id')::uuid, 'planta', '{}'::jsonb, 3);
    raise exception 'expired plant was accepted';
  exception when sqlstate '42501' then null;
  end;
  perform public.save_unit_module_choices(
    current_setting('test.owner_customer_id')::uuid,
    current_setting('test.unit_id')::uuid, 'materials_test',
    jsonb_build_object(current_setting('test.material_group_id'),
                       current_setting('test.material_good_id')), 1);
  if (select revision from public.unit_module_states
      where unit_id = current_setting('test.unit_id')::uuid
        and module_code = 'planta') <> 3 then
    raise exception 'other module changed plant revision';
  end if;
end $$;
reset role;

rollback;
select 'PASS: owner, co-owner, architect, revocation, RLS, concurrency, compatibility, deadline, module isolation; fixtures rolled back' as result;
