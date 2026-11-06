\set ON_ERROR_STOP on
begin;
select user_id as admin_id from public.staff_users where active and role='admin' limit 1 \gset
select usr.user_id as customer_id from public.customer_users usr where active limit 1 \gset
select gen_random_uuid() as unit_id, gen_random_uuid() as auth_id \gset
insert into auth.users(id,email) values(:'auth_id','requirements-'||:'auth_id'||'@example.test');
select set_config('test.auth',:'auth_id',true),set_config('test.unit',:'unit_id',true);
set local role authenticated;
select set_config('request.jwt.claim.sub',:'admin_id',true);
select public.register_customer_account('Cliente temporário','requirements-'||:'auth_id'||'@example.test') as profile_id \gset
select public.register_customer_account('Cliente atualizado','requirements-'||:'auth_id'||'@example.test') as repeated_id \gset
select set_config('test.profile',:'profile_id',true),set_config('test.repeat',:'repeated_id',true);
do $$ begin if current_setting('test.profile')<>current_setting('test.repeat') then raise exception 'Registration was not idempotent'; end if; end $$;
select set_config('request.jwt.claim.sub',:'customer_id',true);
do $$ begin
 begin perform public.find_customer_auth_user('nobody@example.test'); raise exception 'Customer queried accounts'; exception when insufficient_privilege then null; end;
 begin perform public.claim_deadline_notifications(1); raise exception 'Customer claimed reminders'; exception when insufficient_privilege then null; end;
end $$;
reset role;
insert into public.units(id,code,tower,floor_label,termination,typology,customization_closes_at)
values(:'unit_id','REM-'||:'unit_id','Teste','Teste','09A','Teste',
 (((clock_timestamp() at time zone 'America/Sao_Paulo')::date+15)+time '12:00') at time zone 'America/Sao_Paulo');
insert into public.customer_units(customer_id,unit_id) values(:'profile_id',:'unit_id');
set local role service_role;
select count(*) from public.claim_deadline_notifications(100);
do $$ declare v_id uuid; begin
 select id into v_id from public.deadline_notifications where unit_id=current_setting('test.unit')::uuid;
 if v_id is null then raise exception '15-day reminder missing'; end if;
 perform public.finish_deadline_notification(v_id,true,null);
end $$;
select count(*) from public.claim_deadline_notifications(100);
do $$ begin
 if (select count(*) from public.deadline_notifications where unit_id=current_setting('test.unit')::uuid)<>1
   or not exists(select 1 from public.deadline_notifications where unit_id=current_setting('test.unit')::uuid and status='sent')
 then raise exception 'Reminder deduplication failed'; end if;
end $$;
reset role;
update public.units set customization_closes_at=null where id=:'unit_id';
set local role service_role;
select count(*) from public.claim_deadline_notifications(100);
do $$ begin if (select count(*) from public.deadline_notifications where unit_id=current_setting('test.unit')::uuid)<>1
 then raise exception 'Null deadline created reminder'; end if; end $$;
rollback;
select 'PASS: admin account registration, idempotency, customer isolation, reminder claim, delivery, deduplication and null deadline; fixtures rolled back';
