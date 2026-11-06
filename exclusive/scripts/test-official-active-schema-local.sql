\set ON_ERROR_STOP on
begin;
insert into auth.users(id,email) values
 ('21000000-0000-4000-8000-000000000001','bootstrap-admin@example.test'),
 ('21000000-0000-4000-8000-000000000002','bootstrap-architect@example.test'),
 ('21000000-0000-4000-8000-000000000003','bootstrap-owner@example.test'),
 ('21000000-0000-4000-8000-000000000004','bootstrap-other@example.test'),
 ('21000000-0000-4000-8000-000000000005','bootstrap-new@example.test');
insert into public.staff_users(user_id,name,role) values
 ('21000000-0000-4000-8000-000000000001','Admin temporário','admin'),
 ('21000000-0000-4000-8000-000000000002','Arquiteta temporária','architect');
insert into public.customers(id,name,email) values
 ('22000000-0000-4000-8000-000000000001','Cliente temporário','bootstrap-owner@example.test'),
 ('22000000-0000-4000-8000-000000000002','Outro cliente','bootstrap-other@example.test');
insert into public.customer_users(customer_id,user_id) values
 ('22000000-0000-4000-8000-000000000001','21000000-0000-4000-8000-000000000003'),
 ('22000000-0000-4000-8000-000000000002','21000000-0000-4000-8000-000000000004');
insert into public.units(id,code,tower,floor_label,termination,typology) values
 ('23000000-0000-4000-8000-000000000001','BOOTSTRAP-1','Teste','Teste','01','Teste'),
 ('23000000-0000-4000-8000-000000000002','BOOTSTRAP-2','Teste','Teste','02','Teste');
insert into public.customer_units(customer_id,unit_id) values
 ('22000000-0000-4000-8000-000000000001','23000000-0000-4000-8000-000000000001'),
 ('22000000-0000-4000-8000-000000000002','23000000-0000-4000-8000-000000000002');
insert into public.base_plans(id,code,name) values ('24000000-0000-4000-8000-000000000001','BOOTSTRAP','Teste');
insert into public.unit_base_plan_assignments(unit_id,base_plan_id) values
 ('23000000-0000-4000-8000-000000000001','24000000-0000-4000-8000-000000000001'),
 ('23000000-0000-4000-8000-000000000002','24000000-0000-4000-8000-000000000001');
update public.unit_base_plan_assignments set assigned_at=clock_timestamp();
insert into public.customization_groups(id,code,name,module_code,required_for_submission) values
 ('25000000-0000-4000-8000-000000000001','BOOTSTRAP','Teste','planta',true);
insert into public.customization_options(id,group_id,code,name) values
 ('26000000-0000-4000-8000-000000000001','25000000-0000-4000-8000-000000000001','padrao','Padrão');
insert into public.base_plan_option_availability(base_plan_id,option_id) values
 ('24000000-0000-4000-8000-000000000001','26000000-0000-4000-8000-000000000001');
insert into public.base_plan_option_defaults(base_plan_id,group_id,option_id) values
 ('24000000-0000-4000-8000-000000000001','25000000-0000-4000-8000-000000000001','26000000-0000-4000-8000-000000000001');

set local role authenticated;
select set_config('request.jwt.claim.sub','21000000-0000-4000-8000-000000000003',true);
do $$ begin
 if (select count(*) from public.units)<>1 or (select count(*) from public.customers)<>1 then raise exception 'Customer isolation failed'; end if;
 if (select count(*) from public.customization_groups)<>1 or (select count(*) from public.customization_options)<>1 then raise exception 'Current catalog policy failed'; end if;
 if public.validate_unit_session('23000000-0000-4000-8000-000000000001','{}')->>'25000000-0000-4000-8000-000000000001'<>'26000000-0000-4000-8000-000000000001' then raise exception 'Default session failed'; end if;
 begin perform public.set_unit_active('23000000-0000-4000-8000-000000000001',false); raise exception 'Customer changed unit'; exception when insufficient_privilege then null; end;
end $$;
select public.record_unit_access('23000000-0000-4000-8000-000000000001');

select set_config('request.jwt.claim.sub','21000000-0000-4000-8000-000000000002',true);
select public.set_unit_active('23000000-0000-4000-8000-000000000001',false);
select public.record_unit_access('23000000-0000-4000-8000-000000000001');
do $$ begin
 if (select count(*) from public.units)<>2 or not exists(select 1 from public.unit_activity_events) then raise exception 'Staff access/history failed'; end if;
 begin perform public.set_unit_deadline('23000000-0000-4000-8000-000000000001',null); raise exception 'Architect changed deadline'; exception when insufficient_privilege then null; end;
end $$;
select set_config('request.jwt.claim.sub','21000000-0000-4000-8000-000000000003',true);
do $$ begin
 if exists(select 1 from public.units where id='23000000-0000-4000-8000-000000000001') then raise exception 'Customer opened inactive unit'; end if;
 if not exists(select 1 from public.list_customer_unit_cards() where id='23000000-0000-4000-8000-000000000001' and not active) then raise exception 'Inactive card missing'; end if;
 begin perform public.record_unit_access('23000000-0000-4000-8000-000000000001'); raise exception 'Inactive access allowed'; exception when insufficient_privilege then null; end;
end $$;

select set_config('request.jwt.claim.sub','21000000-0000-4000-8000-000000000001',true);
select public.set_unit_active('23000000-0000-4000-8000-000000000001',true);
select public.manage_unit('23000000-0000-4000-8000-000000000001','22000000-0000-4000-8000-000000000001',null,'{}');
select public.set_module_deadline('23000000-0000-4000-8000-000000000001','planta',clock_timestamp()-interval '1 day');
select public.register_customer_account('Novo cliente temporário','bootstrap-new@example.test');
select set_config('request.jwt.claim.sub','21000000-0000-4000-8000-000000000003',true);
do $$ begin
 begin perform public.validate_unit_session('23000000-0000-4000-8000-000000000001','{}'); raise exception 'Expired module accepted'; exception when insufficient_privilege then null; end;
 begin perform public.register_customer_account('Não autorizado','bootstrap-new@example.test'); raise exception 'Customer registered an account'; exception when insufficient_privilege then null; end;
end $$;
select set_config('request.jwt.claim.sub','21000000-0000-4000-8000-000000000001',true);
select public.set_module_deadline('23000000-0000-4000-8000-000000000001','planta',null);
select public.set_unit_deadline('23000000-0000-4000-8000-000000000001',null);
select public.validate_unit_session('23000000-0000-4000-8000-000000000001','{}');
reset role;
set local role service_role;
select count(*) from public.claim_deadline_notifications(10);
reset role;
do $$ begin
 if not has_function_privilege('service_role','public.apply_import_batch(uuid)','execute')
   or has_function_privilege('authenticated','public.apply_import_batch(uuid)','execute') then raise exception 'Import privileges changed'; end if;
 if not exists(select 1 from pg_indexes where schemaname='public' and indexname='unit_activity_events_unit_id_id_idx') then raise exception 'History index missing'; end if;
end $$;
rollback;
select 'PASS: optimized schema supports current catalog, owner isolation, inactive cards, staff history, admin registration, deadlines and service-only imports; fixtures rolled back';
