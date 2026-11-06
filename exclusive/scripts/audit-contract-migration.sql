-- Inventário somente de leitura para planejar a migração ao fluxo de contratos.
-- Executar em uma conexão autorizada ao banco alvo. Retorna apenas contagens;
-- não expõe nomes, e-mails, identificadores de clientes ou escolhas.
-- Revisar a versão do schema antes de aplicar qualquer migration.

begin transaction read only;

select 'units.total' as metric, count(*)::bigint as value from public.units
union all
select 'units.active', count(*)::bigint from public.units where active
union all
select 'units.inactive', count(*)::bigint from public.units where not active;

select 'schema.units.area_m2' as metric, count(*)::bigint as value
from information_schema.columns
where table_schema = 'public' and table_name = 'units' and column_name = 'area_m2'
union all
select 'schema.units.customization_closes_at', count(*)::bigint
from information_schema.columns
where table_schema = 'public' and table_name = 'units'
  and column_name = 'customization_closes_at';

with link_counts as (
  select unit_id,
    count(*) filter (where active) as active_links,
    count(*) filter (where active and ownership_role = 'co_owner') as active_coowners
  from public.customer_units
  group by unit_id
)
select 'units.without_active_customer' as metric, count(*)::bigint as value
from public.units u left join link_counts l on l.unit_id = u.id
where coalesce(l.active_links, 0) = 0
union all
select 'units.with_one_active_customer', count(*)::bigint
from public.units u join link_counts l on l.unit_id = u.id
where l.active_links = 1
union all
select 'units.with_multiple_active_customers', count(*)::bigint
from public.units u join link_counts l on l.unit_id = u.id
where l.active_links > 1
union all
select 'units.with_active_coowner', count(*)::bigint
from public.units u join link_counts l on l.unit_id = u.id
where l.active_coowners > 0;

select 'legacy.unit_drafts' as metric, count(*)::bigint as value
from public.unit_drafts
union all
select 'legacy.draft_history', count(*)::bigint from public.draft_history
union all
select 'current.module_states', count(*)::bigint from public.unit_module_states
union all
select 'current.module_selections', count(*)::bigint from public.unit_module_selections
union all
select 'current.module_history', count(*)::bigint from public.unit_module_history
union all
select 'current.proposals', count(*)::bigint from public.unit_proposals
union all
select 'current.proposal_versions', count(*)::bigint from public.unit_proposal_versions
union all
select 'current.proposal_reviews', count(*)::bigint from public.unit_proposal_reviews;

select 'proposals.open' as metric, count(*)::bigint as value
from public.unit_proposals where status = 'open'
union all
select 'proposals.reviewed', count(*)::bigint
from public.unit_proposals where status = 'reviewed';

select 'catalog.base_plans' as metric, count(*)::bigint as value
from public.base_plans
union all
select 'catalog.unit_base_plan_assignments', count(*)::bigint
from public.unit_base_plan_assignments
union all
select 'catalog.module_windows', count(*)::bigint
from public.unit_module_windows
union all
select 'catalog.option_exclusions', count(*)::bigint
from public.base_plan_option_exclusions;

commit;
