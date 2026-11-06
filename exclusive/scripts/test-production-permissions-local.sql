\set ON_ERROR_STOP on
begin;
insert into auth.users(id,email) values
 ('31000000-0000-4000-8000-000000000001','exclusive@planoaengenharia.com.br'),
 ('31000000-0000-4000-8000-000000000002','admin-permissions@example.test'),
 ('31000000-0000-4000-8000-000000000003','architect-permissions@example.test'),
 ('31000000-0000-4000-8000-000000000004','owner-permissions@example.test'),
 ('31000000-0000-4000-8000-000000000005','other-permissions@example.test');
insert into public.staff_users(user_id,name,role) values
 ('31000000-0000-4000-8000-000000000001','Principal','admin'),
 ('31000000-0000-4000-8000-000000000002','Outro Admin','admin'),
 ('31000000-0000-4000-8000-000000000003','Arquiteta','architect');
insert into public.customers(id,name,email,phone) values
 ('32000000-0000-4000-8000-000000000001','Cliente','owner-permissions@example.test','(82) 99999-0000'),
 ('32000000-0000-4000-8000-000000000002','Outro','other-permissions@example.test',null);
insert into public.customer_users(customer_id,user_id) values
 ('32000000-0000-4000-8000-000000000001','31000000-0000-4000-8000-000000000004'),
 ('32000000-0000-4000-8000-000000000002','31000000-0000-4000-8000-000000000005');
insert into public.units(id,code,tower,floor_label,termination,typology,customization_closes_at) values
 ('33000000-0000-4000-8000-000000000001','PERMISSIONS-1','Teste','Teste','01','Teste',
 (((clock_timestamp() at time zone 'America/Sao_Paulo')::date+15)+time '18:00') at time zone 'America/Sao_Paulo');
insert into public.customer_units(customer_id,unit_id) values
 ('32000000-0000-4000-8000-000000000001','33000000-0000-4000-8000-000000000001');
set local role authenticated;
select set_config('request.jwt.claim.sub','31000000-0000-4000-8000-000000000003',true);
do $$ begin
 if (select phone from public.customers where id='32000000-0000-4000-8000-000000000001')<>'(82) 99999-0000' then raise exception 'Architect cannot read phone'; end if;
 begin perform public.update_customer_contact('32000000-0000-4000-8000-000000000001','Intruso',null);raise exception 'Architect edited contact';exception when insufficient_privilege then null;end;
 begin perform public.set_customer_active('32000000-0000-4000-8000-000000000001',false);raise exception 'Architect blocked account';exception when insufficient_privilege then null;end;
 begin perform public.manage_staff('architect-permissions@example.test','Arquiteta','admin',true);raise exception 'Self promotion';exception when insufficient_privilege then null;end;
 begin perform public.list_staff_accounts();raise exception 'Architect listed staff identities';exception when insufficient_privilege then null;end;
 begin update public.customization_options set name='Changed';raise exception 'Architect edited catalog';exception when insufficient_privilege then null;end;
end $$;
select set_config('request.jwt.claim.sub','31000000-0000-4000-8000-000000000002',true);
select public.update_customer_contact('32000000-0000-4000-8000-000000000001','Cliente atualizado','+55 82 99999-1111');
select public.set_customer_active('32000000-0000-4000-8000-000000000001',false);
do $$ begin
 begin perform public.manage_staff('exclusive@planoaengenharia.com.br','Principal','architect',true);raise exception 'Principal demoted';exception when insufficient_privilege then null;end;
 begin perform public.manage_staff('exclusive@planoaengenharia.com.br','Principal','admin',false);raise exception 'Principal blocked';exception when insufficient_privilege then null;end;
 begin perform public.manage_staff('owner-permissions@example.test','Cliente','admin',true);raise exception 'Customer promoted';exception when invalid_parameter_value then null;end;
 begin perform public.update_customer_contact('32000000-0000-4000-8000-000000000001','Cliente','not-a-phone');raise exception 'Invalid phone accepted';exception when check_violation then null;end;
end $$;
select set_config('request.jwt.claim.sub','31000000-0000-4000-8000-000000000004',true);
do $$ begin
 if public.current_account_active() or exists(select 1 from public.units) or exists(select 1 from public.customers) or exists(select 1 from public.list_customer_unit_cards()) then raise exception 'Blocked customer retained data access';end if;
 if public.customer_can_access_unit('33000000-0000-4000-8000-000000000001') then raise exception 'Definer bypassed account block';end if;
 begin perform public.record_unit_access('33000000-0000-4000-8000-000000000001');raise exception 'Blocked customer opened unit';exception when insufficient_privilege then null;end;
 begin perform public.prepare_customer_email('32000000-0000-4000-8000-000000000001','hijack@example.test');raise exception 'Customer authorized email';exception when insufficient_privilege then null;end;
end $$;
reset role;
set local role service_role;
do $$ begin if exists(select 1 from public.claim_deadline_notifications(10)) then raise exception 'Blocked customer received reminder';end if;end $$;
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','31000000-0000-4000-8000-000000000002',true);
select public.set_customer_active('32000000-0000-4000-8000-000000000001',true);
select public.register_customer_account('Cliente atualizado','owner-permissions@example.test','+55 82 99999-1111');
select set_config('request.jwt.claim.sub','31000000-0000-4000-8000-000000000004',true);
do $$ begin
 if not public.current_account_active() or (select count(*) from public.units)<>1 or (select count(*) from public.customers)<>1 then raise exception 'Reactivation/isolation failed';end if;
 begin update public.customers set name='Changed';raise exception 'Customer edited own profile';exception when insufficient_privilege then null;end;
 begin insert into public.units(code,tower,floor_label,termination,typology) values('INTRUDER','A','1','01','x');raise exception 'Customer created unit';exception when insufficient_privilege then null;end;
 if exists(select 1 from public.unit_activity_events) then raise exception 'Customer read internal history';end if;
end $$;
reset role;
do $$ begin
 begin update auth.users set email='hijack@example.test' where id='31000000-0000-4000-8000-000000000004';raise exception 'Unauthorized Auth email changed';exception when insufficient_privilege then null;end;
 begin update auth.users set email_change='hijack@example.test' where id='31000000-0000-4000-8000-000000000004';raise exception 'Self-service email change started';exception when insufficient_privilege then null;end;
 begin delete from auth.users where id='31000000-0000-4000-8000-000000000001';raise exception 'Principal deleted through Auth cascade';exception when insufficient_privilege then null;end;
 begin update auth.users set email='other-main@example.test' where id='31000000-0000-4000-8000-000000000001';raise exception 'Principal identity changed';exception when insufficient_privilege then null;end;
 begin update auth.users set banned_until=clock_timestamp()+interval '1 day' where id='31000000-0000-4000-8000-000000000001';raise exception 'Principal Auth banned';exception when insufficient_privilege then null;end;
 begin update public.staff_users set protected=false where user_id='31000000-0000-4000-8000-000000000001';raise exception 'Principal protection cleared';exception when insufficient_privilege then null;end;
 begin update public.unit_activity_events set action='Changed';raise exception 'History edited';exception when insufficient_privilege then null;end;
 begin delete from public.unit_activity_events;raise exception 'History removed';exception when insufficient_privilege then null;end;
 begin truncate public.unit_activity_events;raise exception 'History truncated';exception when insufficient_privilege then null;end;
 begin delete from public.units;raise exception 'Units removed';exception when insufficient_privilege then null;end;
end $$;
set local role authenticated;
select set_config('request.jwt.claim.sub','31000000-0000-4000-8000-000000000002',true);
select public.prepare_customer_email('32000000-0000-4000-8000-000000000001','updated-owner@example.test');
reset role;
update auth.users set email='updated-owner@example.test',email_change='' where id='31000000-0000-4000-8000-000000000004';
do $$ begin
 if (select email from public.customers where id='32000000-0000-4000-8000-000000000001')<>'updated-owner@example.test' or exists(select 1 from public.customers where authorized_email is not null) then raise exception 'Auth/profile email sync failed';end if;
 if (select count(*) from public.customers)<>2 then raise exception 'Account duplicated';end if;
end $$;
set local role service_role;
select count(*) from public.claim_deadline_notifications(10);
reset role;
-- Simulate a safely recorded transport failure, eligible for manual retry.
update public.deadline_notifications set status='failed',lease_until=clock_timestamp()-interval '1 second';
set local role authenticated;
select set_config('request.jwt.claim.sub','31000000-0000-4000-8000-000000000003',true);
do $$ declare v_id uuid;begin
 select id into v_id from public.deadline_notifications limit 1;
 -- The architect cannot even read this queue; use a direct known-invalid id.
 begin perform public.retry_deadline_notification('34000000-0000-4000-8000-000000000001');raise exception 'Architect retried notice';exception when insufficient_privilege then null;end;
end $$;
select set_config('request.jwt.claim.sub','31000000-0000-4000-8000-000000000002',true);
select public.retry_deadline_notification(id) from public.deadline_notifications;
select public.set_unit_customer('33000000-0000-4000-8000-000000000001','32000000-0000-4000-8000-000000000002');
select set_config('request.jwt.claim.sub','31000000-0000-4000-8000-000000000004',true);
do $$ begin
 if exists(select 1 from public.units) or exists(select 1 from public.list_customer_unit_cards()) then raise exception 'Former owner retained unit';end if;
 begin perform public.record_unit_access('33000000-0000-4000-8000-000000000001');raise exception 'Former owner opened unit';exception when insufficient_privilege then null;end;
end $$;
reset role;
do $$ begin if exists(select 1 from public.deadline_notifications where public.deadline_notification_eligible(id)) then raise exception 'Former owner reminder still eligible';end if;end $$;
set local role authenticated;
select set_config('request.jwt.claim.sub','31000000-0000-4000-8000-000000000002',true);
do $$ declare n record;begin
 for n in select id from public.deadline_notifications loop
  begin perform public.retry_deadline_notification(n.id);raise exception 'Former owner retry accepted';exception when invalid_parameter_value then null;end;
 end loop;
end $$;
select public.manage_staff('architect-permissions@example.test','Arquiteta','architect',false);
select set_config('request.jwt.claim.sub','31000000-0000-4000-8000-000000000003',true);
do $$ begin if public.current_account_active() or public.current_staff_role() is not null or exists(select 1 from public.units) or exists(select 1 from public.unit_activity_events) then raise exception 'Revoked staff retained access';end if;end $$;
reset role;
insert into public.units(code,tower,floor_label,termination,typology)
 select 'LIMIT-'||i,'Teste','Teste','Teste','Teste' from generate_series(1,388)i;
do $$ begin
 begin insert into public.units(code,tower,floor_label,termination,typology) values('LIMIT-390','Teste','Teste','Teste','Teste');raise exception '390th unit accepted';exception when invalid_parameter_value then null;end;
 if (select count(*) from public.units)<>389 then raise exception 'Inventory bound failed';end if;
end $$;
rollback;
select 'PASS: production permissions, account blocks, protected principal, email guard/sync, immutable history, fixed inventory and eligible retry';
