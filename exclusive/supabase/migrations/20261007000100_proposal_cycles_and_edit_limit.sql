-- Proposal cycles and explicit resubmission limit.
-- Business rule decided on 07/10/2026:
--   * each proposal cycle starts with one submission;
--   * the customer may resubmit at most three times (4 versions total);
--   * module saves do not create proposal versions by themselves;
--   * the architect reviews only the latest submitted version;
--   * once reviewed, the cycle closes and a new cycle may be submitted.

alter table public.unit_proposals
  add column cycle_number integer not null default 1,
  add column status text not null default 'open',
  add column reviewed_at timestamptz;

alter table public.unit_proposals
  add constraint unit_proposals_cycle_number_check check (cycle_number > 0),
  add constraint unit_proposals_status_check check (status in ('open', 'reviewed'));

-- The previous model allowed only one proposal row for the whole unit lifetime.
-- Keep existing rows as cycle 1, then allow future reviewed cycles to remain in history.
alter table public.unit_proposals
  drop constraint if exists unit_proposals_unit_id_key;

create unique index unit_proposals_unit_cycle_key
  on public.unit_proposals(unit_id, cycle_number);

-- A unit can have many historical cycles, but only one cycle waiting for review.
create unique index unit_proposals_one_open_cycle_per_unit
  on public.unit_proposals(unit_id) where status = 'open';

-- If an existing latest version was already reviewed, mark that legacy cycle closed.
update public.unit_proposals p
set status = 'reviewed', reviewed_at = r.reviewed_at, updated_at = greatest(p.updated_at, r.reviewed_at)
from public.unit_proposal_reviews r
where r.proposal_id = p.id
  and r.revision = p.latest_revision;

-- Old behavior created a proposal version after every module save. Versions now exist
-- only when the customer explicitly submits/re-submits the proposal.
drop trigger if exists append_proposal_version_after_module_save
  on public.unit_module_history;
drop function if exists public.append_proposal_version_after_module_save();

-- Once the fourth submitted version exists, freeze that open cycle for the
-- customer and architect. Otherwise an architect edit could create unsent changes
-- that the customer is no longer allowed to resubmit. Admin remains the explicit
-- operational exception.
create function public.guard_open_proposal_edit_limit()
returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  v_status text;
  v_latest_revision integer;
begin
  if new.actor_staff_role = 'admin' then
    return new;
  end if;

  select p.status, p.latest_revision
    into v_status, v_latest_revision
  from public.unit_proposals p
  where p.unit_id = new.unit_id
  order by p.cycle_number desc
  limit 1;

  if v_status = 'open' and v_latest_revision >= 4 then
    raise exception 'Proposal edit limit reached' using errcode = 'P0001';
  end if;

  return new;
end;
$$;

revoke all on function public.guard_open_proposal_edit_limit()
  from public, anon, authenticated;

create trigger guard_open_proposal_edit_limit
  before insert on public.unit_module_history
  for each row execute function public.guard_open_proposal_edit_limit();

create or replace function public.submit_unit_proposal(
  p_customer_id uuid, p_unit_id uuid, p_expected_module_revisions jsonb
) returns public.unit_proposals
language plpgsql security definer set search_path = '' as $$
declare
  v_role text;
  v_plan_id uuid;
  v_expected jsonb;
  v_choices jsonb;
  v_proposal public.unit_proposals;
  v_last_module_revisions jsonb;
  v_next_cycle integer;
  v_next_revision integer;
begin
  if (select auth.uid()) is null or p_customer_id is null or p_unit_id is null
    or jsonb_typeof(p_expected_module_revisions) is distinct from 'object' then
    raise exception 'Invalid proposal submission' using errcode = '22023';
  end if;

  -- Serialize customer submission, architect review and unit-level changes.
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

  v_choices := public.unit_module_choice_snapshot(p_unit_id);

  select * into v_proposal
  from public.unit_proposals p
  where p.unit_id = p_unit_id
  order by p.cycle_number desc
  limit 1
  for update;

  -- No proposal yet, or the previous cycle already received the architect's answer:
  -- begin a new independent cycle with revision 1.
  if v_proposal.id is null or v_proposal.status = 'reviewed' then
    v_next_cycle := coalesce(v_proposal.cycle_number, 0) + 1;

    insert into public.unit_proposals
      (unit_id, cycle_number, status, latest_revision,
       submitted_by_customer_id, submitted_by_user_id,
       submitted_at, updated_at, reviewed_at)
    values
      (p_unit_id, v_next_cycle, 'open', 1,
       p_customer_id, (select auth.uid()),
       clock_timestamp(), clock_timestamp(), null)
    returning * into v_proposal;

    insert into public.unit_proposal_versions
      (proposal_id, revision, action, base_plan_id, selections,
       module_revisions, actor_user_id, actor_customer_id, actor_ownership_role)
    values
      (v_proposal.id, 1, 'submitted', v_plan_id, v_choices,
       v_expected, (select auth.uid()), p_customer_id, v_role);

    return v_proposal;
  end if;

  -- Current cycle is still open. The initial submission plus three resubmissions
  -- means revision 4 is the hard limit.
  if v_proposal.latest_revision >= 4 then
    raise exception 'Proposal edit limit reached' using errcode = 'P0001';
  end if;

  select v.module_revisions into v_last_module_revisions
  from public.unit_proposal_versions v
  where v.proposal_id = v_proposal.id
    and v.revision = v_proposal.latest_revision;

  if v_last_module_revisions = v_expected then
    raise exception 'No proposal changes to submit' using errcode = 'P0001';
  end if;

  v_next_revision := v_proposal.latest_revision + 1;

  update public.unit_proposals
  set latest_revision = v_next_revision,
      updated_at = clock_timestamp()
  where id = v_proposal.id
  returning * into v_proposal;

  insert into public.unit_proposal_versions
    (proposal_id, revision, action, base_plan_id, selections,
     module_revisions, actor_user_id, actor_customer_id, actor_ownership_role)
  values
    (v_proposal.id, v_next_revision, 'choices_updated', v_plan_id, v_choices,
     v_expected, (select auth.uid()), p_customer_id, v_role);

  return v_proposal;
end;
$$;

revoke all on function public.submit_unit_proposal(uuid, uuid, jsonb)
  from public, anon;
grant execute on function public.submit_unit_proposal(uuid, uuid, jsonb)
  to authenticated;

create or replace function public.review_unit_proposal(
  p_unit_id uuid, p_expected_revision integer,
  p_decision text, p_note text default null
) returns public.unit_proposal_reviews
language plpgsql security definer set search_path = '' as $$
declare
  v_proposal public.unit_proposals;
  v_review public.unit_proposal_reviews;
  v_note text;
  v_submitted_module_revisions jsonb;
  v_current_module_revisions jsonb;
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

  select * into v_proposal
  from public.unit_proposals p
  where p.unit_id = p_unit_id
  order by p.cycle_number desc
  limit 1
  for update;

  if v_proposal.id is null or v_proposal.status <> 'open'
    or v_proposal.latest_revision <> p_expected_revision then
    raise exception 'Proposal changed in another session'
      using errcode = '40001';
  end if;

  select v.module_revisions into v_submitted_module_revisions
  from public.unit_proposal_versions v
  where v.proposal_id = v_proposal.id
    and v.revision = p_expected_revision;

  v_current_module_revisions := public.unit_module_revision_snapshot(p_unit_id);
  if v_current_module_revisions <> v_submitted_module_revisions then
    raise exception 'Proposal has unsent changes' using errcode = 'P0001';
  end if;

  insert into public.unit_proposal_reviews
    (proposal_id, revision, decision, note, reviewer_user_id)
  values
    (v_proposal.id, p_expected_revision, p_decision,
     v_note, (select auth.uid()))
  returning * into v_review;

  update public.unit_proposals
  set status = 'reviewed', reviewed_at = v_review.reviewed_at,
      updated_at = greatest(updated_at, v_review.reviewed_at)
  where id = v_proposal.id;

  return v_review;
end;
$$;

revoke all on function public.review_unit_proposal(uuid, integer, text, text)
  from public, anon;
grant execute on function public.review_unit_proposal(uuid, integer, text, text)
  to authenticated;
