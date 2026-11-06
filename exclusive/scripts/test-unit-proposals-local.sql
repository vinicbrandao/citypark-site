\set ON_ERROR_STOP on
-- Local Supabase test. All fixtures and proposal cycles below are rolled back.
begin;
select id as source_unit_id from public.units where code = '1401A' \gset
select cu.customer_id as owner_customer_id, usr.user_id as owner_user_id
from public.customer_units cu
join public.customer_users usr on usr.customer_id = cu.customer_id and usr.active
where cu.unit_id = :'source_unit_id'::uuid and cu.ownership_role = 'owner' and cu.active \gset
select cu.customer_id as co_customer_id, usr.user_id as co_user_id
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
       (:'co_customer_id'::uuid, :'unit_id'::uuid, 'co_owner');
insert into public.staff_unit_assignments(user_id, unit_id)
values (:'architect_user_id'::uuid, :'unit_id'::uuid);
insert into public.architect_authorizations
  (unit_id, architect_user_id, granted_by_customer_id, granted_by_user_id)
values (:'unit_id'::uuid, :'architect_user_id'::uuid,
        :'owner_customer_id'::uuid, :'owner_user_id'::uuid);

insert into public.base_plans(code, name)
values ('proposal-test-' || gen_random_uuid()::text, 'Temporary proposal plan')
returning id as plan_id \gset
insert into public.unit_base_plan_assignments(unit_id, base_plan_id)
values (:'unit_id'::uuid, :'plan_id'::uuid);
insert into public.customization_groups(code, name, module_code)
values ('proposal-test-' || gen_random_uuid()::text, 'Required plant group', 'planta')
returning id as group_id \gset
insert into public.customization_options(group_id, code, name)
values (:'group_id'::uuid, 'choice', 'Temporary choice')
returning id as option_id \gset
insert into public.customization_groups(code, name, module_code)
values ('proposal-test-' || gen_random_uuid()::text, 'Second required group', 'planta')
returning id as second_group_id \gset
insert into public.customization_options(group_id, code, name)
values (:'second_group_id'::uuid, 'choice', 'Other temporary choice')
returning id as second_option_id \gset
insert into public.base_plan_option_availability(base_plan_id, option_id)
values (:'plan_id'::uuid, :'option_id'::uuid),
       (:'plan_id'::uuid, :'second_option_id'::uuid);
insert into public.unit_module_windows(unit_id, module_code, opens_at, closes_at)
values (:'unit_id'::uuid, 'planta', clock_timestamp() - interval '1 day',
        clock_timestamp() + interval '1 day');

select set_config('test.unit_id', :'unit_id', true);
select set_config('test.owner_customer_id', :'owner_customer_id', true);
select set_config('test.co_customer_id', :'co_customer_id', true);
select set_config('test.outsider_customer_id', :'outsider_customer_id', true);
select set_config('test.group_id', :'group_id', true);
select set_config('test.option_id', :'option_id', true);

-- Initial draft and existing completeness/concurrency guards.
set role authenticated;
select set_config('request.jwt.claim.sub', :'owner_user_id', true);
select public.save_unit_module_choices(
  :'owner_customer_id'::uuid, :'unit_id'::uuid, 'planta',
  jsonb_build_object(:'group_id', :'option_id'), 0);
do $$
begin
  begin
    perform public.submit_unit_proposal(
      current_setting('test.owner_customer_id')::uuid,
      current_setting('test.unit_id')::uuid, '{"planta":0}'::jsonb);
    raise exception 'stale configuration was submitted';
  exception when sqlstate '40001' then null;
  end;
  begin
    perform public.submit_unit_proposal(
      current_setting('test.owner_customer_id')::uuid,
      current_setting('test.unit_id')::uuid, '{"planta":1}'::jsonb);
    raise exception 'incomplete required group was submitted';
  exception when sqlstate '22023' then null;
  end;
end $$;
reset role;

update public.customization_groups
set required_for_submission = false where id = :'second_group_id'::uuid;

-- Cycle 1, submission 1/4.
set role authenticated;
select set_config('request.jwt.claim.sub', :'owner_user_id', true);
select (public.submit_unit_proposal(
  :'owner_customer_id'::uuid, :'unit_id'::uuid,
  '{"planta":1}'::jsonb)).id as proposal_id \gset
select set_config('test.proposal_id', :'proposal_id', true);
do $$
begin
  if (select cycle_number from public.unit_proposals
      where id = current_setting('test.proposal_id')::uuid) <> 1
    or (select latest_revision from public.unit_proposals
        where id = current_setting('test.proposal_id')::uuid) <> 1 then
    raise exception 'first proposal cycle was not created correctly';
  end if;
  begin
    perform public.submit_unit_proposal(
      current_setting('test.owner_customer_id')::uuid,
      current_setting('test.unit_id')::uuid, '{"planta":1}'::jsonb);
    raise exception 'unchanged proposal was resubmitted';
  exception when sqlstate 'P0001' then
    if sqlerrm <> 'No proposal changes to submit' then raise; end if;
  end;
end $$;

-- Saving a draft after submission must NOT create a proposal version by itself.
select public.save_unit_module_choices(
  :'owner_customer_id'::uuid, :'unit_id'::uuid, 'planta',
  jsonb_build_object(:'group_id', :'option_id'), 1);
do $$
begin
  if (select latest_revision from public.unit_proposals
      where id = current_setting('test.proposal_id')::uuid) <> 1
    or (select count(*) from public.unit_proposal_versions
        where proposal_id = current_setting('test.proposal_id')::uuid) <> 1 then
    raise exception 'draft save incorrectly consumed a proposal alteration';
  end if;
end $$;

-- Architect cannot review while customer has saved but not resubmitted changes.
select set_config('request.jwt.claim.sub', :'architect_user_id', true);
do $$
begin
  begin
    perform public.review_unit_proposal(
      current_setting('test.unit_id')::uuid, 1, 'approved');
    raise exception 'architect reviewed while unsent changes existed';
  exception when sqlstate 'P0001' then
    if sqlerrm <> 'Proposal has unsent changes' then raise; end if;
  end;
end $$;

-- Cycle 1, alteration 1 => submission 2/4. Co-owner is allowed to resubmit.
select set_config('request.jwt.claim.sub', :'co_user_id', true);
select public.submit_unit_proposal(
  :'co_customer_id'::uuid, :'unit_id'::uuid, '{"planta":2}'::jsonb);

-- Alteration 2 => submission 3/4.
select public.save_unit_module_choices(
  :'co_customer_id'::uuid, :'unit_id'::uuid, 'planta',
  jsonb_build_object(:'group_id', :'option_id'), 2);
select public.submit_unit_proposal(
  :'co_customer_id'::uuid, :'unit_id'::uuid, '{"planta":3}'::jsonb);

-- Alteration 3 => submission 4/4.
select set_config('request.jwt.claim.sub', :'owner_user_id', true);
select public.save_unit_module_choices(
  :'owner_customer_id'::uuid, :'unit_id'::uuid, 'planta',
  jsonb_build_object(:'group_id', :'option_id'), 3);
select public.submit_unit_proposal(
  :'owner_customer_id'::uuid, :'unit_id'::uuid, '{"planta":4}'::jsonb);

do $$
begin
  if (select latest_revision from public.unit_proposals
      where id = current_setting('test.proposal_id')::uuid) <> 4
    or (select count(*) from public.unit_proposal_versions
        where proposal_id = current_setting('test.proposal_id')::uuid) <> 4 then
    raise exception 'proposal did not stop at four submitted versions';
  end if;
  begin
    perform public.save_unit_module_choices(
      current_setting('test.owner_customer_id')::uuid,
      current_setting('test.unit_id')::uuid, 'planta',
      jsonb_build_object(current_setting('test.group_id'), current_setting('test.option_id')),
      4);
    raise exception 'customer edited after the three-change limit';
  exception when sqlstate 'P0001' then
    if sqlerrm <> 'Proposal edit limit reached' then raise; end if;
  end;
end $$;

-- Outsider still cannot read or submit for this unit.
select set_config('request.jwt.claim.sub', :'outsider_user_id', true);
do $$
begin
  if (select count(*) from public.unit_proposals
      where id = current_setting('test.proposal_id')::uuid) <> 0 then
    raise exception 'proposal leaked through RLS';
  end if;
  begin
    perform public.submit_unit_proposal(
      current_setting('test.outsider_customer_id')::uuid,
      current_setting('test.unit_id')::uuid, '{"planta":4}'::jsonb);
    raise exception 'outsider submitted proposal';
  exception when sqlstate '42501' then null;
  end;
end $$;

-- Architect reviews only submission 4/4 and closes cycle 1.
select set_config('request.jwt.claim.sub', :'architect_user_id', true);
do $$
declare reviewed public.unit_proposal_reviews;
begin
  begin
    perform public.review_unit_proposal(
      current_setting('test.unit_id')::uuid, 3, 'approved');
    raise exception 'outdated submitted version was reviewed';
  exception when sqlstate '40001' then null;
  end;
  reviewed := public.review_unit_proposal(
    current_setting('test.unit_id')::uuid, 4, 'approved');
  if reviewed.revision <> 4 then raise exception 'review failed'; end if;
  if (select status from public.unit_proposals
      where id = current_setting('test.proposal_id')::uuid) <> 'reviewed' then
    raise exception 'review did not close proposal cycle';
  end if;
end $$;

-- After the answer, customer may edit again and submit cycle 2 with a fresh 1+3 limit.
select set_config('request.jwt.claim.sub', :'owner_user_id', true);
select public.save_unit_module_choices(
  :'owner_customer_id'::uuid, :'unit_id'::uuid, 'planta',
  jsonb_build_object(:'group_id', :'option_id'), 4);
select (public.submit_unit_proposal(
  :'owner_customer_id'::uuid, :'unit_id'::uuid,
  '{"planta":5}'::jsonb)).id as proposal2_id \gset
select set_config('test.proposal2_id', :'proposal2_id', true);
do $$
begin
  if current_setting('test.proposal2_id')::uuid = current_setting('test.proposal_id')::uuid
    or (select cycle_number from public.unit_proposals
        where id = current_setting('test.proposal2_id')::uuid) <> 2
    or (select latest_revision from public.unit_proposals
        where id = current_setting('test.proposal2_id')::uuid) <> 1
    or (select count(*) from public.unit_proposals
        where unit_id = current_setting('test.unit_id')::uuid) <> 2 then
    raise exception 'second proposal cycle was not opened correctly';
  end if;
end $$;
reset role;

-- Base-plan assignment remains protected after any submitted proposal history exists.
do $$
begin
  begin
    delete from public.unit_base_plan_assignments
      where unit_id = current_setting('test.unit_id')::uuid;
    raise exception 'submitted plan assignment was deleted';
  exception when sqlstate '42501' then null;
  end;
end $$;

rollback;
select 'PASS: proposal cycles, explicit resubmissions, 1+3 limit, latest-review guard, new cycle after review, owner/co-owner, RLS and plan guard; fixtures rolled back' as result;
