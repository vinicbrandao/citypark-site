-- Estrutura inicial do modelo definitivo. Os dados e RPCs do protótipo
-- permanecem disponíveis até a migração explícita da configuração atual.

alter table public.units
  add column tower_code text,
  add column termination_code text,
  add constraint units_tower_code_valid
    check (tower_code is null or tower_code in ('A', 'B')),
  add constraint units_termination_code_valid
    check (termination_code is null or termination_code ~ '^[0-9]{2}$');

-- Apenas dados de teste cujo código e andar já concordam são preenchidos.
-- tower/termination legados não são alterados; podem ter formato diferente.
with parsed as (
  select id, regexp_match(code, '^([0-9]+)([0-9]{2})([AB])$') as parts
  from public.units
)
update public.units u
set tower_code = p.parts[3],
    termination_code = p.parts[2]
from parsed p
where u.id = p.id
  and p.parts is not null
  and u.floor_number = (p.parts[1])::integer;

create unique index units_location_unique
  on public.units(tower_code, floor_number, termination_code)
  where tower_code is not null
    and floor_number is not null
    and termination_code is not null;

-- "plans" guarda combinações do protótipo. Base plans é uma entidade
-- distinta para não reclassificar registros históricos como plantas reais.
create table public.base_plans (
  id uuid primary key default gen_random_uuid(),
  code text not null unique check (length(btrim(code)) > 0),
  name text not null check (length(btrim(name)) > 0),
  description text,
  status text not null default 'active'
    check (status in ('active', 'archived')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Uma atribuição atual por unidade; nenhuma linha significa "em preparação".
-- Somente a equipe, por processo administrativo com service_role, pode gravar.
create table public.unit_base_plan_assignments (
  unit_id uuid primary key references public.units(id),
  base_plan_id uuid not null references public.base_plans(id),
  assigned_by uuid references auth.users(id),
  assigned_at timestamptz not null default now()
);
create index unit_base_plan_assignments_plan_idx
  on public.unit_base_plan_assignments(base_plan_id);

create table public.customization_modules (
  code text primary key check (length(btrim(code)) > 0),
  name text not null check (length(btrim(name)) > 0),
  active boolean not null default true,
  sort_order integer not null default 0
);
insert into public.customization_modules(code, name, sort_order)
values ('planta', 'Planta', 0);

alter table public.customization_groups
  add column module_code text references public.customization_modules(code);
create index customization_groups_module_idx
  on public.customization_groups(module_code);

-- O prazo pertence ao par unidade/módulo. Ausência de janela para Planta
-- deverá bloquear a edição no RPC definitivo, sem afetar outros módulos.
create table public.unit_module_windows (
  unit_id uuid not null references public.units(id),
  module_code text not null references public.customization_modules(code),
  opens_at timestamptz not null,
  closes_at timestamptz not null,
  status text not null default 'active'
    check (status in ('active', 'suspended')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (unit_id, module_code),
  check (opens_at < closes_at)
);
create index unit_module_windows_module_idx
  on public.unit_module_windows(module_code, closes_at);

alter table public.base_plans enable row level security;
alter table public.unit_base_plan_assignments enable row level security;
alter table public.customization_modules enable row level security;
alter table public.unit_module_windows enable row level security;

revoke all on public.base_plans, public.unit_base_plan_assignments,
  public.customization_modules, public.unit_module_windows
  from public, anon, authenticated;
grant select on public.base_plans, public.unit_base_plan_assignments,
  public.customization_modules, public.unit_module_windows
  to authenticated;
grant all on public.base_plans, public.unit_base_plan_assignments,
  public.customization_modules, public.unit_module_windows
  to service_role;

create policy readable_base_plan_assignments
  on public.unit_base_plan_assignments for select to authenticated
  using (exists (
    select 1 from public.units u
    where u.id = unit_base_plan_assignments.unit_id
  ));

create policy readable_base_plans
  on public.base_plans for select to authenticated
  using (exists (
    select 1 from public.unit_base_plan_assignments a
    where a.base_plan_id = base_plans.id
  ));

create policy readable_modules
  on public.customization_modules for select to authenticated
  using (active and exists (
    select 1 from public.unit_module_windows w
    where w.module_code = customization_modules.code
  ));

create policy readable_unit_module_windows
  on public.unit_module_windows for select to authenticated
  using (exists (
    select 1 from public.units u
    where u.id = unit_module_windows.unit_id
  ));


