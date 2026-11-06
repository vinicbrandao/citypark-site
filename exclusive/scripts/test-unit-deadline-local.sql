\set ON_ERROR_STOP on
begin;
select id as source_unit_id from public.units where code = '1401A' \gset
select cu.customer_id as owner_customer_id, usr.user_id as owner_user_id
from public.customer_units cu
join public.customer_users usr on usr.customer_id = cu.customer_id and usr.active
where cu.unit_id = :'source_unit_id'::uuid and cu.ownership_role = 'owner' and cu.active \gset
select s.user_id as architect_user_id from public.staff_users s
join public.staff_unit_assignments a on a.user_id = s.user_id and a.active
where a.unit_id = :'source_unit_id'::uuid and s.role = 'architect' and s.active
  and public.current_architect_authorization(a.unit_id, s.user_id) limit 1 \gset

insert into public.units(code, tower, floor_label, termination, typology, area_m2, customization_closes_at)
select 'DEADLINE-TEST-' || gen_random_uuid(), tower, floor_label, termination, typology,
       99.90, clock_timestamp() + interval '1 day'
from public.units where id = :'source_unit_id'::uuid returning id as unit_id \gset
insert into public.customer_units(customer_id, unit_id, ownership_role)
values (:'owner_customer_id'::uuid, :'unit_id'::uuid, 'owner');
insert into public.staff_unit_assignments(user_id, unit_id)
values (:'architect_user_id'::uuid, :'unit_id'::uuid);
insert into public.architect_authorizations
  (unit_id, architect_user_id, granted_by_customer_id, granted_by_user_id)
values (:'unit_id'::uuid, :'architect_user_id'::uuid, :'owner_customer_id'::uuid, :'owner_user_id'::uuid);
insert into public.base_plans(code, name) values ('deadline-' || gen_random_uuid(), 'Deadline test')
returning id as plan_id \gset
insert into public.unit_base_plan_assignments(unit_id, base_plan_id)
values (:'unit_id'::uuid, :'plan_id'::uuid);
insert into public.customization_modules(code, name) values ('deadline_materials_test', 'Deadline test materials');
insert into public.customization_groups(code, name, module_code)
values ('deadline-' || gen_random_uuid(), 'Plant test', 'planta') returning id as plant_group_id \gset
insert into public.customization_groups(code, name, module_code)
values ('deadline-' || gen_random_uuid(), 'Materials test', 'deadline_materials_test') returning id as materials_group_id \gset
insert into public.customization_options(group_id, code, name)
values (:'plant_group_id'::uuid, 'choice', 'Plant choice') returning id as plant_option_id \gset
insert into public.customization_options(group_id, code, name)
values (:'materials_group_id'::uuid, 'choice', 'Materials choice') returning id as materials_option_id \gset
insert into public.base_plan_option_availability(base_plan_id, option_id)
values (:'plan_id'::uuid, :'plant_option_id'::uuid), (:'plan_id'::uuid, :'materials_option_id'::uuid);
insert into public.unit_module_windows(unit_id, module_code, opens_at, closes_at)
values (:'unit_id'::uuid, 'planta', now() - interval '2 days', now() + interval '1 day'),
       (:'unit_id'::uuid, 'deadline_materials_test', now() - interval '2 days', now() + interval '1 day');

select set_config('test.unit_id', :'unit_id', true);
select set_config('test.owner_customer_id', :'owner_customer_id', true);
select set_config('test.plant_group_id', :'plant_group_id', true);
select set_config('test.plant_option_id', :'plant_option_id', true);
select set_config('test.materials_group_id', :'materials_group_id', true);
select set_config('test.materials_option_id', :'materials_option_id', true);
set role authenticated;
select set_config('request.jwt.claim.sub', :'owner_user_id', true);
select public.save_unit_module_choices(:'owner_customer_id'::uuid, :'unit_id'::uuid, 'planta',
  jsonb_build_object(:'plant_group_id', :'plant_option_id'), 0);
select public.save_unit_module_choices(:'owner_customer_id'::uuid, :'unit_id'::uuid, 'deadline_materials_test',
  jsonb_build_object(:'materials_group_id', :'materials_option_id'), 0);
reset role;
update public.units set customization_closes_at = clock_timestamp() - interval '1 second' where id = :'unit_id'::uuid;

set role authenticated;
select set_config('request.jwt.claim.sub', :'owner_user_id', true);
do $$
begin
  -- Expired choices remain readable; neither module nor a new proposal is writable.
  if (select area_m2 from public.units where id = current_setting('test.unit_id')::uuid) <> 99.90
    or (select count(*) from public.unit_module_selections where unit_id = current_setting('test.unit_id')::uuid) <> 2 then
    raise exception 'Expired unit is not readable';
  end if;
  begin
    perform public.save_unit_module_choices(current_setting('test.owner_customer_id')::uuid,
      current_setting('test.unit_id')::uuid, 'planta',
      jsonb_build_object(current_setting('test.plant_group_id'), current_setting('test.plant_option_id')), 1);
    raise exception 'Plant changed after final deadline';
  exception when sqlstate '42501' then
    if sqlerrm <> 'Unit customization deadline reached' then raise; end if;
  end;
  begin
    perform public.save_unit_module_choices(current_setting('test.owner_customer_id')::uuid,
      current_setting('test.unit_id')::uuid, 'deadline_materials_test',
      jsonb_build_object(current_setting('test.materials_group_id'), current_setting('test.materials_option_id')), 1);
    raise exception 'Materials changed after final deadline';
  exception when sqlstate '42501' then
    if sqlerrm <> 'Unit customization deadline reached' then raise; end if;
  end;
  begin
    perform public.submit_unit_proposal(current_setting('test.owner_customer_id')::uuid,
      current_setting('test.unit_id')::uuid, '{"planta":1,"deadline_materials_test":1}');
    raise exception 'Initial proposal accepted after deadline';
  exception when sqlstate '42501' then
    if sqlerrm <> 'Unit customization deadline reached' then raise; end if;
  end;
  begin
    update public.units set customization_closes_at = now() + interval '1 year'
      where id = current_setting('test.unit_id')::uuid;
    raise exception 'Customer changed final deadline';
  exception when sqlstate '42501' then null;
  end;
end $$;

select set_config('request.jwt.claim.sub', :'architect_user_id', true);
do $$ begin
  begin
    perform public.save_unit_module_choices(null, current_setting('test.unit_id')::uuid, 'planta',
      jsonb_build_object(current_setting('test.plant_group_id'), current_setting('test.plant_option_id')), 1);
    raise exception 'Architect bypassed final deadline';
  exception when sqlstate '42501' then
    if sqlerrm <> 'Unit customization deadline reached' then raise; end if;
  end;
end $$;
reset role;

-- Rejected RPCs must not leave partial module states, history or proposals.
do $$ begin
  if (select count(*) from public.unit_proposals where unit_id = current_setting('test.unit_id')::uuid) <> 0
    or (select count(*) from public.unit_module_history where unit_id = current_setting('test.unit_id')::uuid) <> 2
    or (select max(revision) from public.unit_module_states where unit_id = current_setting('test.unit_id')::uuid) <> 1 then
    raise exception 'Deadline rejection left partial writes';
  end if;
  begin
    update public.units set area_m2 = 0 where id = current_setting('test.unit_id')::uuid;
    raise exception 'Invalid area accepted';
  exception when check_violation then null;
  end;
end $$;
update public.units set customization_closes_at = now() + interval '1 day' where id = :'unit_id'::uuid;
set role authenticated;
select set_config('request.jwt.claim.sub', :'owner_user_id', true);
select public.submit_unit_proposal(:'owner_customer_id'::uuid, :'unit_id'::uuid,
  '{"planta":1,"deadline_materials_test":1}');
select public.save_unit_module_choices(:'owner_customer_id'::uuid, :'unit_id'::uuid, 'planta',
  jsonb_build_object(:'plant_group_id', :'plant_option_id'), 1);
reset role;
update public.units set customization_closes_at = now() - interval '1 second' where id = :'unit_id'::uuid;
set role authenticated;
do $$ begin
  begin
    perform public.submit_unit_proposal(current_setting('test.owner_customer_id')::uuid,
      current_setting('test.unit_id')::uuid, '{"planta":2,"deadline_materials_test":1}');
    raise exception 'Resubmission accepted after final deadline';
  exception when sqlstate '42501' then
    if sqlerrm <> 'Unit customization deadline reached' then raise; end if;
  end;
end $$;
reset role;

-- Reviewing an existing submitted version is still allowed after final cutoff.
update public.units set customization_closes_at = now() + interval '1 day' where id = :'unit_id'::uuid;
set role authenticated;
select public.submit_unit_proposal(:'owner_customer_id'::uuid, :'unit_id'::uuid,
  '{"planta":2,"deadline_materials_test":1}');
reset role;
update public.units set customization_closes_at = now() - interval '1 second' where id = :'unit_id'::uuid;
set role authenticated;
select set_config('request.jwt.claim.sub', :'architect_user_id', true);
select public.review_unit_proposal(:'unit_id'::uuid, 2, 'approved');
reset role;
rollback;
select 'PASS: final cutoff blocks every module and submission, preserves consultation, atomicity, authorization and review; fixtures rolled back';
