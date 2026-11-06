-- Approved permissions, 30/10/2026. Additive upgrade; no seeds or new tables.
alter table public.customers
  add column phone text check (phone is null or (length(phone)<=40 and phone ~ '^[+0-9() .-]+$' and length(regexp_replace(phone,'[^0-9]','','g')) between 8 and 15)),
  add column active boolean not null default true,
  add column authorized_email text,
  add column authorized_email_by uuid references auth.users(id),
  add column authorized_email_at timestamptz;
alter table public.staff_users add column protected boolean not null default false;
update public.staff_users s set protected=true, role='admin', active=true
  from auth.users u where u.id=s.user_id and lower(u.email)='exclusive@planoaengenharia.com.br';
create unique index staff_single_principal on public.staff_users(protected) where protected;

create function public.current_account_active() returns boolean
language sql stable security definer set search_path='' as $$
  select (select auth.uid()) is not null and case
    when exists(select 1 from public.staff_users where user_id=(select auth.uid())) then
      exists(select 1 from public.staff_users where user_id=(select auth.uid()) and active)
    when exists(select 1 from public.customer_users where user_id=(select auth.uid())) then
      exists(select 1 from public.customer_users u join public.customers c on c.id=u.customer_id
        where u.user_id=(select auth.uid()) and u.active and c.active)
    else true end;
$$;
revoke all on function public.current_account_active() from public,anon;
grant execute on function public.current_account_active() to authenticated;

-- Restrictive policies supplement existing ownership policies, never replace them.
do $$ declare t record; begin
  for t in select tablename from pg_tables where schemaname='public' loop
    execute format('create policy active_account_required on public.%I as restrictive for all to authenticated using ((select public.current_account_active())) with check ((select public.current_account_active()))',t.tablename);
  end loop;
end $$;

create or replace function public.customer_can_access_unit(p_unit_id uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.units u
   join public.customer_units cu on cu.unit_id=u.id and cu.active and cu.ownership_role='owner'
   join public.customer_users usr on usr.customer_id=cu.customer_id and usr.active
   join public.customers c on c.id=cu.customer_id and c.active
   where u.id=p_unit_id and u.active and usr.user_id=(select auth.uid()));
$$;
create or replace function public.list_customer_unit_cards()
returns table(id uuid,code text,tower text,tower_code text,floor_label text,termination text,typology text,
 area_m2 numeric,customization_closes_at timestamptz,active boolean,customization_status text)
language sql stable security definer set search_path='' as $$
 select u.id,u.code,u.tower,u.tower_code,u.floor_label,u.termination,u.typology,u.area_m2,
   u.customization_closes_at,u.active,u.customization_status from public.units u
 where public.current_account_active() and exists(select 1 from public.customer_units cu
   join public.customer_users usr on usr.customer_id=cu.customer_id and usr.active
   where cu.unit_id=u.id and cu.active and cu.ownership_role='owner' and usr.user_id=(select auth.uid())) order by u.code;
$$;

create function public.deny_record_removal() returns trigger
language plpgsql set search_path='' as $$ begin
 raise exception 'Records are preserved; use deactivation' using errcode='42501';
end $$;
revoke all on function public.deny_record_removal() from public,anon,authenticated;
create trigger immutable_unit_activity before update or delete on public.unit_activity_events
 for each row execute function public.deny_record_removal();
create trigger immutable_unit_activity_truncate before truncate on public.unit_activity_events
 for each statement execute function public.deny_record_removal();
do $$ declare t text; begin
 foreach t in array array['customers','units','staff_users','base_plans','customization_groups','customization_options'] loop
   execute format('create trigger preserve_records before delete or truncate on public.%I for each statement execute function public.deny_record_removal()',t);
 end loop;
end $$;

create function public.guard_principal_staff() returns trigger
language plpgsql security definer set search_path='' as $$ begin
 if tg_op='UPDATE' and old.protected and
   (not new.protected or not new.active or new.role<>'admin' or new.user_id<>old.user_id) then
   raise exception 'Principal Admin is protected' using errcode='42501';
 end if;
 if exists(select 1 from auth.users where id=new.user_id and lower(email)='exclusive@planoaengenharia.com.br') then
   new.protected:=true;
   if not new.active or new.role<>'admin' then
     raise exception 'Principal Admin is protected' using errcode='42501';
   end if;
 elsif new.protected and (tg_op='INSERT' or not old.protected) then
   raise exception 'Protected identity cannot be assigned' using errcode='42501';
 end if;
 return new;
end $$;
revoke all on function public.guard_principal_staff() from public,anon,authenticated;
create trigger protect_principal before insert or update on public.staff_users
 for each row execute function public.guard_principal_staff();

-- Auth API changes are allowed only after an Admin authorizes that exact address.
-- The Auth transaction synchronizes the profile; no direct auth.users UPDATE RPC.
create function public.guard_managed_auth_identity() returns trigger
language plpgsql security definer set search_path='' as $$
declare c public.customers; v_actor uuid;
begin
 if tg_op='DELETE' then
   if exists(select 1 from public.staff_users where user_id=old.id)
     or exists(select 1 from public.customer_users where user_id=old.id) then
     raise exception 'Managed accounts must be deactivated' using errcode='42501';
   end if;
   return old;
 end if;
 if exists(select 1 from public.staff_users where user_id=old.id and protected)
   and (new.id<>old.id or new.email is distinct from old.email or new.deleted_at is distinct from old.deleted_at
     or (new.banned_until is not null and new.banned_until>clock_timestamp())) then
   raise exception 'Principal Admin is protected' using errcode='42501';
 end if;
 select p.* into c from public.customers p join public.customer_users u on u.customer_id=p.id where u.user_id=old.id for update of p;
 if found then
   if new.deleted_at is distinct from old.deleted_at then
     raise exception 'Managed accounts must be deactivated' using errcode='42501';
   end if;
   if new.email is distinct from old.email or
     (coalesce(new.email_change,'')<>'' and new.email_change is distinct from old.email_change) then
     if c.authorized_email is null or c.authorized_email_at<clock_timestamp()-interval '10 minutes'
       or not exists(select 1 from public.staff_users where user_id=c.authorized_email_by and active and role='admin')
       or lower(case when new.email is distinct from old.email then new.email else new.email_change end)<>c.authorized_email then
       raise exception 'Only Admin can change customer email' using errcode='42501';
     end if;
     if new.email is distinct from old.email then
       if lower(new.email)<>c.authorized_email then raise exception 'Email authorization mismatch' using errcode='42501'; end if;
       v_actor:=c.authorized_email_by;
       update public.customers set email=lower(new.email),authorized_email=null,authorized_email_by=null,authorized_email_at=null where id=c.id;
       insert into public.unit_activity_events(actor_user_id,actor_role,actor_name,action,details)
       values(v_actor,'admin',(select name from public.staff_users where user_id=v_actor),'customer_email_changed',jsonb_build_object('customer_id',c.id));
     end if;
   end if;
 end if;
 return new;
end $$;
revoke all on function public.guard_managed_auth_identity() from public,anon,authenticated;
create trigger protect_managed_identity before update or delete on auth.users
 for each row execute function public.guard_managed_auth_identity();

create function public.update_customer_contact(p_customer_id uuid,p_name text,p_phone text) returns void
language plpgsql security definer set search_path='' as $$ begin
 if public.current_staff_role() is distinct from 'admin' then raise exception 'Admin required' using errcode='42501'; end if;
 if p_name is null or length(btrim(p_name)) not between 1 and 200 then raise exception 'Invalid customer profile' using errcode='22023'; end if;
 update public.customers set name=btrim(p_name),phone=nullif(btrim(p_phone),'') where id=p_customer_id;
 if not found then raise exception 'Customer not found' using errcode='22023'; end if;
 insert into public.unit_activity_events(actor_user_id,actor_role,action,details)
 values((select auth.uid()),'admin','customer_contact_changed',jsonb_build_object('customer_id',p_customer_id));
end $$;
create function public.set_customer_active(p_customer_id uuid,p_active boolean) returns void
language plpgsql security definer set search_path='' as $$ begin
 if public.current_staff_role() is distinct from 'admin' then raise exception 'Admin required' using errcode='42501'; end if;
 if p_active is null then raise exception 'Invalid status' using errcode='22023'; end if;
 update public.customers set active=p_active where id=p_customer_id;
 if not found then raise exception 'Customer not found' using errcode='22023'; end if;
 insert into public.unit_activity_events(actor_user_id,actor_role,action,details)
 values((select auth.uid()),'admin','customer_status_changed',jsonb_build_object('customer_id',p_customer_id,'active',p_active));
end $$;
create function public.prepare_customer_email(p_customer_id uuid,p_email text) returns uuid
language plpgsql security definer set search_path='' as $$
declare v_user uuid; v_email text:=lower(btrim(p_email));
begin
 if public.current_staff_role() is distinct from 'admin' then raise exception 'Admin required' using errcode='42501'; end if;
 if v_email is null or length(v_email)>254 or v_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then raise exception 'Invalid email' using errcode='22023'; end if;
 perform 1 from public.customers where id=p_customer_id for update;
 select user_id into v_user from public.customer_users where customer_id=p_customer_id and active;
 if v_user is null then raise exception 'Account not found' using errcode='22023'; end if;
 if exists(select 1 from auth.users where lower(email)=v_email and id<>v_user) then raise exception 'Email already in use' using errcode='22023'; end if;
 if exists(select 1 from public.customers where id=p_customer_id and authorized_email_at>clock_timestamp()-interval '10 minutes') then raise exception 'Email update in progress' using errcode='22023'; end if;
 update public.customers set authorized_email=v_email,authorized_email_by=(select auth.uid()),authorized_email_at=clock_timestamp() where id=p_customer_id;
 return v_user;
end $$;
create function public.cancel_customer_email(p_customer_id uuid,p_email text) returns void
language plpgsql security definer set search_path='' as $$ begin
 if public.current_staff_role() is distinct from 'admin' then raise exception 'Admin required' using errcode='42501'; end if;
 update public.customers set authorized_email=null,authorized_email_by=null,authorized_email_at=null
 where id=p_customer_id and authorized_email=lower(btrim(p_email)) and authorized_email_by=(select auth.uid());
end $$;

-- Keep the old RPC for compatibility; new handler supplies phone explicitly.
create function public.register_customer_account(p_name text,p_email text,p_phone text) returns uuid
language plpgsql security definer set search_path='' as $$
declare v_id uuid;
begin
 v_id:=public.register_customer_account(p_name,p_email);
 perform public.update_customer_contact(v_id,p_name,p_phone);
 return v_id;
end $$;

create function public.manage_staff(p_email text,p_name text,p_role text,p_active boolean) returns uuid
language plpgsql security definer set search_path='' as $$ declare v_id uuid;
begin
 if public.current_staff_role() is distinct from 'admin' then raise exception 'Admin required' using errcode='42501'; end if;
 if p_name is null or length(btrim(p_name)) not between 1 and 200 or p_role is null or p_role not in ('admin','architect') or p_active is null then raise exception 'Invalid staff profile' using errcode='22023'; end if;
 v_id:=public.find_customer_auth_user(p_email);
 if v_id is null or exists(select 1 from public.customer_users where user_id=v_id) then raise exception 'Staff identity unavailable' using errcode='22023'; end if;
 if v_id=(select auth.uid()) and (not p_active or p_role<>'admin') then raise exception 'Cannot revoke own Admin access' using errcode='42501'; end if;
 insert into public.staff_users(user_id,name,role,active) values(v_id,btrim(p_name),p_role,p_active)
 on conflict(user_id) do update set name=excluded.name,role=excluded.role,active=excluded.active;
 insert into public.unit_activity_events(actor_user_id,actor_role,action,details)
 values((select auth.uid()),'admin','staff_access_changed',jsonb_build_object('user_id',v_id,'role',p_role,'active',p_active));
 return v_id;
end $$;
create function public.list_staff_accounts() returns table(user_id uuid,name text,email text,role text,active boolean,protected boolean)
language plpgsql stable security definer set search_path='' as $$ begin
 if public.current_staff_role() is distinct from 'admin' then raise exception 'Admin required' using errcode='42501'; end if;
 return query select s.user_id,s.name,u.email::text,s.role,s.active,s.protected from public.staff_users s join auth.users u on u.id=s.user_id order by s.name;
end $$;

-- Managed accounts never have direct write/delete privileges on these tables.
revoke insert,update,delete,truncate on public.customers,public.customer_users,public.staff_users,
 public.units,public.unit_base_plan_assignments,public.customization_options,public.customization_groups,
 public.base_plans,public.unit_activity_events from authenticated,anon;
revoke all on function public.update_customer_contact(uuid,text,text),public.set_customer_active(uuid,boolean),
 public.prepare_customer_email(uuid,text),public.cancel_customer_email(uuid,text),
 public.register_customer_account(text,text,text),public.manage_staff(text,text,text,boolean),public.list_staff_accounts() from public,anon;
grant execute on function public.update_customer_contact(uuid,text,text),public.set_customer_active(uuid,boolean),
 public.prepare_customer_email(uuid,text),public.cancel_customer_email(uuid,text),
 public.register_customer_account(text,text,text),public.manage_staff(text,text,text,boolean),public.list_staff_accounts() to authenticated;

-- Existing rows are preserved. The remaining inventory arrives through technical import.
create function public.guard_unit_inventory() returns trigger language plpgsql security definer set search_path='' as $$ begin
 perform pg_catalog.pg_advisory_xact_lock(3892026);
 if (select count(*) from public.units)>=389 then raise exception 'Fixed inventory limit is 389 units' using errcode='22023'; end if;
 return new;
end $$;
revoke all on function public.guard_unit_inventory() from public,anon,authenticated;
create trigger fixed_unit_inventory before insert on public.units for each row execute function public.guard_unit_inventory();


create function public.deadline_notification_eligible(p_id uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.deadline_notifications n
 join public.units u on u.id=n.unit_id and u.active and u.customization_status='pending'
 join public.customer_units cu on cu.unit_id=u.id and cu.customer_id=n.customer_id and cu.active and cu.ownership_role='owner'
 join public.customers c on c.id=n.customer_id and c.active
 join public.customer_users usr on usr.customer_id=c.id and usr.active
 join auth.users au on au.id=usr.user_id and lower(au.email)=lower(n.recipient)
 where n.id=p_id and n.due_date=(clock_timestamp() at time zone 'America/Sao_Paulo')::date
 and (n.deadline at time zone 'America/Sao_Paulo')::date-n.due_date=n.days_before
 and n.deadline>clock_timestamp()
 and ((n.scope='unit' and u.customization_closes_at=n.deadline) or exists(
   select 1 from public.unit_module_windows w join public.customization_modules m on m.code=w.module_code and m.active
   where w.unit_id=n.unit_id and n.scope='module:'||w.module_code and w.status='active' and w.closes_at=n.deadline)));
$$;
revoke all on function public.deadline_notification_eligible(uuid) from public,anon,authenticated;
grant execute on function public.deadline_notification_eligible(uuid) to service_role;

create or replace function public.claim_deadline_notifications(p_limit integer default 50)
returns setof public.deadline_notifications
language plpgsql security definer set search_path = '' as $$
declare v_today date := (clock_timestamp() at time zone 'America/Sao_Paulo')::date;
begin
  if p_limit not between 1 and 100 then raise exception 'Invalid batch size'; end if;
  insert into public.deadline_notifications(unit_id,customer_id,scope,deadline,due_date,days_before,recipient,unit_code,module_name)
  select u.id,cu.customer_id,d.scope,d.deadline,v_today,
    (d.deadline at time zone 'America/Sao_Paulo')::date-v_today,au.email,u.code,d.module_name
  from public.units u
  join public.customer_units cu on cu.unit_id=u.id and cu.active and cu.ownership_role='owner'
  join public.customers c on c.id=cu.customer_id and c.active
  join public.customer_users usr on usr.customer_id=cu.customer_id and usr.active
  join auth.users au on au.id=usr.user_id and au.email is not null
  cross join lateral (
    select 'unit'::text as scope,u.customization_closes_at as deadline,null::text as module_name
    union all
    select 'module:'||w.module_code,w.closes_at,m.name from public.unit_module_windows w
      join public.customization_modules m on m.code=w.module_code and m.active
      where w.unit_id=u.id and w.status='active'
  ) d
  where u.active and u.customization_status='pending' and d.deadline is not null
    and (d.deadline at time zone 'America/Sao_Paulo')::date-v_today in (15,10,5,1)
  on conflict(unit_id,customer_id,scope,deadline,days_before) do nothing;

  return query with batch as (
    select n.id from public.deadline_notifications n
    join public.units u on u.id=n.unit_id and u.active and u.customization_status='pending'
    join public.customer_units cu on cu.unit_id=u.id and cu.customer_id=n.customer_id and cu.active
    where public.deadline_notification_eligible(n.id) and n.due_date=v_today and n.attempts<5 and n.status<>'sent'
      and (n.lease_until is null or n.lease_until<clock_timestamp())
      and ((n.scope='unit' and u.customization_closes_at=n.deadline) or exists(
        select 1 from public.unit_module_windows w where w.unit_id=n.unit_id
          and n.scope='module:'||w.module_code and w.status='active' and w.closes_at=n.deadline))
    order by n.created_at for update of n skip locked limit p_limit
  ) update public.deadline_notifications n set status='sending',attempts=n.attempts+1,
      lease_until=clock_timestamp()+interval '10 minutes'
    from batch where n.id=batch.id returning n.*;
end; $$;



create function public.retry_deadline_notification(p_id uuid) returns void
language plpgsql security definer set search_path='' as $$
declare v_unit uuid;
begin
 if public.current_staff_role() is distinct from 'admin' then raise exception 'Admin required' using errcode='42501'; end if;
 update public.deadline_notifications set status='pending',lease_until=null
 where id=p_id and status='failed' and attempts<5 and (lease_until is null or lease_until<=clock_timestamp())
 and public.deadline_notification_eligible(id) returning unit_id into v_unit;
 if not found then raise exception 'Notification is sent, reserved, exhausted or no longer eligible' using errcode='22023'; end if;
 insert into public.unit_activity_events(unit_id,actor_user_id,actor_role,action,details)
 values(v_unit,(select auth.uid()),'admin','deadline_retry_requested',jsonb_build_object('notification_id',p_id));
end $$;
revoke all on function public.retry_deadline_notification(uuid) from public,anon;
grant execute on function public.retry_deadline_notification(uuid) to authenticated;
