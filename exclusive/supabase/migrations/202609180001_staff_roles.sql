create table public.staff_users (
  user_id uuid primary key references auth.users(id) on delete cascade,
  name text not null,
  role text not null check (role in ('admin','architect')),
  active boolean not null default true
);
alter table public.staff_users enable row level security;
revoke all on public.staff_users from anon, authenticated;
grant select on public.staff_users to authenticated;
grant all on public.staff_users to service_role;
create policy own_staff_role on public.staff_users for select to authenticated using (user_id = (select auth.uid()));
create function public.current_staff_role() returns text language sql stable security definer set search_path = '' as $$
  select role from public.staff_users where user_id = auth.uid() and active;
$$;
revoke all on function public.current_staff_role() from public, anon;
grant execute on function public.current_staff_role() to authenticated;
create policy staff_units on public.units for select to authenticated using (active and public.current_staff_role() in ('admin','architect'));
create policy staff_drafts on public.unit_drafts for select to authenticated using (public.current_staff_role() in ('admin','architect'));
create table public.draft_history (
  id bigint generated always as identity primary key,
  unit_id uuid not null references public.units(id),
  revision integer not null,
  selections jsonb not null,
  actor_id uuid not null references auth.users(id),
  actor_role text not null,
  created_at timestamptz not null default now()
);
alter table public.draft_history enable row level security;
revoke all on public.draft_history from anon, authenticated;
grant select on public.draft_history to authenticated;
grant all on public.draft_history to service_role;
create policy staff_history on public.draft_history for select to authenticated using (public.current_staff_role() in ('admin','architect'));
create function public.record_draft_history() returns trigger language plpgsql security definer set search_path = '' as $$
begin
 insert into public.draft_history(unit_id,revision,selections,actor_id,actor_role)
 values(new.unit_id,new.revision,new.selections,new.updated_by,coalesce(public.current_staff_role(),'customer'));
 return new;
end; $$;
revoke all on function public.record_draft_history() from public, anon, authenticated;
create trigger draft_audit after insert or update on public.unit_drafts for each row execute function public.record_draft_history();
create or replace function public.save_unit_draft(p_unit_id uuid, p_selections jsonb, p_expected_revision integer)
returns public.unit_drafts
language plpgsql security definer set search_path = '' as $$
declare
  result public.unit_drafts;
  item record;
begin
  if auth.uid() is null or not exists (select 1 from public.units where id = p_unit_id and active) or (coalesce(public.current_staff_role(), '') not in ('admin', 'architect') and not exists (
    select 1 from public.units u
    join public.customer_units cu on cu.unit_id = u.id and cu.active
    join public.customer_users usr on usr.customer_id = cu.customer_id and usr.active
    where u.id = p_unit_id and u.active and usr.user_id = auth.uid()
  )) then raise exception 'Unit access denied' using errcode = '42501'; end if;
  if p_expected_revision is null or p_expected_revision < 0
     or p_selections is null or jsonb_typeof(p_selections) <> 'object' then
    raise exception 'Invalid draft' using errcode = '22023';
  end if;
  -- Initial catalog allowlist; migrate to a versioned catalog before confirmation.
  for item in select * from jsonb_each(p_selections) loop
    if not (case item.key
      when 'socialPlant' then item.value in ('null'::jsonb, '"social-original"', '"social-standard"', '"social-veranda"', '"social-full"')
      when 'suitePlant' then item.value in ('null'::jsonb, '"suite-standard"', '"suite-closet"', '"suite-office"')
      when 'counter' then item.value in ('"counter-standard"'::jsonb, '"counter-extended"')
      when 'stone' then item.value in ('"sao-marco"'::jsonb, '"bellagio"')
      when 'rodamao' then item.value in ('"padrao"'::jsonb, '"60"')
      when 'service' then item.value in ('"service-no"'::jsonb, '"service-yes"')
      else false end) then raise exception 'Invalid selection' using errcode = '22023'; end if;
  end loop;
  if not (p_selections ?& array['socialPlant','suitePlant','counter','stone','rodamao','service']) then
    raise exception 'Incomplete draft' using errcode = '22023';
  end if;
  if p_expected_revision = 0 then
    insert into public.unit_drafts(unit_id, selections, updated_by)
    values (p_unit_id, p_selections, auth.uid())
    on conflict (unit_id) do nothing returning * into result;
  else
    update public.unit_drafts
    set selections = p_selections, revision = revision + 1, updated_by = auth.uid(), updated_at = now()
    where unit_id = p_unit_id and revision = p_expected_revision returning * into result;
  end if;
  if result.unit_id is null then raise exception 'Draft changed in another session' using errcode = '40001'; end if;
  return result;
end;
$$;
revoke all on function public.save_unit_draft(uuid, jsonb, integer) from public, anon;
grant execute on function public.save_unit_draft(uuid, jsonb, integer) to authenticated;


