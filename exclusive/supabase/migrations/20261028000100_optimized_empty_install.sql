-- Optional cleanup ONLY for the approved, empty official installation.
-- Ordinary upgrades (including the populated local database) preserve history.
-- The initial deployment sets this transaction-local flag after an empty-DB guard.
do $optimized_install$
declare
  legacy_tables text[] := array[
    'architect_assistance_events','architect_assistance_requests',
    'architect_authorization_events','architect_authorizations','configuration_reviews',
    'customer_customizations','customization_history','customization_windows',
    'draft_history','option_compatibilities','plan_features','plans',
    'staff_unit_assignments','unit_configuration_state','unit_drafts',
    'unit_module_history','unit_module_selections','unit_module_states','unit_plans',
    'unit_proposal_reviews','unit_proposal_versions','unit_proposals'
  ];
  legacy_functions text[] := array[
    'accept_architect_assistance','cancel_architect_assistance','clear_completed_ui_draft',
    'current_architect_authorization','guard_legacy_architect_draft',
    'guard_open_proposal_edit_limit','guard_submitted_base_plan_assignment',
    'guard_unit_customization_deadline','list_unit_architects','record_customization_actor',
    'record_draft_history','request_architect_assistance','resolve_architect_assistance',
    'review_unit_configuration','review_unit_proposal','save_partial_unit_configuration',
    'save_staff_unit_configuration','save_unit_configuration','save_unit_draft',
    'save_unit_module_choices','set_architect_authorization','submit_unit_proposal',
    'unit_module_choice_snapshot','unit_module_revision_snapshot'
  ];
  table_name text;
  has_records boolean;
  item record;
begin
  if current_setting('citypark.optimized_initial_install', true) is distinct from 'on' then
    return;
  end if;
  if exists(select 1 from auth.users) then
    raise exception 'Optimized initial install refuses existing Auth accounts';
  end if;
  -- Guard every table, including legacy audit records, before any removal.
  for table_name in select tablename from pg_tables
    where schemaname='public' and tablename <> 'customization_modules'
  loop
    execute format('select exists(select 1 from public.%I)',table_name) into has_records;
    if has_records then
      raise exception 'Optimized initial install refuses data in public.%',table_name;
    end if;
  end loop;

  -- The current module catalog has its own unit-scoped policies. Remove only
  -- the transitional policies that still reference prototype combinations.
  drop policy readable_options on public.customization_options;
  drop policy readable_groups on public.customization_groups;

  for item in select c.relname as table_name,t.tgname
    from pg_trigger t join pg_class c on c.oid=t.tgrelid
    join pg_namespace n on n.oid=c.relnamespace join pg_proc p on p.oid=t.tgfoid
    where n.nspname='public' and not t.tgisinternal
      and (c.relname=any(legacy_tables) or p.proname=any(legacy_functions))
  loop
    execute format('drop trigger %I on public.%I',item.tgname,item.table_name);
  end loop;
  for item in select tablename,policyname from pg_policies
    where schemaname='public' and tablename=any(legacy_tables)
  loop
    execute format('drop policy %I on public.%I',item.policyname,item.tablename);
  end loop;
  for item in select p.proname,pg_get_function_identity_arguments(p.oid) as arguments
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname=any(legacy_functions)
  loop
    -- RESTRICT is intentional: an unexpected dependency must stop installation.
    execute format('drop function public.%I(%s) restrict',item.proname,item.arguments);
  end loop;
  execute 'drop table ' || (
    select string_agg(format('public.%I',name),',') from unnest(legacy_tables) name
  ) || ' restrict';

  -- Match the actual history query: WHERE unit_id = ? ORDER BY id DESC LIMIT 100.
  drop index public.unit_activity_events_unit_time;
  create index unit_activity_events_unit_id_id_idx on public.unit_activity_events(unit_id,id desc);
end;
$optimized_install$;
