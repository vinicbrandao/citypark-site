-- A request for help is distinct from the owner's authorization. The request
-- can only target an assigned architect with effective authorization.

create table public.architect_assistance_requests (
  id uuid primary key default gen_random_uuid(),
  unit_id uuid not null references public.units(id),
  architect_user_id uuid not null references public.staff_users(user_id),
  requester_customer_id uuid not null,
  requester_user_id uuid not null references auth.users(id),
  message text check (message is null or length(message) <= 2000),
  status text not null default 'requested'
    check (status in ('requested', 'in_progress', 'resolved', 'canceled')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  closed_at timestamptz,
  foreign key (requester_customer_id, unit_id)
    references public.customer_units(customer_id, unit_id),
  check ((status in ('requested', 'in_progress') and closed_at is null)
    or (status in ('resolved', 'canceled') and closed_at is not null))
);
create unique index one_open_architect_assistance_per_unit
  on public.architect_assistance_requests(unit_id)
  where status in ('requested', 'in_progress');
create index architect_assistance_queue_idx
  on public.architect_assistance_requests(architect_user_id, status, created_at);

create table public.architect_assistance_events (
  id bigint generated always as identity primary key,
  request_id uuid not null references public.architect_assistance_requests(id),
  action text not null check (action in ('requested', 'accepted', 'resolved', 'canceled')),
  actor_user_id uuid not null references auth.users(id),
  note text check (note is null or length(note) <= 2000),
  created_at timestamptz not null default now()
);
create index architect_assistance_events_request_idx
  on public.architect_assistance_events(request_id, created_at);

alter table public.architect_assistance_requests enable row level security;
alter table public.architect_assistance_events enable row level security;
revoke all on public.architect_assistance_requests,
  public.architect_assistance_events from public, anon, authenticated;
grant select on public.architect_assistance_requests,
  public.architect_assistance_events to authenticated;
grant all on public.architect_assistance_requests,
  public.architect_assistance_events to service_role;
grant usage, select on sequence public.architect_assistance_events_id_seq
  to service_role;

create policy readable_architect_assistance_requests
  on public.architect_assistance_requests for select to authenticated
  using (exists (select 1 from public.units u where u.id = unit_id));
create policy readable_architect_assistance_events
  on public.architect_assistance_events for select to authenticated
  using (exists (
    select 1 from public.architect_assistance_requests r
    where r.id = request_id
  ));

create function public.request_architect_assistance(
  p_customer_id uuid, p_unit_id uuid, p_architect_user_id uuid,
  p_message text default null
) returns public.architect_assistance_requests
language plpgsql security definer set search_path = '' as $$
declare
  v_request public.architect_assistance_requests;
  v_message text;
begin
  if (select auth.uid()) is null or p_customer_id is null
    or p_unit_id is null or p_architect_user_id is null then
    raise exception 'Unit access denied' using errcode = '42501';
  end if;
  v_message := nullif(btrim(p_message), '');
  if length(v_message) > 2000 then
    raise exception 'Message too long' using errcode = '22023';
  end if;
  -- Consent changes lock the same unit, so request creation sees current access.
  perform 1 from public.units where id = p_unit_id and active for update;
  if not found or not exists (
    select 1 from public.customer_units cu
    join public.customer_users usr
      on usr.customer_id = cu.customer_id and usr.active
    where cu.customer_id = p_customer_id and cu.unit_id = p_unit_id
      and cu.active and cu.ownership_role in ('owner', 'co_owner')
      and usr.user_id = (select auth.uid())
  ) then
    raise exception 'Unit access denied' using errcode = '42501';
  end if;
  if not exists (
    select 1 from public.staff_unit_assignments a
    join public.staff_users s on s.user_id = a.user_id
    where a.unit_id = p_unit_id and a.user_id = p_architect_user_id
      and a.active and s.active and s.role = 'architect'
  ) or not public.current_architect_authorization(p_unit_id, p_architect_user_id) then
    raise exception 'Architect unavailable or not authorized'
      using errcode = '42501';
  end if;
  select * into v_request from public.architect_assistance_requests
    where unit_id = p_unit_id and status in ('requested', 'in_progress')
    for update;
  if v_request.id is not null then
    if v_request.architect_user_id = p_architect_user_id then
      return v_request;
    end if;
    raise exception 'Unit already has an open assistance request'
      using errcode = '23505';
  end if;
  insert into public.architect_assistance_requests
    (unit_id, architect_user_id, requester_customer_id,
     requester_user_id, message)
  values (p_unit_id, p_architect_user_id, p_customer_id,
          (select auth.uid()), v_message)
  returning * into v_request;
  insert into public.architect_assistance_events
    (request_id, action, actor_user_id, note)
  values (v_request.id, 'requested', (select auth.uid()), v_message);
  return v_request;
end;
$$;

create function public.accept_architect_assistance(p_request_id uuid)
returns public.architect_assistance_requests
language plpgsql security definer set search_path = '' as $$
declare v_request public.architect_assistance_requests;
begin
  select * into v_request from public.architect_assistance_requests
    where id = p_request_id for update;
  if v_request.id is null
    or v_request.architect_user_id is distinct from (select auth.uid())
    or not public.staff_can_access_unit(v_request.unit_id) then
    raise exception 'Assistance access denied' using errcode = '42501';
  end if;
  if v_request.status = 'in_progress' then return v_request; end if;
  if v_request.status <> 'requested' then
    raise exception 'Request is closed' using errcode = '22023';
  end if;
  update public.architect_assistance_requests
    set status = 'in_progress', updated_at = clock_timestamp()
    where id = p_request_id returning * into v_request;
  insert into public.architect_assistance_events
    (request_id, action, actor_user_id)
  values (p_request_id, 'accepted', (select auth.uid()));
  return v_request;
end;
$$;

create function public.resolve_architect_assistance(
  p_request_id uuid, p_note text default null
) returns public.architect_assistance_requests
language plpgsql security definer set search_path = '' as $$
declare
  v_request public.architect_assistance_requests;
  v_note text;
  v_now timestamptz;
begin
  v_note := nullif(btrim(p_note), '');
  if length(v_note) > 2000 then
    raise exception 'Note too long' using errcode = '22023';
  end if;
  select * into v_request from public.architect_assistance_requests
    where id = p_request_id for update;
  if v_request.id is null
    or v_request.architect_user_id is distinct from (select auth.uid())
    or not public.staff_can_access_unit(v_request.unit_id) then
    raise exception 'Assistance access denied' using errcode = '42501';
  end if;
  if v_request.status <> 'in_progress' then
    raise exception 'Request is not in progress' using errcode = '22023';
  end if;
  v_now := clock_timestamp();
  update public.architect_assistance_requests
    set status = 'resolved', updated_at = v_now, closed_at = v_now
    where id = p_request_id returning * into v_request;
  insert into public.architect_assistance_events
    (request_id, action, actor_user_id, note)
  values (p_request_id, 'resolved', (select auth.uid()), v_note);
  return v_request;
end;
$$;

create function public.cancel_architect_assistance(p_request_id uuid)
returns public.architect_assistance_requests
language plpgsql security definer set search_path = '' as $$
declare
  v_request public.architect_assistance_requests;
  v_now timestamptz;
begin
  select * into v_request from public.architect_assistance_requests
    where id = p_request_id for update;
  if v_request.id is null or not exists (
    select 1 from public.customer_units cu
    join public.customer_users usr
      on usr.customer_id = cu.customer_id and usr.active
    join public.units u on u.id = cu.unit_id and u.active
    where cu.unit_id = v_request.unit_id and cu.active
      and cu.ownership_role in ('owner', 'co_owner')
      and usr.user_id = (select auth.uid())
  ) then
    raise exception 'Assistance access denied' using errcode = '42501';
  end if;
  if v_request.status not in ('requested', 'in_progress') then
    raise exception 'Request is closed' using errcode = '22023';
  end if;
  v_now := clock_timestamp();
  update public.architect_assistance_requests
    set status = 'canceled', updated_at = v_now, closed_at = v_now
    where id = p_request_id returning * into v_request;
  insert into public.architect_assistance_events
    (request_id, action, actor_user_id)
  values (p_request_id, 'canceled', (select auth.uid()));
  return v_request;
end;
$$;

revoke all on function public.request_architect_assistance(uuid, uuid, uuid, text),
  public.accept_architect_assistance(uuid),
  public.resolve_architect_assistance(uuid, text),
  public.cancel_architect_assistance(uuid)
  from public, anon;
grant execute on function public.request_architect_assistance(uuid, uuid, uuid, text),
  public.accept_architect_assistance(uuid),
  public.resolve_architect_assistance(uuid, text),
  public.cancel_architect_assistance(uuid)
  to authenticated;
