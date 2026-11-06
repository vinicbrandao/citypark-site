\set ON_ERROR_STOP on
begin;
select user_id as admin_id from public.staff_users where active and role = 'admin' limit 1 \gset
select user_id as architect_id from public.staff_users where active and role = 'architect' limit 1 \gset
select u.id as source_id, a.base_plan_id as plan_id, cu.customer_id, usr.user_id as customer_user_id
from public.units u join public.unit_base_plan_assignments a on a.unit_id = u.id
join public.customer_units cu on cu.unit_id = u.id and cu.active
join public.customer_users usr on usr.customer_id = cu.customer_id and usr.active
where u.code = '1401A' \gset
select gen_random_uuid() as test_unit_id \gset
insert into public.units(id,code,tower,floor_label,termination,typology,active)
values(:'test_unit_id', 'REQ-' || :'test_unit_id', 'Teste','Teste','09A','Teste',true);
insert into public.unit_base_plan_assignments(unit_id,base_plan_id) values(:'test_unit_id',:'plan_id');
insert into public.customer_units(customer_id,unit_id) values(:'customer_id',:'test_unit_id');
select set_config('test.unit', :'test_unit_id', true), set_config('test.plan', :'plan_id', true);

set local role authenticated;
select set_config('request.jwt.claim.sub', :'customer_user_id', true);
select public.record_unit_access(:'test_unit_id');
-- No unit deadline and no module window: defaults are valid, no draft is stored.
select public.validate_unit_session(:'test_unit_id', '{}');
do $$ begin
  if exists(select 1 from public.unit_module_states where unit_id = current_setting('test.unit')::uuid)
    then raise exception 'Session choices were persisted'; end if;
  begin
    perform public.set_unit_active(current_setting('test.unit')::uuid,false);
    raise exception 'Customer changed unit status';
  exception when insufficient_privilege then null; end;
  begin
    perform public.save_unit_module_choices(null,current_setting('test.unit')::uuid,'planta','{}',0);
    raise exception 'Legacy module save still allowed';
  exception when insufficient_privilege then null; end;
end $$;

select set_config('request.jwt.claim.sub', :'architect_id', true);
select public.set_unit_active(:'test_unit_id',false);
select public.record_unit_access(:'test_unit_id');
do $$ begin
  if not exists(select 1 from public.units where id = current_setting('test.unit')::uuid and not active)
    then raise exception 'Architect cannot read inactive unit'; end if;
  begin
    perform public.set_unit_deadline(current_setting('test.unit')::uuid,null);
    raise exception 'Architect changed deadline';
  exception when insufficient_privilege then null; end;
end $$;
select set_config('request.jwt.claim.sub', :'customer_user_id', true);
do $$ begin
  if exists(select 1 from public.units where id = current_setting('test.unit')::uuid)
    then raise exception 'Customer can read inactive unit'; end if;
  if not exists(select 1 from public.list_customer_unit_cards() where id=current_setting('test.unit')::uuid and not active)
    then raise exception 'Customer cannot see own inactive card'; end if;
  begin
    perform public.record_unit_access(current_setting('test.unit')::uuid);
    raise exception 'Customer opened inactive unit';
  exception when insufficient_privilege then null; end;
end $$;

select set_config('request.jwt.claim.sub', :'admin_id', true);
select public.set_unit_active(:'test_unit_id',true);
select public.set_module_deadline(:'test_unit_id','planta',clock_timestamp()-interval '1 day');
do $$ begin
  begin
    perform public.validate_unit_session(current_setting('test.unit')::uuid,'{}');
    raise exception 'Expired module allowed';
  exception when insufficient_privilege then null; end;
end $$;
select public.set_module_deadline(:'test_unit_id','planta',null);
select public.validate_unit_session(:'test_unit_id','{}');
select public.set_unit_deadline(:'test_unit_id',clock_timestamp()-interval '1 day');
do $$ begin
  begin
    perform public.validate_unit_session(current_setting('test.unit')::uuid,'{}');
    raise exception 'Expired unit allowed';
  exception when insufficient_privilege then null; end;
end $$;
select public.set_unit_deadline(:'test_unit_id',null);

reset role;
select o.id as stone_id, g.id as stone_group from public.customization_options o
join public.customization_groups g on g.id=o.group_id where g.code='DEMO-GRANITO' and o.code='bellagio' \gset
select o.id as social_id, g.id as social_group from public.customization_options o
join public.customization_groups g on g.id=o.group_id where g.code='DEMO-AREA-SOCIAL' and o.code='euroglass' \gset
insert into public.base_plan_option_requirements values(:'plan_id',:'stone_id',:'social_id');
select set_config('test.stone_group',:'stone_group',true),set_config('test.stone_id',:'stone_id',true);
set local role authenticated;
select set_config('request.jwt.claim.sub', :'customer_user_id', true);
do $$ begin
  begin
    perform public.validate_unit_session(current_setting('test.unit')::uuid,
      jsonb_build_object(current_setting('test.stone_group'),current_setting('test.stone_id')));
    raise exception 'Dependency not enforced';
  exception when invalid_parameter_value then null; end;
end $$;
select public.validate_unit_session(:'test_unit_id',jsonb_build_object(:'stone_group',:'stone_id',:'social_group',:'social_id'));
reset role;
update public.units set active=false,customization_status='completed' where id=:'test_unit_id';
set local role authenticated;
select set_config('request.jwt.claim.sub', :'architect_id', true);
do $$ begin
  begin perform public.set_unit_active(current_setting('test.unit')::uuid,true);
    raise exception 'Architect reopened completed unit'; exception when insufficient_privilege then null; end;
end $$;
select set_config('request.jwt.claim.sub', :'admin_id', true);
select public.set_unit_active(:'test_unit_id',true);
do $$ begin
  if not exists(select 1 from public.units where id=current_setting('test.unit')::uuid and active and customization_status='pending')
    then raise exception 'Admin reopening did not reset status'; end if;
  begin
    perform public.manage_unit(current_setting('test.unit')::uuid,null,clock_timestamp()+interval '2 days','{"missing-module":null}');
    raise exception 'Invalid batch succeeded'; exception when invalid_parameter_value then null; end;
  if not exists(select 1 from public.customer_units where unit_id=current_setting('test.unit')::uuid and active)
    or exists(select 1 from public.units where id=current_setting('test.unit')::uuid and customization_closes_at is not null)
    then raise exception 'Failed management batch partially committed'; end if;
end $$;
reset role;
do $$ begin
  if (select count(*) from public.unit_activity_events where unit_id=current_setting('test.unit')::uuid) < 6
    then raise exception 'Missing audit events'; end if;
end $$;
rollback;
select 'PASS: transient choices, defaults, inactive staff access, customer isolation, admin deadlines, dependencies, legacy write revocation and audit; fixtures rolled back';
