-- One submitted proposal per unit. Module saves after submission append a new
-- immutable version of that same proposal, keeping earlier versions readable.

alter table public.customization_groups
  add column required_for_submission boolean not null default true;

create table public.unit_proposals (
  id uuid primary key default gen_random_uuid(),
  unit_id uuid not null unique references public.units(id),
  latest_revision integer not null default 1 check (latest_revision > 0),
  submitted_by_customer_id uuid not null,
  submitted_by_user_id uuid not null references auth.users(id),
  submitted_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (submitted_by_customer_id, unit_id)
    references public.customer_units(customer_id, unit_id)
);

create table public.unit_proposal_versions (
  proposal_id uuid not null references public.unit_proposals(id),
  revision integer not null check (revision > 0),
  action text not null check (action in ('submitted', 'choices_updated')),
  base_plan_id uuid not null references public.base_plans(id),
  selections jsonb not null check (jsonb_typeof(selections) = 'object'),
  module_revisions jsonb not null
    check (jsonb_typeof(module_revisions) = 'object'),
  actor_user_id uuid not null references auth.users(id),
  actor_customer_id uuid,
  actor_ownership_role text,
  actor_staff_role text,
  source_module_code text references public.customization_modules(code),
  source_module_revision integer,
  created_at timestamptz not null default now(),
  primary key (proposal_id, revision),
  check ((action = 'submitted' and revision = 1
            and source_module_code is null and source_module_revision is null)
      or (action = 'choices_updated' and revision > 1
            and source_module_code is not null and source_module_revision > 0)),
  check ((actor_customer_id is not null
            and actor_ownership_role in ('owner', 'co_owner')
            and actor_staff_role is null)
      or (actor_customer_id is null and actor_ownership_role is null
            and actor_staff_role in ('admin', 'architect')))
);
create index unit_proposal_versions_actor_idx
  on public.unit_proposal_versions(actor_user_id, created_at desc);

-- Technical review is attached to one proposal revision, not a final
-- commercial approval. A later edit produces another version to review.
create table public.unit_proposal_reviews (
  proposal_id uuid not null,
  revision integer not null,
  decision text not null check (decision in ('approved', 'changes_requested')),
  note text check (note is null or length(note) <= 2000),
  reviewer_user_id uuid not null references public.staff_users(user_id),
  reviewed_at timestamptz not null default now(),
  primary key (proposal_id, revision),
  foreign key (proposal_id, revision)
    references public.unit_proposal_versions(proposal_id, revision),
  check (decision <> 'changes_requested'
    or (note is not null and length(btrim(note)) > 0))
);

alter table public.unit_proposals enable row level security;
alter table public.unit_proposal_versions enable row level security;
alter table public.unit_proposal_reviews enable row level security;
revoke all on public.unit_proposals, public.unit_proposal_versions,
  public.unit_proposal_reviews from public, anon, authenticated;
grant select on public.unit_proposals, public.unit_proposal_versions,
  public.unit_proposal_reviews to authenticated;
grant all on public.unit_proposals, public.unit_proposal_versions,
  public.unit_proposal_reviews to service_role;

create policy readable_unit_proposals on public.unit_proposals
  for select to authenticated using (
    exists (select 1 from public.units u where u.id = unit_id)
  );
create policy readable_unit_proposal_versions on public.unit_proposal_versions
  for select to authenticated using (
    exists (select 1 from public.unit_proposals p where p.id = proposal_id)
  );
create policy readable_unit_proposal_reviews on public.unit_proposal_reviews
  for select to authenticated using (
    exists (select 1 from public.unit_proposals p where p.id = proposal_id)
  );

create function public.unit_module_revision_snapshot(p_unit_id uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_object_agg(s.module_code, s.revision), '{}'::jsonb)
  from public.unit_module_states s where s.unit_id = p_unit_id;
$$;
revoke all on function public.unit_module_revision_snapshot(uuid)
  from public, anon, authenticated;

create function public.unit_module_choice_snapshot(p_unit_id uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_object_agg(x.module_code, x.choices), '{}'::jsonb)
  from (
    select state.module_code,
      coalesce(jsonb_object_agg(s.group_id::text, s.option_id::text)
        filter (where s.group_id is not null), '{}'::jsonb) as choices
    from public.unit_module_states state
    left join public.unit_module_selections s
      on s.unit_id = state.unit_id and s.module_code = state.module_code
    where state.unit_id = p_unit_id
    group by state.module_code
  ) x;
$$;
revoke all on function public.unit_module_choice_snapshot(uuid)
  from public, anon, authenticated;

create function public.submit_unit_proposal(
  p_customer_id uuid, p_unit_id uuid, p_expected_module_revisions jsonb
) returns public.unit_proposals
language plpgsql security definer set search_path = '' as $$
declare
  v_role text;
  v_plan_id uuid;
  v_expected jsonb;
  v_choices jsonb;
  v_proposal public.unit_proposals;
begin
  if (select auth.uid()) is null or p_customer_id is null or p_unit_id is null
    or jsonb_typeof(p_expected_module_revisions) is distinct from 'object' then
    raise exception 'Invalid proposal submission' using errcode = '22023';
  end if;
  -- Same order as module saves; proposal submission observes a stable snapshot.
  perform 1 from public.units where id = p_unit_id and active for update;
  if not found then
    raise exception 'Unit access denied' using errcode = '42501';
  end if;
  select cu.ownership_role into v_role
  from public.customer_units cu
  join public.customer_users usr
    on usr.customer_id = cu.customer_id and usr.active
  where cu.customer_id = p_customer_id and cu.unit_id = p_unit_id
    and cu.active and usr.user_id = (select auth.uid());
  if v_role is null or v_role not in ('owner', 'co_owner') then
    raise exception 'Unit access denied' using errcode = '42501';
  end if;
  select a.base_plan_id into v_plan_id
  from public.unit_base_plan_assignments a
  join public.base_plans p on p.id = a.base_plan_id and p.status = 'active'
  where a.unit_id = p_unit_id for share of a, p;
  if v_plan_id is null then
    raise exception 'Base plan not assigned' using errcode = '22023';
  end if;
  v_expected := public.unit_module_revision_snapshot(p_unit_id);
  if v_expected <> p_expected_module_revisions then
    raise exception 'Configuration changed in another session'
      using errcode = '40001';
  end if;
  if not exists (select 1 from public.unit_module_selections
                 where unit_id = p_unit_id) then
    raise exception 'No choices to submit' using errcode = '22023';
  end if;
  if exists (
    select 1 from public.customization_groups g
    join public.customization_modules m
      on m.code = g.module_code and m.active
    where g.status = 'active' and g.required_for_submission
      and exists (
        select 1 from public.customization_options o
        join public.base_plan_option_availability a
          on a.option_id = o.id and a.base_plan_id = v_plan_id
        where o.group_id = g.id and o.status = 'active'
      )
      and not exists (
        select 1 from public.unit_module_selections s
        where s.unit_id = p_unit_id and s.group_id = g.id
      )
  ) then
    raise exception 'Required choices are incomplete' using errcode = '22023';
  end if;
  if exists (
    select 1 from public.unit_module_selections s
    left join public.customization_groups g on g.id = s.group_id
    left join public.customization_modules m on m.code = s.module_code
    left join public.customization_options o on o.id = s.option_id
    left join public.base_plan_option_availability a
      on a.option_id = s.option_id and a.base_plan_id = v_plan_id
    where s.unit_id = p_unit_id and (
      g.status is distinct from 'active'
      or g.module_code is distinct from s.module_code
      or m.active is distinct from true
      or o.status is distinct from 'active'
      or o.group_id is distinct from s.group_id
      or a.option_id is null
    )
  ) or exists (
    select 1 from public.base_plan_option_exclusions e
    join public.unit_module_selections first_choice
      on first_choice.unit_id = p_unit_id
     and first_choice.option_id = e.first_option_id
    join public.unit_module_selections second_choice
      on second_choice.unit_id = p_unit_id
     and second_choice.option_id = e.second_option_id
    where e.base_plan_id = v_plan_id
  ) then
    raise exception 'Current choices unavailable for base plan'
      using errcode = '22023';
  end if;

  select * into v_proposal from public.unit_proposals
    where unit_id = p_unit_id for update;
  if v_proposal.id is not null then return v_proposal; end if;
  v_choices := public.unit_module_choice_snapshot(p_unit_id);
  insert into public.unit_proposals
    (unit_id, submitted_by_customer_id, submitted_by_user_id)
  values (p_unit_id, p_customer_id, (select auth.uid()))
  returning * into v_proposal;
  insert into public.unit_proposal_versions
    (proposal_id, revision, action, base_plan_id, selections,
     module_revisions, actor_user_id, actor_customer_id, actor_ownership_role)
  values (v_proposal.id, 1, 'submitted', v_plan_id, v_choices,
          v_expected, (select auth.uid()), p_customer_id, v_role);
  return v_proposal;
end;
$$;
revoke all on function public.submit_unit_proposal(uuid, uuid, jsonb)
  from public, anon;
grant execute on function public.submit_unit_proposal(uuid, uuid, jsonb)
  to authenticated;

create function public.append_proposal_version_after_module_save()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_proposal public.unit_proposals;
begin
  select * into v_proposal from public.unit_proposals
    where unit_id = new.unit_id for update;
  if v_proposal.id is null then return new; end if;
  update public.unit_proposals
    set latest_revision = latest_revision + 1,
        updated_at = clock_timestamp()
    where id = v_proposal.id returning * into v_proposal;
  insert into public.unit_proposal_versions
    (proposal_id, revision, action, base_plan_id, selections,
     module_revisions, actor_user_id, actor_customer_id,
     actor_ownership_role, actor_staff_role,
     source_module_code, source_module_revision)
  values (v_proposal.id, v_proposal.latest_revision, 'choices_updated',
    new.base_plan_id, public.unit_module_choice_snapshot(new.unit_id),
    public.unit_module_revision_snapshot(new.unit_id),
    new.actor_user_id, new.actor_customer_id,
    new.actor_ownership_role, new.actor_staff_role,
    new.module_code, new.revision);
  return new;
end;
$$;
revoke all on function public.append_proposal_version_after_module_save()
  from public, anon, authenticated;
create trigger append_proposal_version_after_module_save
  after insert on public.unit_module_history
  for each row execute function public.append_proposal_version_after_module_save();

-- Reassigning the base plan after submission needs an explicit migration of
-- choices and a new proposal version; until that workflow exists, reject it.
create function public.guard_submitted_base_plan_assignment()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if tg_op = 'DELETE' then
    if exists (select 1 from public.unit_proposals p where p.unit_id = old.unit_id) then
      raise exception 'Submitted proposal requires a plan-change workflow'
        using errcode = '42501';
    end if;
    return old;
  end if;
  if old.base_plan_id is distinct from new.base_plan_id
    and exists (select 1 from public.unit_proposals p where p.unit_id = old.unit_id) then
    raise exception 'Submitted proposal requires a plan-change workflow'
      using errcode = '42501';
  end if;
  return new;
end;
$$;
revoke all on function public.guard_submitted_base_plan_assignment()
  from public, anon, authenticated;
create trigger guard_submitted_base_plan_assignment
  before update or delete on public.unit_base_plan_assignments
  for each row execute function public.guard_submitted_base_plan_assignment();

create function public.review_unit_proposal(
  p_unit_id uuid, p_expected_revision integer,
  p_decision text, p_note text default null
) returns public.unit_proposal_reviews
language plpgsql security definer set search_path = '' as $$
declare
  v_proposal public.unit_proposals;
  v_review public.unit_proposal_reviews;
  v_note text;
begin
  if (select public.current_staff_role()) is distinct from 'architect'
    or not public.staff_can_access_unit(p_unit_id) then
    raise exception 'Technical review denied' using errcode = '42501';
  end if;
  v_note := nullif(btrim(p_note), '');
  if p_expected_revision is null or p_expected_revision < 1
    or p_decision not in ('approved', 'changes_requested')
    or p_decision is null or length(v_note) > 2000
    or (p_decision = 'changes_requested' and v_note is null) then
    raise exception 'Invalid technical review' using errcode = '22023';
  end if;
  perform 1 from public.units where id = p_unit_id and active for update;
  if not found or not public.staff_can_access_unit(p_unit_id) then
    raise exception 'Technical review denied' using errcode = '42501';
  end if;
  select * into v_proposal from public.unit_proposals
    where unit_id = p_unit_id for update;
  if v_proposal.id is null or v_proposal.latest_revision <> p_expected_revision then
    raise exception 'Proposal changed in another session'
      using errcode = '40001';
  end if;
  insert into public.unit_proposal_reviews
    (proposal_id, revision, decision, note, reviewer_user_id)
  values (v_proposal.id, p_expected_revision, p_decision,
          v_note, (select auth.uid()))
  returning * into v_review;
  return v_review;
end;
$$;
revoke all on function public.review_unit_proposal(uuid, integer, text, text)
  from public, anon;
grant execute on function public.review_unit_proposal(uuid, integer, text, text)
  to authenticated;
