\set ON_ERROR_STOP on
-- Local Supabase fixture: every request and consent change is rolled back.
begin;
select u.id as source_unit_id from public.units u where u.code = '1401A' \gset
select cu.customer_id as owner_customer_id, usr.user_id as owner_user_id
from public.customer_units cu
join public.customer_users usr on usr.customer_id = cu.customer_id and usr.active
where cu.unit_id = :'source_unit_id'::uuid and cu.ownership_role = 'owner' and cu.active \gset
select usr.user_id as co_user_id
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

insert into public.units(code, tower, floor_label, termination, typology)
select 'LOCAL-TEST-' || gen_random_uuid()::text, tower, floor_label, termination, typology
from public.units where id = :'source_unit_id'::uuid
returning id as unit_id \gset
insert into public.customer_units(customer_id, unit_id, ownership_role)
values (:'owner_customer_id'::uuid, :'unit_id'::uuid, 'owner'),
       ((select customer_id from public.customer_units
         where unit_id = :'source_unit_id'::uuid and ownership_role = 'co_owner'
           and active limit 1), :'unit_id'::uuid, 'co_owner');
insert into public.staff_unit_assignments(user_id, unit_id)
values (:'architect_user_id'::uuid, :'unit_id'::uuid);
insert into public.architect_authorizations
  (unit_id, architect_user_id, granted_by_customer_id, granted_by_user_id)
values (:'unit_id'::uuid, :'architect_user_id'::uuid,
        :'owner_customer_id'::uuid, :'owner_user_id'::uuid);

select set_config('test.unit_id', :'unit_id', true);
select set_config('test.owner_customer_id', :'owner_customer_id', true);
select set_config('test.outsider_customer_id', :'outsider_customer_id', true);
select set_config('test.architect_user_id', :'architect_user_id', true);

set role authenticated;
select set_config('request.jwt.claim.sub', :'owner_user_id', true);
select (public.request_architect_assistance(
  :'owner_customer_id'::uuid, :'unit_id'::uuid,
  :'architect_user_id'::uuid, 'Preciso de ajuda')).id as first_request_id \gset
select set_config('test.first_request_id', :'first_request_id', true);
do $$
declare repeated public.architect_assistance_requests;
begin
  repeated := public.request_architect_assistance(
    current_setting('test.owner_customer_id')::uuid,
    current_setting('test.unit_id')::uuid,
    current_setting('test.architect_user_id')::uuid, 'Pedido repetido');
  if repeated.id <> current_setting('test.first_request_id')::uuid then
    raise exception 'duplicate request created';
  end if;
  if (select count(*) from public.architect_assistance_events
      where request_id = repeated.id) <> 1 then
    raise exception 'duplicate event created';
  end if;
  if has_table_privilege('authenticated',
      'public.architect_assistance_requests', 'INSERT') then
    raise exception 'direct insert granted';
  end if;
end $$;

select set_config('request.jwt.claim.sub', :'outsider_user_id', true);
do $$
begin
  if (select count(*) from public.architect_assistance_requests
      where unit_id = current_setting('test.unit_id')::uuid) <> 0 then
    raise exception 'request leaked through RLS';
  end if;
  begin
    perform public.request_architect_assistance(
      current_setting('test.outsider_customer_id')::uuid,
      current_setting('test.unit_id')::uuid,
      current_setting('test.architect_user_id')::uuid);
    raise exception 'outsider created request';
  exception when sqlstate '42501' then null;
  end;
end $$;

select set_config('request.jwt.claim.sub', :'architect_user_id', true);
do $$
declare accepted public.architect_assistance_requests;
begin
  if (select count(*) from public.architect_assistance_requests
      where id = current_setting('test.first_request_id')::uuid) <> 1 then
    raise exception 'architect cannot see request';
  end if;
  accepted := public.accept_architect_assistance(
    current_setting('test.first_request_id')::uuid);
  if accepted.status <> 'in_progress' then raise exception 'accept failed'; end if;
end $$;

select set_config('request.jwt.claim.sub', :'co_user_id', true);
do $$
declare canceled public.architect_assistance_requests;
begin
  canceled := public.cancel_architect_assistance(
    current_setting('test.first_request_id')::uuid);
  if canceled.status <> 'canceled' or canceled.closed_at is null then
    raise exception 'co-owner cancel failed';
  end if;
end $$;

select set_config('request.jwt.claim.sub', :'architect_user_id', true);
do $$
begin
  begin
    perform public.resolve_architect_assistance(
      current_setting('test.first_request_id')::uuid);
    raise exception 'canceled request was resolved';
  exception when sqlstate '22023' then null;
  end;
end $$;

select set_config('request.jwt.claim.sub', :'owner_user_id', true);
select public.set_architect_authorization(
  :'owner_customer_id'::uuid, :'unit_id'::uuid,
  :'architect_user_id'::uuid, false);
do $$
begin
  begin
    perform public.request_architect_assistance(
      current_setting('test.owner_customer_id')::uuid,
      current_setting('test.unit_id')::uuid,
      current_setting('test.architect_user_id')::uuid);
    raise exception 'request accepted after authorization revoked';
  exception when sqlstate '42501' then null;
  end;
end $$;
select public.set_architect_authorization(
  :'owner_customer_id'::uuid, :'unit_id'::uuid,
  :'architect_user_id'::uuid, true);

select (public.request_architect_assistance(
  :'owner_customer_id'::uuid, :'unit_id'::uuid,
  :'architect_user_id'::uuid)).id as second_request_id \gset
select set_config('test.second_request_id', :'second_request_id', true);
select set_config('request.jwt.claim.sub', :'architect_user_id', true);
do $$
declare resolved public.architect_assistance_requests;
begin
  perform public.accept_architect_assistance(
    current_setting('test.second_request_id')::uuid);
  resolved := public.resolve_architect_assistance(
    current_setting('test.second_request_id')::uuid, 'Atendimento concluído');
  if resolved.status <> 'resolved'
    or (select count(*) from public.architect_assistance_events
        where request_id = resolved.id) <> 3 then
    raise exception 'resolution or event history failed';
  end if;
end $$;
reset role;

rollback;
select 'PASS: request, authorization, owner/co-owner, architect, RLS, status transitions and events; fixtures rolled back' as result;
