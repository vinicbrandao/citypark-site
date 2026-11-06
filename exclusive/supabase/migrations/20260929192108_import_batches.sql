-- ============================================================
-- Importação controlada
-- Armazena lotes e resultados de prévia sem alterar cadastros.
-- ============================================================

create table public.import_batches (
  id uuid primary key default gen_random_uuid(),

  source_name text not null,
  source_hash text not null,

  status text not null default 'previewed',

  total_rows integer not null default 0,
  accepted_rows integer not null default 0,
  repeated_rows integer not null default 0,
  pending_rows integer not null default 0,

  metadata jsonb not null default '{}'::jsonb,

  created_at timestamptz not null default now(),
  applied_at timestamptz,

  constraint import_batches_status_valid
    check (
      status in (
        'previewed',
        'approved',
        'applying',
        'applied',
        'failed',
        'cancelled'
      )
    ),

  constraint import_batches_counts_valid
    check (
      total_rows >= 0
      and accepted_rows >= 0
      and repeated_rows >= 0
      and pending_rows >= 0
      and accepted_rows + repeated_rows + pending_rows = total_rows
    )
);

create unique index import_batches_source_hash_unique
  on public.import_batches (source_hash);


create table public.import_rows (
  id bigint generated always as identity primary key,

  batch_id uuid not null
    references public.import_batches(id)
    on delete cascade,

  line_number integer not null,

  status text not null,
  reason text,

  customer_external_ref text,
  unit_external_ref text,
  link_external_ref text,

  raw_payload jsonb not null default '{}'::jsonb,
  normalized_payload jsonb not null default '{}'::jsonb,

  created_at timestamptz not null default now(),

  constraint import_rows_status_valid
    check (
      status in (
        'aceito',
        'repetido',
        'pendente'
      )
    ),

  constraint import_rows_line_valid
    check (line_number > 0),

  constraint import_rows_batch_line_unique
    unique (batch_id, line_number)
);


create index import_rows_batch_id_index
  on public.import_rows(batch_id);

create index import_rows_customer_external_ref_index
  on public.import_rows(customer_external_ref);

create index import_rows_unit_external_ref_index
  on public.import_rows(unit_external_ref);

create index import_rows_link_external_ref_index
  on public.import_rows(link_external_ref);


-- Estas tabelas não devem ser acessadas diretamente por clientes.
-- Os scripts administrativos usam service_role no ambiente local.

alter table public.import_batches enable row level security;
alter table public.import_rows enable row level security;