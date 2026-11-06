-- ============================================================
-- Aplicação transacional de lotes de importação.
-- Somente service_role pode aprovar/aplicar lotes.
-- ============================================================

alter table public.import_batches
  add column approved_at timestamptz;

alter table public.import_rows
  add column applied_at timestamptz,
  add column apply_result jsonb not null default '{}'::jsonb;


-- Endurece o acesso às tabelas de importação.
revoke all on public.import_batches, public.import_rows
  from anon, authenticated;

grant all on public.import_batches, public.import_rows
  to service_role;


-- ============================================================
-- Aprovação explícita do lote
-- ============================================================

create function public.approve_import_batch(p_batch_id uuid)
returns public.import_batches
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_batch public.import_batches;
begin
  select *
    into v_batch
  from public.import_batches
  where id = p_batch_id
  for update;

  if not found then
    raise exception 'Import batch not found'
      using errcode = 'P0002';
  end if;

  if v_batch.status = 'applied' then
    return v_batch;
  end if;

  if v_batch.status not in ('previewed', 'approved') then
    raise exception
      'Batch cannot be approved from status %',
      v_batch.status
      using errcode = '22023';
  end if;

  if exists (
    select 1
    from public.import_rows
    where batch_id = p_batch_id
      and status = 'pendente'
  ) then
    raise exception
      'Batch has pending rows and cannot be approved'
      using errcode = '22023';
  end if;

  update public.import_batches
  set
    status = 'approved',
    approved_at = coalesce(approved_at, now())
  where id = p_batch_id
  returning *
  into v_batch;

  return v_batch;
end;
$$;

revoke all on function public.approve_import_batch(uuid)
  from public, anon, authenticated;

grant execute on function public.approve_import_batch(uuid)
  to service_role;


-- ============================================================
-- Aplicação atômica do lote
-- ============================================================

create function public.apply_import_batch(p_batch_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_batch public.import_batches;
  v_row public.import_rows;
  v_payload jsonb;

  v_customer public.customers;
  v_unit public.units;
  v_link public.customer_units;

  v_customer_action text;
  v_unit_action text;
  v_link_action text;

  v_processed integer := 0;
  v_customers_created integer := 0;
  v_units_created integer := 0;
  v_links_created integer := 0;
begin
  select *
    into v_batch
  from public.import_batches
  where id = p_batch_id
  for update;

  if not found then
    raise exception 'Import batch not found'
      using errcode = 'P0002';
  end if;

  -- Idempotência: aplicar novamente um lote já concluído
  -- não cria qualquer registro adicional.
  if v_batch.status = 'applied' then
    return jsonb_build_object(
      'batch_id', p_batch_id,
      'status', 'applied',
      'already_applied', true
    );
  end if;

  if v_batch.status <> 'approved' then
    raise exception
      'Batch must be approved before application'
      using errcode = '22023';
  end if;

  if exists (
    select 1
    from public.import_rows
    where batch_id = p_batch_id
      and status = 'pendente'
  ) then
    raise exception
      'Batch has pending rows'
      using errcode = '22023';
  end if;

  update public.import_batches
  set status = 'applying'
  where id = p_batch_id;

  for v_row in
    select *
    from public.import_rows
    where batch_id = p_batch_id
      and status = 'aceito'
    order by line_number
    for update
  loop
    v_payload := v_row.normalized_payload;

    -- ========================================================
    -- CLIENTE
    -- ========================================================

    select *
      into v_customer
    from public.customers
    where external_ref =
      v_payload ->> 'customer_external_ref';

    if found then
      if
        btrim(v_customer.name)
          is distinct from
        btrim(v_payload ->> 'customer_name')

        or lower(btrim(v_customer.email))
          is distinct from
        lower(btrim(v_payload ->> 'customer_email'))
      then
        raise exception
          'Customer conflict on line %',
          v_row.line_number
          using errcode = '23505';
      end if;

      v_customer_action := 'reused';
    else
      insert into public.customers (
        name,
        email,
        external_ref
      )
      values (
        v_payload ->> 'customer_name',
        lower(v_payload ->> 'customer_email'),
        v_payload ->> 'customer_external_ref'
      )
      returning *
      into v_customer;

      v_customer_action := 'created';
      v_customers_created :=
        v_customers_created + 1;
    end if;


    -- ========================================================
    -- UNIDADE
    -- ========================================================

    select *
      into v_unit
    from public.units
    where external_ref =
      v_payload ->> 'unit_external_ref';

    if found then
      if
        v_unit.code
          is distinct from
        v_payload ->> 'unit_code'

        or v_unit.tower
          is distinct from
        v_payload ->> 'tower'

        or v_unit.floor_number
          is distinct from
        (v_payload ->> 'floor_number')::integer

        or v_unit.termination
          is distinct from
        v_payload ->> 'termination'

        or v_unit.typology
          is distinct from
        v_payload ->> 'typology'
      then
        raise exception
          'Unit conflict on line %',
          v_row.line_number
          using errcode = '23505';
      end if;

      v_unit_action := 'reused';
    else
      insert into public.units (
        code,
        tower,
        floor_label,
        floor_number,
        termination,
        typology,
        external_ref,
        active
      )
      values (
        v_payload ->> 'unit_code',
        v_payload ->> 'tower',

        (v_payload ->> 'floor_number')
          || 'º andar',

        (v_payload ->> 'floor_number')::integer,

        v_payload ->> 'termination',
        v_payload ->> 'typology',
        v_payload ->> 'unit_external_ref',
        true
      )
      returning *
      into v_unit;

      v_unit_action := 'created';
      v_units_created :=
        v_units_created + 1;
    end if;


    -- ========================================================
    -- VÍNCULO CLIENTE ↔ UNIDADE
    -- ========================================================

    select *
      into v_link
    from public.customer_units
    where external_ref =
      v_payload ->> 'link_external_ref';

    if found then
      if
        v_link.customer_id <> v_customer.id
        or v_link.unit_id <> v_unit.id
        or v_link.ownership_role
          is distinct from
          v_payload ->> 'ownership_role'
        or v_link.purchase_date
          is distinct from
          (v_payload ->> 'purchase_date')::date
      then
        raise exception
          'Ownership conflict on line %',
          v_row.line_number
          using errcode = '23505';
      end if;

      v_link_action := 'reused';

    else
      -- Pode existir vínculo antigo pelo par
      -- cliente/unidade ainda sem external_ref.

      select *
        into v_link
      from public.customer_units
      where customer_id = v_customer.id
        and unit_id = v_unit.id;

      if found then
        if
          v_link.external_ref is not null
          and v_link.external_ref <>
            v_payload ->> 'link_external_ref'
        then
          raise exception
            'Ownership external_ref conflict on line %',
            v_row.line_number
            using errcode = '23505';
        end if;

        if
          v_link.ownership_role
            is distinct from
            v_payload ->> 'ownership_role'
          or v_link.purchase_date
            is distinct from
            (v_payload ->> 'purchase_date')::date
        then
          raise exception
            'Ownership data conflict on line %',
            v_row.line_number
            using errcode = '23505';
        end if;

        if v_link.external_ref is null then
          update public.customer_units
          set external_ref =
            v_payload ->> 'link_external_ref'
          where customer_id = v_customer.id
            and unit_id = v_unit.id
          returning *
          into v_link;
        end if;

        v_link_action := 'reused';

      else
        insert into public.customer_units (
          customer_id,
          unit_id,
          ownership_role,
          purchase_date,
          external_ref,
          active
        )
        values (
          v_customer.id,
          v_unit.id,
          v_payload ->> 'ownership_role',
          (v_payload ->> 'purchase_date')::date,
          v_payload ->> 'link_external_ref',
          true
        )
        returning *
        into v_link;

        v_link_action := 'created';
        v_links_created :=
          v_links_created + 1;
      end if;
    end if;


    -- ========================================================
    -- AUDITORIA DA LINHA
    -- ========================================================

    update public.import_rows
    set
      applied_at = now(),

      apply_result = jsonb_build_object(
        'customer_id', v_customer.id,
        'customer_action', v_customer_action,

        'unit_id', v_unit.id,
        'unit_action', v_unit_action,

        'link_external_ref',
          v_payload ->> 'link_external_ref',

        'link_action', v_link_action
      )

    where id = v_row.id;

    v_processed := v_processed + 1;
  end loop;


  update public.import_batches
  set
    status = 'applied',
    applied_at = now()
  where id = p_batch_id;


  return jsonb_build_object(
    'batch_id', p_batch_id,
    'status', 'applied',
    'already_applied', false,
    'processed_rows', v_processed,
    'customers_created', v_customers_created,
    'units_created', v_units_created,
    'links_created', v_links_created
  );
end;
$$;

revoke all on function public.apply_import_batch(uuid)
  from public, anon, authenticated;

grant execute on function public.apply_import_batch(uuid)
  to service_role;