


SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;


CREATE SCHEMA IF NOT EXISTS "public";


ALTER SCHEMA "public" OWNER TO "pg_database_owner";


COMMENT ON SCHEMA "public" IS 'standard public schema';


SET default_tablespace = '';

SET default_table_access_method = "heap";


CREATE TABLE IF NOT EXISTS "public"."architect_assistance_requests" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "unit_id" "uuid" NOT NULL,
    "architect_user_id" "uuid" NOT NULL,
    "requester_customer_id" "uuid" NOT NULL,
    "requester_user_id" "uuid" NOT NULL,
    "message" "text",
    "status" "text" DEFAULT 'requested'::"text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "closed_at" timestamp with time zone,
    CONSTRAINT "architect_assistance_requests_check" CHECK (((("status" = ANY (ARRAY['requested'::"text", 'in_progress'::"text"])) AND ("closed_at" IS NULL)) OR (("status" = ANY (ARRAY['resolved'::"text", 'canceled'::"text"])) AND ("closed_at" IS NOT NULL)))),
    CONSTRAINT "architect_assistance_requests_message_check" CHECK ((("message" IS NULL) OR ("length"("message") <= 2000))),
    CONSTRAINT "architect_assistance_requests_status_check" CHECK (("status" = ANY (ARRAY['requested'::"text", 'in_progress'::"text", 'resolved'::"text", 'canceled'::"text"])))
);


ALTER TABLE "public"."architect_assistance_requests" OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."accept_architect_assistance"("p_request_id" "uuid") RETURNS "public"."architect_assistance_requests"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
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


ALTER FUNCTION "public"."accept_architect_assistance"("p_request_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."apply_import_batch"("p_batch_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
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


ALTER FUNCTION "public"."apply_import_batch"("p_batch_id" "uuid") OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."import_batches" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "source_name" "text" NOT NULL,
    "source_hash" "text" NOT NULL,
    "status" "text" DEFAULT 'previewed'::"text" NOT NULL,
    "total_rows" integer DEFAULT 0 NOT NULL,
    "accepted_rows" integer DEFAULT 0 NOT NULL,
    "repeated_rows" integer DEFAULT 0 NOT NULL,
    "pending_rows" integer DEFAULT 0 NOT NULL,
    "metadata" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "applied_at" timestamp with time zone,
    "approved_at" timestamp with time zone,
    CONSTRAINT "import_batches_counts_valid" CHECK ((("total_rows" >= 0) AND ("accepted_rows" >= 0) AND ("repeated_rows" >= 0) AND ("pending_rows" >= 0) AND ((("accepted_rows" + "repeated_rows") + "pending_rows") = "total_rows"))),
    CONSTRAINT "import_batches_status_valid" CHECK (("status" = ANY (ARRAY['previewed'::"text", 'approved'::"text", 'applying'::"text", 'applied'::"text", 'failed'::"text", 'cancelled'::"text"])))
);


ALTER TABLE "public"."import_batches" OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."approve_import_batch"("p_batch_id" "uuid") RETURNS "public"."import_batches"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
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


ALTER FUNCTION "public"."approve_import_batch"("p_batch_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."cancel_architect_assistance"("p_request_id" "uuid") RETURNS "public"."architect_assistance_requests"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
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


ALTER FUNCTION "public"."cancel_architect_assistance"("p_request_id" "uuid") OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."deadline_notifications" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "unit_id" "uuid" NOT NULL,
    "customer_id" "uuid" NOT NULL,
    "scope" "text" NOT NULL,
    "deadline" timestamp with time zone NOT NULL,
    "due_date" "date" NOT NULL,
    "days_before" integer NOT NULL,
    "recipient" "text" NOT NULL,
    "unit_code" "text" NOT NULL,
    "module_name" "text",
    "status" "text" DEFAULT 'pending'::"text" NOT NULL,
    "attempts" integer DEFAULT 0 NOT NULL,
    "lease_until" timestamp with time zone,
    "last_error" "text",
    "sent_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "clock_timestamp"() NOT NULL,
    CONSTRAINT "deadline_notifications_days_before_check" CHECK (("days_before" = ANY (ARRAY[15, 10, 5, 1]))),
    CONSTRAINT "deadline_notifications_status_check" CHECK (("status" = ANY (ARRAY['pending'::"text", 'sending'::"text", 'sent'::"text", 'failed'::"text"])))
);


ALTER TABLE "public"."deadline_notifications" OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."claim_deadline_notifications"("p_limit" integer DEFAULT 50) RETURNS SETOF "public"."deadline_notifications"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare v_today date := (clock_timestamp() at time zone 'America/Sao_Paulo')::date;
begin
  if p_limit not between 1 and 100 then raise exception 'Invalid batch size'; end if;
  insert into public.deadline_notifications(unit_id,customer_id,scope,deadline,due_date,days_before,recipient,unit_code,module_name)
  select u.id,cu.customer_id,d.scope,d.deadline,v_today,
    (d.deadline at time zone 'America/Sao_Paulo')::date-v_today,au.email,u.code,d.module_name
  from public.units u
  join public.customer_units cu on cu.unit_id=u.id and cu.active and cu.ownership_role='owner'
  join public.customer_users usr on usr.customer_id=cu.customer_id and usr.active
  join auth.users au on au.id=usr.user_id and au.email is not null
  cross join lateral (
    select 'unit'::text as scope,u.customization_closes_at as deadline,null::text as module_name
    union all
    select 'module:'||w.module_code,w.closes_at,m.name from public.unit_module_windows w
      join public.customization_modules m on m.code=w.module_code and m.active
      where w.unit_id=u.id and w.status='active'
  ) d
  where u.active and u.customization_status='pending' and d.deadline is not null
    and (d.deadline at time zone 'America/Sao_Paulo')::date-v_today in (15,10,5,1)
  on conflict(unit_id,customer_id,scope,deadline,days_before) do nothing;

  return query with batch as (
    select n.id from public.deadline_notifications n
    join public.units u on u.id=n.unit_id and u.active and u.customization_status='pending'
    join public.customer_units cu on cu.unit_id=u.id and cu.customer_id=n.customer_id and cu.active
    where n.due_date=v_today and n.attempts<5 and n.status<>'sent'
      and (n.lease_until is null or n.lease_until<clock_timestamp())
      and ((n.scope='unit' and u.customization_closes_at=n.deadline) or exists(
        select 1 from public.unit_module_windows w where w.unit_id=n.unit_id
          and n.scope='module:'||w.module_code and w.status='active' and w.closes_at=n.deadline))
    order by n.created_at for update of n skip locked limit p_limit
  ) update public.deadline_notifications n set status='sending',attempts=n.attempts+1,
      lease_until=clock_timestamp()+interval '10 minutes'
    from batch where n.id=batch.id returning n.*;
end; $$;


ALTER FUNCTION "public"."claim_deadline_notifications"("p_limit" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."clear_completed_ui_draft"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
begin
  if new.plan_id is not null then
    new.draft_selections = '{}'::jsonb;
  end if;
  return new;
end;
$$;


ALTER FUNCTION "public"."clear_completed_ui_draft"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."current_actor_name"() RETURNS "text"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
  select coalesce(
    (select name from public.staff_users where user_id = (select auth.uid()) and active),
    (select c.name from public.customers c join public.customer_users u on u.customer_id = c.id
      where u.user_id = (select auth.uid()) and u.active limit 1), 'Usuário');
$$;


ALTER FUNCTION "public"."current_actor_name"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."current_architect_authorization"("p_unit_id" "uuid", "p_architect_user_id" "uuid") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
  select exists (
    select 1 from public.architect_authorizations consent
    join public.customer_units cu
      on cu.customer_id = consent.granted_by_customer_id
     and cu.unit_id = consent.unit_id and cu.active
    join public.customer_users usr
      on usr.customer_id = cu.customer_id
     and usr.user_id = consent.granted_by_user_id and usr.active
    where consent.unit_id = p_unit_id
      and consent.architect_user_id = p_architect_user_id and consent.active
  );
$$;


ALTER FUNCTION "public"."current_architect_authorization"("p_unit_id" "uuid", "p_architect_user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."current_staff_role"() RETURNS "text"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
  select role from public.staff_users where user_id = auth.uid() and active;
$$;


ALTER FUNCTION "public"."current_staff_role"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."customer_can_access_unit"("p_unit_id" "uuid") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
  select exists (
    select 1 from public.units u
    join public.customer_units cu on cu.unit_id = u.id and cu.active and cu.ownership_role = 'owner'
    join public.customer_users usr on usr.customer_id = cu.customer_id and usr.active
    where u.id = p_unit_id and u.active and usr.user_id = (select auth.uid())
  );
$$;


ALTER FUNCTION "public"."customer_can_access_unit"("p_unit_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."find_customer_auth_user"("p_email" "text") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
begin
  if public.current_staff_role() is distinct from 'admin' then
    raise exception 'Admin required' using errcode = '42501'; end if;
  return (select id from auth.users where lower(email) = lower(btrim(p_email)) limit 1);
end; $$;


ALTER FUNCTION "public"."find_customer_auth_user"("p_email" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."finish_deadline_notification"("p_id" "uuid", "p_success" boolean, "p_error" "text" DEFAULT NULL::"text") RETURNS "void"
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
  update public.deadline_notifications set status=case when p_success then 'sent' else 'failed' end,
    sent_at=case when p_success then clock_timestamp() else null end,
    last_error=case when p_success then null else left(p_error,1000) end,
    lease_until=case when p_success then null else clock_timestamp()+interval '10 minutes' end
  where id=p_id and status='sending';
$$;


ALTER FUNCTION "public"."finish_deadline_notification"("p_id" "uuid", "p_success" boolean, "p_error" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."guard_legacy_architect_draft"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
begin
  if (select public.current_staff_role()) = 'architect'
    and not public.staff_can_access_unit(new.unit_id) then
    raise exception 'Unit access denied' using errcode = '42501';
  end if;
  return new;
end;
$$;


ALTER FUNCTION "public"."guard_legacy_architect_draft"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."guard_open_proposal_edit_limit"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
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


ALTER FUNCTION "public"."guard_open_proposal_edit_limit"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."guard_submitted_base_plan_assignment"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
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


ALTER FUNCTION "public"."guard_submitted_base_plan_assignment"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."guard_unit_customization_deadline"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_unit_id uuid;
  v_closes_at timestamptz;
begin
  if tg_table_name = 'unit_module_history' then
    v_unit_id := new.unit_id;
  else
    select p.unit_id into v_unit_id from public.unit_proposals p
      where p.id = new.proposal_id;
  end if;
  select u.customization_closes_at into v_closes_at
    from public.units u where u.id = v_unit_id;
  if v_closes_at is not null and clock_timestamp() >= v_closes_at then
    raise exception 'Unit customization deadline reached' using errcode = '42501';
  end if;
  return new;
end;
$$;


ALTER FUNCTION "public"."guard_unit_customization_deadline"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."list_customer_unit_cards"() RETURNS TABLE("id" "uuid", "code" "text", "tower" "text", "tower_code" "text", "floor_label" "text", "termination" "text", "typology" "text", "area_m2" numeric, "customization_closes_at" timestamp with time zone, "active" boolean, "customization_status" "text")
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
  select u.id,u.code,u.tower,u.tower_code,u.floor_label,u.termination,u.typology,
    u.area_m2,u.customization_closes_at,u.active,u.customization_status
  from public.units u
  where exists (
    select 1 from public.customer_units cu
    join public.customer_users usr on usr.customer_id=cu.customer_id and usr.active
    where cu.unit_id=u.id and cu.active and cu.ownership_role='owner'
      and usr.user_id=(select auth.uid())
  )
  order by u.code;
$$;


ALTER FUNCTION "public"."list_customer_unit_cards"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."list_unit_architects"("p_unit_id" "uuid") RETURNS TABLE("user_id" "uuid", "name" "text", "authorized" boolean)
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
begin
  if not exists (
    select 1 from public.customer_units cu
    join public.customer_users usr on usr.customer_id = cu.customer_id and usr.active
    join public.units u on u.id = cu.unit_id and u.active
    where cu.unit_id = p_unit_id and cu.active
      and cu.ownership_role in ('owner', 'co_owner')
      and usr.user_id = (select auth.uid())
  ) then
    raise exception 'Unit access denied' using errcode = '42501';
  end if;
  return query
    select s.user_id, s.name,
      public.current_architect_authorization(a.unit_id, a.user_id)
    from public.staff_unit_assignments a
    join public.staff_users s on s.user_id = a.user_id
      and s.role = 'architect' and s.active
    where a.unit_id = p_unit_id and a.active
    order by s.name, s.user_id;
end;
$$;


ALTER FUNCTION "public"."list_unit_architects"("p_unit_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."manage_unit"("p_unit_id" "uuid", "p_customer_id" "uuid", "p_closes_at" timestamp with time zone, "p_module_deadlines" "jsonb") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare v_module text; v_date text;
begin
  if public.current_staff_role() is distinct from 'admin'
    then raise exception 'Admin required' using errcode = '42501'; end if;
  if jsonb_typeof(p_module_deadlines) is distinct from 'object'
    then raise exception 'Invalid module deadlines' using errcode = '22023'; end if;
  perform public.set_unit_customer(p_unit_id, p_customer_id);
  perform public.set_unit_deadline(p_unit_id, p_closes_at);
  for v_module, v_date in select key, value from jsonb_each_text(p_module_deadlines) loop
    perform public.set_module_deadline(p_unit_id, v_module, v_date::timestamptz);
  end loop;
end; $$;


ALTER FUNCTION "public"."manage_unit"("p_unit_id" "uuid", "p_customer_id" "uuid", "p_closes_at" timestamp with time zone, "p_module_deadlines" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."record_customization_actor"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
begin
  if new.updated_by is null then new.updated_by = (select auth.uid()); end if;
  return new;
end;
$$;


ALTER FUNCTION "public"."record_customization_actor"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."record_draft_history"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
begin
 insert into public.draft_history(unit_id,revision,selections,actor_id,actor_role)
 values(new.unit_id,new.revision,new.selections,new.updated_by,coalesce(public.current_staff_role(),'customer'));
 return new;
end; $$;


ALTER FUNCTION "public"."record_draft_history"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."record_unit_access"("p_unit_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare v_first boolean;
begin
  -- Serialize access against activation/link changes and concurrent first opens.
  perform 1 from public.units where id=p_unit_id for update;
  if not found or (select auth.uid()) is null or not (
    coalesce(public.staff_can_access_unit(p_unit_id),false) or public.customer_can_access_unit(p_unit_id)
  ) then raise exception 'Unit access denied' using errcode='42501'; end if;
  v_first := not exists(select 1 from public.unit_activity_events
    where unit_id=p_unit_id and actor_user_id=(select auth.uid())
      and action in ('unit_opened','unit_first_opened'));
  insert into public.unit_activity_events(unit_id,actor_user_id,actor_role,action)
  values(p_unit_id,(select auth.uid()),coalesce(public.current_staff_role(),'customer'),
    case when v_first then 'unit_first_opened' else 'unit_opened' end);
end; $$;


ALTER FUNCTION "public"."record_unit_access"("p_unit_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."register_customer_account"("p_name" "text", "p_email" "text") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $_$
declare v_user uuid; v_customer uuid; v_email text := lower(btrim(p_email)); v_name text := btrim(p_name);
begin
  if public.current_staff_role() is distinct from 'admin' then
    raise exception 'Admin required' using errcode = '42501'; end if;
  if v_name is null or length(v_name) not between 1 and 200 or v_email is null
    or length(v_email) > 254 or v_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then
    raise exception 'Invalid customer profile' using errcode = '22023'; end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_email, 0));
  v_user := public.find_customer_auth_user(v_email);
  if v_user is null then raise exception 'Auth account not provisioned' using errcode = '22023'; end if;
  if exists(select 1 from public.staff_users where user_id = v_user) then
    raise exception 'Staff account cannot be a customer account' using errcode = '22023'; end if;
  select customer_id into v_customer from public.customer_users where user_id = v_user and active;
  if v_customer is null then
    insert into public.customers(name,email) values(v_name,v_email) returning id into v_customer;
    insert into public.customer_users(customer_id,user_id,active) values(v_customer,v_user,true);
  else
    update public.customers set name = v_name, email = v_email where id = v_customer;
  end if;
  insert into public.unit_activity_events(actor_user_id,actor_role,action,details)
  values((select auth.uid()),'admin','customer_registered',jsonb_build_object('customer_id',v_customer));
  return v_customer;
end; $_$;


ALTER FUNCTION "public"."register_customer_account"("p_name" "text", "p_email" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."request_architect_assistance"("p_customer_id" "uuid", "p_unit_id" "uuid", "p_architect_user_id" "uuid", "p_message" "text" DEFAULT NULL::"text") RETURNS "public"."architect_assistance_requests"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
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


ALTER FUNCTION "public"."request_architect_assistance"("p_customer_id" "uuid", "p_unit_id" "uuid", "p_architect_user_id" "uuid", "p_message" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."resolve_architect_assistance"("p_request_id" "uuid", "p_note" "text" DEFAULT NULL::"text") RETURNS "public"."architect_assistance_requests"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
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


ALTER FUNCTION "public"."resolve_architect_assistance"("p_request_id" "uuid", "p_note" "text") OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."configuration_reviews" (
    "unit_id" "uuid" NOT NULL,
    "revision" integer NOT NULL,
    "decision" "text" NOT NULL,
    "note" "text",
    "reviewer_user_id" "uuid" NOT NULL,
    "reviewed_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "configuration_reviews_check" CHECK ((("decision" <> 'changes_requested'::"text") OR (("note" IS NOT NULL) AND ("length"("btrim"("note")) > 0)))),
    CONSTRAINT "configuration_reviews_decision_check" CHECK (("decision" = ANY (ARRAY['approved'::"text", 'changes_requested'::"text"]))),
    CONSTRAINT "configuration_reviews_note_check" CHECK ((("note" IS NULL) OR ("length"("note") <= 2000))),
    CONSTRAINT "configuration_reviews_revision_check" CHECK (("revision" > 0))
);


ALTER TABLE "public"."configuration_reviews" OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."review_unit_configuration"("p_unit_id" "uuid", "p_expected_revision" integer, "p_decision" "text", "p_note" "text" DEFAULT NULL::"text") RETURNS "public"."configuration_reviews"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_state public.unit_configuration_state;
  v_review public.configuration_reviews;
  v_note text;
begin
  if (select public.current_staff_role()) is distinct from 'architect'
    or not public.staff_can_access_unit(p_unit_id) then
    raise exception 'Technical review denied' using errcode = '42501';
  end if;
  v_note := nullif(btrim(p_note), '');
  if p_expected_revision is null or p_expected_revision <= 0
    or p_decision not in ('approved', 'changes_requested') or p_decision is null
    or length(v_note) > 2000
    or (p_decision = 'changes_requested' and v_note is null) then
    raise exception 'Invalid review' using errcode = '22023';
  end if;
  select * into v_state from public.unit_configuration_state
    where unit_id = p_unit_id for update;
  if v_state.unit_id is null or v_state.revision <> p_expected_revision then
    raise exception 'Configuration changed in another session' using errcode = '40001';
  end if;
  if v_state.status <> 'draft' or v_state.plan_id is null
    or not exists (
      select 1 from public.customization_history h
      where h.unit_id = p_unit_id and h.revision = p_expected_revision
        and h.selection_format = 'catalog_ids'
    ) then
    raise exception 'Complete saved configuration required' using errcode = '22023';
  end if;
  if exists (select 1 from public.configuration_reviews
             where unit_id = p_unit_id and revision = p_expected_revision) then
    raise exception 'Revision already reviewed' using errcode = '23505';
  end if;
  insert into public.configuration_reviews
    (unit_id, revision, decision, note, reviewer_user_id)
  values (p_unit_id, p_expected_revision, p_decision, v_note, (select auth.uid()))
  returning * into v_review;
  return v_review;
end;
$$;


ALTER FUNCTION "public"."review_unit_configuration"("p_unit_id" "uuid", "p_expected_revision" integer, "p_decision" "text", "p_note" "text") OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."unit_proposal_reviews" (
    "proposal_id" "uuid" NOT NULL,
    "revision" integer NOT NULL,
    "decision" "text" NOT NULL,
    "note" "text",
    "reviewer_user_id" "uuid" NOT NULL,
    "reviewed_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "unit_proposal_reviews_check" CHECK ((("decision" <> 'changes_requested'::"text") OR (("note" IS NOT NULL) AND ("length"("btrim"("note")) > 0)))),
    CONSTRAINT "unit_proposal_reviews_decision_check" CHECK (("decision" = ANY (ARRAY['approved'::"text", 'changes_requested'::"text"]))),
    CONSTRAINT "unit_proposal_reviews_note_check" CHECK ((("note" IS NULL) OR ("length"("note") <= 2000)))
);


ALTER TABLE "public"."unit_proposal_reviews" OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."review_unit_proposal"("p_unit_id" "uuid", "p_expected_revision" integer, "p_decision" "text", "p_note" "text" DEFAULT NULL::"text") RETURNS "public"."unit_proposal_reviews"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
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


ALTER FUNCTION "public"."review_unit_proposal"("p_unit_id" "uuid", "p_expected_revision" integer, "p_decision" "text", "p_note" "text") OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."unit_configuration_state" (
    "unit_id" "uuid" NOT NULL,
    "plan_id" "uuid",
    "status" "text" DEFAULT 'draft'::"text" NOT NULL,
    "revision" integer DEFAULT 0 NOT NULL,
    "updated_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "draft_selections" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    CONSTRAINT "unit_configuration_state_draft_selections_check" CHECK (("jsonb_typeof"("draft_selections") = 'object'::"text")),
    CONSTRAINT "unit_configuration_state_plan_revision_check" CHECK ((("revision" > 0) OR ("plan_id" IS NULL))),
    CONSTRAINT "unit_configuration_state_revision_check" CHECK (("revision" >= 0)),
    CONSTRAINT "unit_configuration_state_status_check" CHECK (("status" = ANY (ARRAY['draft'::"text", 'submitted'::"text", 'locked'::"text"])))
);


ALTER TABLE "public"."unit_configuration_state" OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."save_partial_unit_configuration"("p_customer_id" "uuid", "p_unit_id" "uuid", "p_selections" "jsonb", "p_expected_revision" integer) RETURNS "public"."unit_configuration_state"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_state public.unit_configuration_state;
  v_role text;
  v_key text;
  v_value jsonb;
begin
  if (select auth.uid()) is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  select cu.ownership_role into v_role
  from public.customer_units cu
  join public.customer_users usr on usr.customer_id = cu.customer_id and usr.active
  join public.units u on u.id = cu.unit_id and u.active
  where cu.customer_id = p_customer_id and cu.unit_id = p_unit_id
    and cu.active and usr.user_id = (select auth.uid());
  if v_role is null or v_role not in ('owner', 'co_owner') then
    raise exception 'Unit access denied' using errcode = '42501';
  end if;
  if p_expected_revision is null or p_expected_revision < 0
    or jsonb_typeof(p_selections) is distinct from 'object' then
    raise exception 'Invalid partial configuration' using errcode = '22023';
  end if;
  if not (p_selections ?& array['socialPlant','suitePlant','counter','stone','rodamao','service'])
    or (select count(*) from jsonb_object_keys(p_selections)) <> 6
    or (p_selections->'socialPlant' <> 'null'::jsonb
      and p_selections->'suitePlant' <> 'null'::jsonb) then
    raise exception 'Expected six selections with an incomplete plant' using errcode = '22023';
  end if;
  for v_key, v_value in select key, value from jsonb_each(p_selections) loop
    if v_key in ('socialPlant', 'suitePlant') then
      if jsonb_typeof(v_value) not in ('null', 'string') then
        raise exception 'Invalid plant choice' using errcode = '22023';
      end if;
    elsif jsonb_typeof(v_value) <> 'string' then
      raise exception 'Invalid material choice' using errcode = '22023';
    end if;
  end loop;

  -- Todos os materiais devem caber em pelo menos uma planta disponível que
  -- respeite as partes da planta já escolhidas.
  if not exists (
    select 1 from public.unit_plans up
    join public.plans p on p.id = up.plan_id and p.status = 'active'
    where up.unit_id = p_unit_id and up.status = 'available'
      and (p_selections->'socialPlant' = 'null'::jsonb or exists (
        select 1 from public.plan_features pf
        where pf.plan_id = up.plan_id and pf.feature_key = 'social'
          and pf.feature_value->>'choice' = p_selections->>'socialPlant'
      ))
      and (p_selections->'suitePlant' = 'null'::jsonb or exists (
        select 1 from public.plan_features pf
        where pf.plan_id = up.plan_id and pf.feature_key = 'suite'
          and pf.feature_value->>'choice' = p_selections->>'suitePlant'
      ))
      and not exists (
        select 1 from jsonb_each_text(p_selections) as chosen(key, value)
        where chosen.key in ('counter','stone','rodamao','service')
          and not exists (
            select 1 from public.customization_groups g
            join public.customization_options o on o.group_id = g.id
            join public.option_compatibilities oc on oc.option_id = o.id
            where g.code = chosen.key and g.status = 'active'
              and o.code = chosen.value and o.status = 'active'
              and oc.plan_id = up.plan_id
          )
      )
  ) then
    raise exception 'Choices are not available together for this unit'
      using errcode = '22023';
  end if;

  insert into public.unit_configuration_state(unit_id)
    values (p_unit_id) on conflict (unit_id) do nothing;
  select * into v_state from public.unit_configuration_state
    where unit_id = p_unit_id for update;
  if v_state.revision <> p_expected_revision then
    raise exception 'Configuration changed in another session' using errcode = '40001';
  end if;
  if v_state.status <> 'draft' then
    raise exception 'Configuration is not editable' using errcode = '42501';
  end if;
  if not exists (
    select 1 from public.customization_windows w
    where w.unit_id = p_unit_id and w.status = 'active'
      and clock_timestamp() >= w.opens_at and clock_timestamp() < w.closes_at
  ) then
    raise exception 'Customization window closed' using errcode = '42501';
  end if;

  delete from public.customer_customizations where unit_id = p_unit_id;
  update public.unit_configuration_state
    set plan_id = null, draft_selections = p_selections,
        revision = revision + 1, updated_by = (select auth.uid()),
        updated_at = now()
    where unit_id = p_unit_id returning * into v_state;
  insert into public.customization_history
    (unit_id, revision, plan_id, selections, actor_customer_id,
     actor_user_id, actor_ownership_role, action, selection_format)
  values (p_unit_id, v_state.revision, null, p_selections,
          p_customer_id, (select auth.uid()), v_role, 'draft_saved', 'ui_draft');
  return v_state;
end;
$$;


ALTER FUNCTION "public"."save_partial_unit_configuration"("p_customer_id" "uuid", "p_unit_id" "uuid", "p_selections" "jsonb", "p_expected_revision" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."save_staff_unit_configuration"("p_unit_id" "uuid", "p_plan_id" "uuid", "p_option_ids" "uuid"[], "p_partial_selections" "jsonb", "p_expected_revision" integer) RETURNS "public"."unit_configuration_state"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_state public.unit_configuration_state;
  v_staff_role text;
  v_customer_id uuid;
  v_count integer;
  v_distinct_groups integer;
  v_selections jsonb;
  v_key text;
  v_value jsonb;
begin
  v_staff_role := public.current_staff_role();
  if v_staff_role not in ('admin', 'architect') or v_staff_role is null
    or not public.staff_can_access_unit(p_unit_id)
    or not exists (select 1 from public.units u where u.id = p_unit_id and u.active) then
    raise exception 'Unit access denied' using errcode = '42501';
  end if;
  if p_expected_revision is null or p_expected_revision < 0 then
    raise exception 'Invalid revision' using errcode = '22023';
  end if;
  select cu.customer_id into v_customer_id
  from public.customer_units cu
  where cu.unit_id = p_unit_id and cu.active
  order by (cu.ownership_role = 'owner') desc, cu.created_at, cu.customer_id
  limit 1;
  if v_customer_id is null then
    raise exception 'Unit has no active purchasing link' using errcode = '22023';
  end if;

  if p_plan_id is null then
    if p_option_ids is not null or jsonb_typeof(p_partial_selections) is distinct from 'object'
      or not (p_partial_selections ?& array['socialPlant','suitePlant','counter','stone','rodamao','service'])
      or (select count(*) from jsonb_object_keys(p_partial_selections)) <> 6
      or (p_partial_selections->'socialPlant' <> 'null'::jsonb
        and p_partial_selections->'suitePlant' <> 'null'::jsonb) then
      raise exception 'Invalid partial configuration' using errcode = '22023';
    end if;
    for v_key, v_value in select key, value from jsonb_each(p_partial_selections) loop
      if v_key in ('socialPlant', 'suitePlant') then
        if jsonb_typeof(v_value) not in ('null', 'string') then
          raise exception 'Invalid plant choice' using errcode = '22023';
        end if;
      elsif jsonb_typeof(v_value) <> 'string' then
        raise exception 'Invalid material choice' using errcode = '22023';
      end if;
    end loop;
    if not exists (
      select 1 from public.unit_plans up
      join public.plans p on p.id = up.plan_id and p.status = 'active'
      where up.unit_id = p_unit_id and up.status = 'available'
        and (p_partial_selections->'socialPlant' = 'null'::jsonb or exists (
          select 1 from public.plan_features pf
          where pf.plan_id = up.plan_id and pf.feature_key = 'social'
            and pf.feature_value->>'choice' = p_partial_selections->>'socialPlant'
        ))
        and (p_partial_selections->'suitePlant' = 'null'::jsonb or exists (
          select 1 from public.plan_features pf
          where pf.plan_id = up.plan_id and pf.feature_key = 'suite'
            and pf.feature_value->>'choice' = p_partial_selections->>'suitePlant'
        ))
        and not exists (
          select 1 from jsonb_each_text(p_partial_selections) as chosen(key, value)
          where chosen.key in ('counter','stone','rodamao','service')
            and not exists (
              select 1 from public.customization_groups g
              join public.customization_options o on o.group_id = g.id
              join public.option_compatibilities oc on oc.option_id = o.id
              where g.code = chosen.key and g.status = 'active'
                and o.code = chosen.value and o.status = 'active'
                and oc.plan_id = up.plan_id
            )
        )
    ) then
      raise exception 'Choices are not available together for this unit'
        using errcode = '22023';
    end if;
    v_selections := p_partial_selections;
  else
    if p_partial_selections is not null or p_option_ids is null or not exists (
      select 1 from public.unit_plans up
      join public.plans p on p.id = up.plan_id
      where up.unit_id = p_unit_id and up.plan_id = p_plan_id
        and up.status = 'available' and p.status = 'active'
    ) then
      raise exception 'Invalid or unavailable plan' using errcode = '22023';
    end if;
    select count(*), count(distinct o.group_id),
      coalesce(jsonb_object_agg(o.group_id::text, o.id::text), '{}'::jsonb)
      into v_count, v_distinct_groups, v_selections
    from unnest(p_option_ids) as selected(option_id)
    join public.customization_options o on o.id = selected.option_id and o.status = 'active'
    join public.customization_groups g on g.id = o.group_id and g.status = 'active'
    join public.option_compatibilities oc on oc.option_id = o.id and oc.plan_id = p_plan_id;
    if v_count <> cardinality(p_option_ids) or v_count <> v_distinct_groups then
      raise exception 'Invalid or duplicate customization option' using errcode = '22023';
    end if;
  end if;

  insert into public.unit_configuration_state(unit_id)
    values (p_unit_id) on conflict (unit_id) do nothing;
  select * into v_state from public.unit_configuration_state
    where unit_id = p_unit_id for update;
  if v_state.revision <> p_expected_revision then
    raise exception 'Configuration changed in another session' using errcode = '40001';
  end if;
  if v_state.status <> 'draft' then
    raise exception 'Configuration is not editable' using errcode = '42501';
  end if;
  if not exists (
    select 1 from public.customization_windows w
    where w.unit_id = p_unit_id and w.status = 'active'
      and clock_timestamp() >= w.opens_at and clock_timestamp() < w.closes_at
  ) then
    raise exception 'Customization window closed' using errcode = '42501';
  end if;

  delete from public.customer_customizations where unit_id = p_unit_id;
  update public.unit_configuration_state
    set plan_id = p_plan_id,
        draft_selections = case when p_plan_id is null then p_partial_selections else '{}'::jsonb end,
        revision = revision + 1, updated_by = (select auth.uid()), updated_at = now()
    where unit_id = p_unit_id returning * into v_state;
  if p_plan_id is not null then
    insert into public.customer_customizations
      (unit_id, group_id, option_id, plan_id, customer_id, revision, updated_by)
    select p_unit_id, o.group_id, o.id, p_plan_id, v_customer_id,
      v_state.revision, (select auth.uid())
    from unnest(p_option_ids) as selected(option_id)
    join public.customization_options o on o.id = selected.option_id;
  end if;
  insert into public.customization_history
    (unit_id, revision, plan_id, selections, actor_customer_id,
     actor_user_id, actor_ownership_role, actor_staff_role, action, selection_format)
  values (p_unit_id, v_state.revision, p_plan_id, v_selections, null,
          (select auth.uid()), null, v_staff_role, 'draft_saved',
          case when p_plan_id is null then 'ui_draft' else 'catalog_ids' end);
  return v_state;
end;
$$;


ALTER FUNCTION "public"."save_staff_unit_configuration"("p_unit_id" "uuid", "p_plan_id" "uuid", "p_option_ids" "uuid"[], "p_partial_selections" "jsonb", "p_expected_revision" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."save_unit_configuration"("p_customer_id" "uuid", "p_unit_id" "uuid", "p_plan_id" "uuid", "p_option_ids" "uuid"[], "p_expected_revision" integer) RETURNS "public"."unit_configuration_state"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_state public.unit_configuration_state;
  v_role text;
  v_count integer;
  v_distinct_groups integer;
  v_selections jsonb;
begin
  if (select auth.uid()) is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select cu.ownership_role into v_role
  from public.customer_units cu
  join public.customer_users usr on usr.customer_id = cu.customer_id and usr.active
  join public.units u on u.id = cu.unit_id and u.active
  where cu.customer_id = p_customer_id and cu.unit_id = p_unit_id
    and cu.active and usr.user_id = (select auth.uid());
  if v_role not in ('owner', 'co_owner') or v_role is null then
    raise exception 'Unit access denied' using errcode = '42501';
  end if;
  if p_plan_id is null or p_option_ids is null or p_expected_revision is null
      or p_expected_revision < 0 then
    raise exception 'Invalid configuration' using errcode = '22023';
  end if;
  if not exists (
    select 1 from public.unit_plans up
    join public.plans p on p.id = up.plan_id
    where up.unit_id = p_unit_id and up.plan_id = p_plan_id
      and up.status = 'available' and p.status = 'active'
  ) then
    raise exception 'Plan unavailable for unit' using errcode = '22023';
  end if;
  if not exists (
    select 1 from public.customization_windows w
    where w.unit_id = p_unit_id and w.status = 'active'
      and statement_timestamp() >= w.opens_at and statement_timestamp() < w.closes_at
  ) then
    raise exception 'Customization window closed' using errcode = '42501';
  end if;

  select count(*), count(distinct o.group_id),
         coalesce(jsonb_object_agg(o.group_id::text, o.id::text), '{}'::jsonb)
    into v_count, v_distinct_groups, v_selections
  from unnest(p_option_ids) as selected(option_id)
  join public.customization_options o on o.id = selected.option_id and o.status = 'active'
  join public.customization_groups g on g.id = o.group_id and g.status = 'active'
  join public.option_compatibilities oc on oc.option_id = o.id and oc.plan_id = p_plan_id;
  if v_count <> cardinality(p_option_ids) or v_count <> v_distinct_groups then
    raise exception 'Invalid or duplicate customization option' using errcode = '22023';
  end if;

  insert into public.unit_configuration_state(unit_id)
    values (p_unit_id) on conflict (unit_id) do nothing;
  select * into v_state from public.unit_configuration_state
    where unit_id = p_unit_id for update;
  if v_state.revision <> p_expected_revision then
    raise exception 'Configuration changed in another session' using errcode = '40001';
  end if;
  if v_state.status <> 'draft' then
    raise exception 'Configuration is not editable' using errcode = '42501';
  end if;

  delete from public.customer_customizations where unit_id = p_unit_id;
  update public.unit_configuration_state
    set plan_id = p_plan_id, revision = revision + 1,
        updated_by = (select auth.uid()), updated_at = now()
    where unit_id = p_unit_id returning * into v_state;
  insert into public.customer_customizations
    (unit_id, group_id, option_id, plan_id, customer_id, revision)
  select p_unit_id, o.group_id, o.id, p_plan_id, p_customer_id, v_state.revision
  from unnest(p_option_ids) as selected(option_id)
  join public.customization_options o on o.id = selected.option_id;
  insert into public.customization_history
    (unit_id, revision, plan_id, selections, actor_customer_id,
     actor_user_id, actor_ownership_role, action)
  values (p_unit_id, v_state.revision, p_plan_id, v_selections,
          p_customer_id, (select auth.uid()), v_role, 'draft_saved');
  return v_state;
end;
$$;


ALTER FUNCTION "public"."save_unit_configuration"("p_customer_id" "uuid", "p_unit_id" "uuid", "p_plan_id" "uuid", "p_option_ids" "uuid"[], "p_expected_revision" integer) OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."unit_drafts" (
    "unit_id" "uuid" NOT NULL,
    "selections" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "revision" integer DEFAULT 1 NOT NULL,
    "updated_by" "uuid" NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "unit_drafts_revision_check" CHECK (("revision" > 0)),
    CONSTRAINT "unit_drafts_selections_check" CHECK (("jsonb_typeof"("selections") = 'object'::"text"))
);


ALTER TABLE "public"."unit_drafts" OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."save_unit_draft"("p_unit_id" "uuid", "p_selections" "jsonb", "p_expected_revision" integer) RETURNS "public"."unit_drafts"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
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


ALTER FUNCTION "public"."save_unit_draft"("p_unit_id" "uuid", "p_selections" "jsonb", "p_expected_revision" integer) OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."unit_module_states" (
    "unit_id" "uuid" NOT NULL,
    "module_code" "text" NOT NULL,
    "revision" integer DEFAULT 0 NOT NULL,
    "updated_by" "uuid",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "unit_module_states_revision_check" CHECK (("revision" >= 0))
);


ALTER TABLE "public"."unit_module_states" OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."save_unit_module_choices"("p_customer_id" "uuid", "p_unit_id" "uuid", "p_module_code" "text", "p_selections" "jsonb", "p_expected_revision" integer) RETURNS "public"."unit_module_states"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $_$
declare
  v_state public.unit_module_states;
  v_base_plan_id uuid;
  v_role text;
  v_staff_role text;
  v_key text;
  v_value text;
  v_count integer;
  v_valid_count integer;
  v_window public.unit_module_windows;
  v_saved_at timestamptz;
begin
  if (select auth.uid()) is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if p_unit_id is null or p_module_code is null
    or p_expected_revision is null or p_expected_revision < 0
    or jsonb_typeof(p_selections) is distinct from 'object' then
    raise exception 'Invalid module choices' using errcode = '22023';
  end if;

  -- Authorizations and assignments also lock the unit when changed.
  perform 1 from public.units where id = p_unit_id and active for update;
  if not found then
    raise exception 'Unit access denied' using errcode = '42501';
  end if;
  if p_customer_id is null then
    v_staff_role := public.current_staff_role();
    if v_staff_role is null or not public.staff_can_access_unit(p_unit_id) then
      raise exception 'Unit access denied' using errcode = '42501';
    end if;
  else
    select cu.ownership_role into v_role
    from public.customer_units cu
    join public.customer_users usr
      on usr.customer_id = cu.customer_id and usr.active
    where cu.customer_id = p_customer_id and cu.unit_id = p_unit_id
      and cu.active and usr.user_id = (select auth.uid());
    if v_role is null or v_role not in ('owner', 'co_owner') then
      raise exception 'Unit access denied' using errcode = '42501';
    end if;
  end if;

  select a.base_plan_id into v_base_plan_id
  from public.unit_base_plan_assignments a
  join public.base_plans p on p.id = a.base_plan_id and p.status = 'active'
  where a.unit_id = p_unit_id
  for share of a, p;
  if v_base_plan_id is null
    or not exists (select 1 from public.customization_modules m
                   where m.code = p_module_code and m.active)
    or not exists (select 1 from public.customization_groups g
                   where g.module_code = p_module_code and g.status = 'active') then
    raise exception 'Module catalog unavailable' using errcode = '22023';
  end if;

  for v_key, v_value in select key, value from jsonb_each_text(p_selections) loop
    if jsonb_typeof(p_selections->v_key) <> 'string'
      or v_key !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
      or v_value !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
      raise exception 'Invalid module option' using errcode = '22023';
    end if;
  end loop;
  select count(*) into v_count from jsonb_each(p_selections);
  select count(*) into v_valid_count
  from jsonb_each_text(p_selections) chosen(group_key, option_key)
  join public.customization_groups g
    on g.id = chosen.group_key::uuid
    and g.module_code = p_module_code and g.status = 'active'
  join public.customization_options o
    on o.id = chosen.option_key::uuid
    and o.group_id = g.id and o.status = 'active'
  join public.base_plan_option_availability a
    on a.base_plan_id = v_base_plan_id and a.option_id = o.id;
  if v_count <> v_valid_count then
    raise exception 'Option unavailable for module or plan' using errcode = '22023';
  end if;
  -- Check new choices together with unchanged choices of other modules.
  if exists (
    with chosen_options as (
      select value::uuid as option_id from jsonb_each_text(p_selections)
      union all
      select s.option_id from public.unit_module_selections s
      where s.unit_id = p_unit_id and s.module_code <> p_module_code
    )
    select 1 from public.base_plan_option_exclusions e
    join chosen_options first_choice on first_choice.option_id = e.first_option_id
    join chosen_options second_choice on second_choice.option_id = e.second_option_id
    where e.base_plan_id = v_base_plan_id
  ) then
    raise exception 'Incompatible module options' using errcode = '22023';
  end if;

  insert into public.unit_module_states(unit_id, module_code)
  values (p_unit_id, p_module_code) on conflict do nothing;
  select * into v_state from public.unit_module_states
    where unit_id = p_unit_id and module_code = p_module_code for update;
  if v_state.revision <> p_expected_revision then
    raise exception 'Module changed in another session' using errcode = '40001';
  end if;
  select * into v_window from public.unit_module_windows
    where unit_id = p_unit_id and module_code = p_module_code for share;
  v_saved_at := clock_timestamp();
  if v_window.unit_id is null or v_window.status <> 'active'
    or v_saved_at < v_window.opens_at or v_saved_at >= v_window.closes_at then
    raise exception 'Module window closed' using errcode = '42501';
  end if;

  delete from public.unit_module_selections
    where unit_id = p_unit_id and module_code = p_module_code;
  insert into public.unit_module_selections
    (unit_id, module_code, group_id, option_id, updated_by, updated_at)
  select p_unit_id, p_module_code, chosen.group_key::uuid,
    chosen.option_key::uuid, (select auth.uid()), v_saved_at
  from jsonb_each_text(p_selections) chosen(group_key, option_key);
  update public.unit_module_states
    set revision = revision + 1, updated_by = (select auth.uid()),
      updated_at = v_saved_at
    where unit_id = p_unit_id and module_code = p_module_code
    returning * into v_state;
  insert into public.unit_module_history
    (unit_id, module_code, revision, base_plan_id, selections,
     actor_user_id, actor_customer_id, actor_ownership_role,
     actor_staff_role, created_at)
  values (p_unit_id, p_module_code, v_state.revision, v_base_plan_id,
    p_selections, (select auth.uid()), p_customer_id, v_role,
    v_staff_role, v_saved_at);
  return v_state;
end;
$_$;


ALTER FUNCTION "public"."save_unit_module_choices"("p_customer_id" "uuid", "p_unit_id" "uuid", "p_module_code" "text", "p_selections" "jsonb", "p_expected_revision" integer) OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."architect_authorizations" (
    "unit_id" "uuid" NOT NULL,
    "architect_user_id" "uuid" NOT NULL,
    "granted_by_customer_id" "uuid" NOT NULL,
    "granted_by_user_id" "uuid" NOT NULL,
    "active" boolean DEFAULT true NOT NULL,
    "granted_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "revoked_by_user_id" "uuid",
    "revoked_at" timestamp with time zone,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "architect_authorizations_check" CHECK ((("active" AND ("revoked_at" IS NULL) AND ("revoked_by_user_id" IS NULL)) OR ((NOT "active") AND ("revoked_at" IS NOT NULL) AND ("revoked_by_user_id" IS NOT NULL))))
);


ALTER TABLE "public"."architect_authorizations" OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."set_architect_authorization"("p_customer_id" "uuid", "p_unit_id" "uuid", "p_architect_user_id" "uuid", "p_active" boolean) RETURNS "public"."architect_authorizations"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_role text;
  v_row public.architect_authorizations;
begin
  select cu.ownership_role into v_role
  from public.customer_units cu
  join public.customer_users usr on usr.customer_id = cu.customer_id and usr.active
  join public.units u on u.id = cu.unit_id and u.active
  where cu.customer_id = p_customer_id and cu.unit_id = p_unit_id
    and cu.active and usr.user_id = (select auth.uid());
  if v_role not in ('owner', 'co_owner') or v_role is null then
    raise exception 'Unit access denied' using errcode = '42501';
  end if;
  if p_active is null then
    raise exception 'Invalid authorization state' using errcode = '22023';
  end if;
  if p_active and not exists (
    select 1 from public.staff_unit_assignments a
    join public.staff_users s on s.user_id = a.user_id
    where a.unit_id = p_unit_id and a.user_id = p_architect_user_id
      and a.active and s.active and s.role = 'architect'
  ) then
    raise exception 'Architect is not assigned to unit' using errcode = '22023';
  end if;
  perform 1 from public.units where id = p_unit_id for update;
  select * into v_row from public.architect_authorizations
    where unit_id = p_unit_id and architect_user_id = p_architect_user_id for update;
  if p_active and (v_row.unit_id is null
    or not public.current_architect_authorization(p_unit_id, p_architect_user_id)) then
    insert into public.architect_authorizations
      (unit_id, architect_user_id, granted_by_customer_id, granted_by_user_id,
       active, granted_at, revoked_by_user_id, revoked_at, updated_at)
    values (p_unit_id, p_architect_user_id, p_customer_id, (select auth.uid()),
            true, now(), null, null, now())
    on conflict (unit_id, architect_user_id) do update
      set granted_by_customer_id = excluded.granted_by_customer_id,
          granted_by_user_id = excluded.granted_by_user_id,
          active = true, granted_at = now(), revoked_by_user_id = null,
          revoked_at = null, updated_at = now()
    returning * into v_row;
    insert into public.architect_authorization_events
      (unit_id, architect_user_id, actor_customer_id, actor_user_id, action)
    values (p_unit_id, p_architect_user_id, p_customer_id,
            (select auth.uid()), 'granted');
  elsif not p_active and v_row.unit_id is not null and v_row.active then
    update public.architect_authorizations
      set active = false, revoked_by_user_id = (select auth.uid()),
          revoked_at = now(), updated_at = now()
      where unit_id = p_unit_id and architect_user_id = p_architect_user_id
      returning * into v_row;
    insert into public.architect_authorization_events
      (unit_id, architect_user_id, actor_customer_id, actor_user_id, action)
    values (p_unit_id, p_architect_user_id, p_customer_id,
            (select auth.uid()), 'revoked');
  end if;
  return v_row;
end;
$$;


ALTER FUNCTION "public"."set_architect_authorization"("p_customer_id" "uuid", "p_unit_id" "uuid", "p_architect_user_id" "uuid", "p_active" boolean) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."set_module_deadline"("p_unit_id" "uuid", "p_module_code" "text", "p_closes_at" timestamp with time zone) RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare v_previous timestamptz;
begin
  if public.current_staff_role() is distinct from 'admin'
    then raise exception 'Admin required' using errcode = '42501'; end if;
  perform 1 from public.units where id = p_unit_id for update;
  if not found or not exists (select 1 from public.customization_modules where code = p_module_code and active)
    then raise exception 'Unit or module not found' using errcode = '22023'; end if;
  select closes_at into v_previous from public.unit_module_windows
    where unit_id = p_unit_id and module_code = p_module_code;
  if p_closes_at is null then
    delete from public.unit_module_windows where unit_id = p_unit_id and module_code = p_module_code;
  else
    insert into public.unit_module_windows(unit_id, module_code, opens_at, closes_at, status)
    values(p_unit_id, p_module_code, least(clock_timestamp(), p_closes_at) - interval '1 second', p_closes_at, 'active')
    on conflict (unit_id, module_code) do update set opens_at = excluded.opens_at,
      closes_at = excluded.closes_at, status = 'active', updated_at = clock_timestamp();
  end if;
  if v_previous is distinct from p_closes_at then
    insert into public.unit_activity_events(unit_id, actor_user_id, actor_role, action, details)
    values(p_unit_id, (select auth.uid()), 'admin', 'module_deadline_changed',
      jsonb_build_object('module_code', p_module_code, 'previous', v_previous, 'closes_at', p_closes_at));
  end if;
end; $$;


ALTER FUNCTION "public"."set_module_deadline"("p_unit_id" "uuid", "p_module_code" "text", "p_closes_at" timestamp with time zone) OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."units" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "code" "text" NOT NULL,
    "tower" "text" NOT NULL,
    "floor_label" "text" NOT NULL,
    "termination" "text" NOT NULL,
    "typology" "text" NOT NULL,
    "active" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "floor_number" integer,
    "external_ref" "text",
    "tower_code" "text",
    "termination_code" "text",
    "area_m2" numeric(8,2),
    "customization_closes_at" timestamp with time zone,
    "customization_status" "text" DEFAULT 'pending'::"text" NOT NULL,
    CONSTRAINT "units_area_m2_positive" CHECK ((("area_m2" IS NULL) OR ("area_m2" > (0)::numeric))),
    CONSTRAINT "units_completed_is_inactive" CHECK ((("customization_status" <> 'completed'::"text") OR (NOT "active"))),
    CONSTRAINT "units_customization_status_check" CHECK (("customization_status" = ANY (ARRAY['pending'::"text", 'completed'::"text"]))),
    CONSTRAINT "units_floor_number_valid" CHECK ((("floor_number" IS NULL) OR ("floor_number" >= 0))),
    CONSTRAINT "units_termination_code_valid" CHECK ((("termination_code" IS NULL) OR ("termination_code" ~ '^[0-9]{2}$'::"text"))),
    CONSTRAINT "units_tower_code_valid" CHECK ((("tower_code" IS NULL) OR ("tower_code" = ANY (ARRAY['A'::"text", 'B'::"text"]))))
);


ALTER TABLE "public"."units" OWNER TO "postgres";


COMMENT ON COLUMN "public"."units"."area_m2" IS 'Apartment area in m², supplied by the team.';



COMMENT ON COLUMN "public"."units"."customization_closes_at" IS 'Exclusive final cutoff for all unit choices and proposal submissions. Module windows may close earlier.';



CREATE OR REPLACE FUNCTION "public"."set_unit_active"("p_unit_id" "uuid", "p_active" boolean) RETURNS "public"."units"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare v_unit public.units;
begin
  if (select public.current_staff_role()) not in ('architect','admin') or public.current_staff_role() is null
    then raise exception 'Staff access required' using errcode = '42501'; end if;
  if p_active is null then raise exception 'Invalid unit status' using errcode = '22023'; end if;
  select * into v_unit from public.units where id = p_unit_id for update;
  if not found then raise exception 'Unit not found' using errcode = '22023'; end if;
  if p_active and v_unit.customization_status = 'completed' and public.current_staff_role() <> 'admin'
    then raise exception 'Only admin can reopen completed unit' using errcode = '42501'; end if;
  if v_unit.active is distinct from p_active then
    update public.units set active = p_active,
      customization_status = case when p_active then 'pending' else customization_status end
      where id = p_unit_id returning * into v_unit;
    insert into public.unit_activity_events(unit_id, actor_user_id, actor_role, action, details)
    values(p_unit_id, (select auth.uid()), public.current_staff_role(), 'unit_status_changed',
      jsonb_build_object('active', p_active, 'customization_status', v_unit.customization_status));
  end if;
  return v_unit;
end; $$;


ALTER FUNCTION "public"."set_unit_active"("p_unit_id" "uuid", "p_active" boolean) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."set_unit_customer"("p_unit_id" "uuid", "p_customer_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare v_previous uuid;
begin
  if public.current_staff_role() is distinct from 'admin'
    then raise exception 'Admin required' using errcode = '42501'; end if;
  perform 1 from public.units where id = p_unit_id for update;
  if not found or (p_customer_id is not null and not exists (select 1 from public.customers where id = p_customer_id))
    then raise exception 'Unit or customer not found' using errcode = '22023'; end if;
  select customer_id into v_previous from public.customer_units where unit_id = p_unit_id and active;
  update public.customer_units set active = false where unit_id = p_unit_id and active;
  if p_customer_id is not null then
    insert into public.customer_units(customer_id, unit_id, ownership_role, active)
    values(p_customer_id, p_unit_id, 'owner', true) on conflict(customer_id, unit_id)
    do update set ownership_role = 'owner', active = true;
  end if;
  if v_previous is distinct from p_customer_id then
    insert into public.unit_activity_events(unit_id, actor_user_id, actor_role, action, details)
    values(p_unit_id, (select auth.uid()), 'admin', 'unit_customer_changed',
      jsonb_build_object('previous_customer_id', v_previous, 'customer_id', p_customer_id));
  end if;
end; $$;


ALTER FUNCTION "public"."set_unit_customer"("p_unit_id" "uuid", "p_customer_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."set_unit_deadline"("p_unit_id" "uuid", "p_closes_at" timestamp with time zone) RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare v_previous timestamptz;
begin
  if public.current_staff_role() is distinct from 'admin'
    then raise exception 'Admin required' using errcode = '42501'; end if;
  select customization_closes_at into v_previous from public.units where id = p_unit_id for update;
  if not found then raise exception 'Unit not found' using errcode = '22023'; end if;
  update public.units set customization_closes_at = p_closes_at where id = p_unit_id;
  if v_previous is distinct from p_closes_at then
    insert into public.unit_activity_events(unit_id, actor_user_id, actor_role, action, details)
    values(p_unit_id, (select auth.uid()), 'admin', 'unit_deadline_changed',
      jsonb_build_object('previous', v_previous, 'closes_at', p_closes_at));
  end if;
end; $$;


ALTER FUNCTION "public"."set_unit_deadline"("p_unit_id" "uuid", "p_closes_at" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."staff_can_access_unit"("p_unit_id" "uuid") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
  select exists (select 1 from public.units where id = p_unit_id)
    and public.current_staff_role() in ('architect', 'admin');
$$;


ALTER FUNCTION "public"."staff_can_access_unit"("p_unit_id" "uuid") OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."unit_proposals" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "unit_id" "uuid" NOT NULL,
    "latest_revision" integer DEFAULT 1 NOT NULL,
    "submitted_by_customer_id" "uuid" NOT NULL,
    "submitted_by_user_id" "uuid" NOT NULL,
    "submitted_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "cycle_number" integer DEFAULT 1 NOT NULL,
    "status" "text" DEFAULT 'open'::"text" NOT NULL,
    "reviewed_at" timestamp with time zone,
    CONSTRAINT "unit_proposals_cycle_number_check" CHECK (("cycle_number" > 0)),
    CONSTRAINT "unit_proposals_latest_revision_check" CHECK (("latest_revision" > 0)),
    CONSTRAINT "unit_proposals_status_check" CHECK (("status" = ANY (ARRAY['open'::"text", 'reviewed'::"text"])))
);


ALTER TABLE "public"."unit_proposals" OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."submit_unit_proposal"("p_customer_id" "uuid", "p_unit_id" "uuid", "p_expected_module_revisions" "jsonb") RETURNS "public"."unit_proposals"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
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


ALTER FUNCTION "public"."submit_unit_proposal"("p_customer_id" "uuid", "p_unit_id" "uuid", "p_expected_module_revisions" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."unit_module_choice_snapshot"("p_unit_id" "uuid") RETURNS "jsonb"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
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


ALTER FUNCTION "public"."unit_module_choice_snapshot"("p_unit_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."unit_module_revision_snapshot"("p_unit_id" "uuid") RETURNS "jsonb"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
  select coalesce(jsonb_object_agg(s.module_code, s.revision), '{}'::jsonb)
  from public.unit_module_states s where s.unit_id = p_unit_id;
$$;


ALTER FUNCTION "public"."unit_module_revision_snapshot"("p_unit_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."validate_unit_session"("p_unit_id" "uuid", "p_selections" "jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $_$
declare v_plan uuid; v_choices jsonb; v_count integer;
begin
  if (select auth.uid()) is null or not (coalesce(public.staff_can_access_unit(p_unit_id), false)
    or public.customer_can_access_unit(p_unit_id))
    then raise exception 'Unit access denied' using errcode = '42501'; end if;
  if jsonb_typeof(p_selections) is distinct from 'object'
    then raise exception 'Invalid session choices' using errcode = '22023'; end if;
  select a.base_plan_id into v_plan from public.unit_base_plan_assignments a
    join public.base_plans p on p.id = a.base_plan_id and p.status = 'active' where a.unit_id = p_unit_id;
  if v_plan is null then raise exception 'Base plan not assigned' using errcode = '22023'; end if;
  select coalesce(jsonb_object_agg(group_id::text, option_id::text), '{}'::jsonb) into v_choices
    from public.base_plan_option_defaults where base_plan_id = v_plan;
  v_choices := v_choices || p_selections;
  if exists (select 1 from jsonb_each(v_choices) e where jsonb_typeof(e.value) <> 'string'
    or e.key !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    or (e.value #>> '{}') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')
    then raise exception 'Invalid session option' using errcode = '22023'; end if;
  select count(*) into v_count from jsonb_each_text(v_choices) e
    join public.customization_options o on o.id = e.value::uuid and o.group_id = e.key::uuid and o.status = 'active'
    join public.customization_groups g on g.id = o.group_id and g.status = 'active'
    join public.customization_modules m on m.code = g.module_code and m.active
    join public.base_plan_option_availability a on a.option_id = o.id and a.base_plan_id = v_plan;
  if v_count <> (select count(*) from jsonb_each(v_choices)) then
    raise exception 'Option unavailable for base plan' using errcode = '22023'; end if;
  if exists (select 1 from public.customization_groups g
    join public.customization_modules m on m.code = g.module_code and m.active
    where g.status = 'active' and g.required_for_submission
      and exists (select 1 from public.customization_options o join public.base_plan_option_availability a
        on a.option_id = o.id and a.base_plan_id = v_plan where o.group_id = g.id and o.status = 'active')
      and not (v_choices ? g.id::text)) then
    raise exception 'Required choices are incomplete' using errcode = '22023'; end if;
  if exists (select 1 from public.base_plan_option_exclusions e where e.base_plan_id = v_plan
    and exists (select 1 from jsonb_each_text(v_choices) c where c.value::uuid = e.first_option_id)
    and exists (select 1 from jsonb_each_text(v_choices) c where c.value::uuid = e.second_option_id))
    or exists (select 1 from public.base_plan_option_requirements r where r.base_plan_id = v_plan
      and exists (select 1 from jsonb_each_text(v_choices) c where c.value::uuid = r.option_id)
      and not exists (select 1 from jsonb_each_text(v_choices) c where c.value::uuid = r.required_option_id))
    then raise exception 'Incompatible session choices' using errcode = '22023'; end if;
  if exists (select 1 from public.units where id = p_unit_id
    and customization_closes_at is not null and clock_timestamp() >= customization_closes_at)
    or exists (select 1 from public.unit_module_windows w
      join public.customization_groups g on g.module_code = w.module_code
      where w.unit_id = p_unit_id and v_choices ? g.id::text
        and (w.status <> 'active' or clock_timestamp() < w.opens_at or clock_timestamp() >= w.closes_at))
    then raise exception 'Customization deadline closed' using errcode = '42501'; end if;
  return v_choices;
end; $_$;


ALTER FUNCTION "public"."validate_unit_session"("p_unit_id" "uuid", "p_selections" "jsonb") OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."architect_assistance_events" (
    "id" bigint NOT NULL,
    "request_id" "uuid" NOT NULL,
    "action" "text" NOT NULL,
    "actor_user_id" "uuid" NOT NULL,
    "note" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "architect_assistance_events_action_check" CHECK (("action" = ANY (ARRAY['requested'::"text", 'accepted'::"text", 'resolved'::"text", 'canceled'::"text"]))),
    CONSTRAINT "architect_assistance_events_note_check" CHECK ((("note" IS NULL) OR ("length"("note") <= 2000)))
);


ALTER TABLE "public"."architect_assistance_events" OWNER TO "postgres";


ALTER TABLE "public"."architect_assistance_events" ALTER COLUMN "id" ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME "public"."architect_assistance_events_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."architect_authorization_events" (
    "id" bigint NOT NULL,
    "unit_id" "uuid" NOT NULL,
    "architect_user_id" "uuid" NOT NULL,
    "actor_customer_id" "uuid" NOT NULL,
    "actor_user_id" "uuid" NOT NULL,
    "action" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "architect_authorization_events_action_check" CHECK (("action" = ANY (ARRAY['granted'::"text", 'revoked'::"text"])))
);


ALTER TABLE "public"."architect_authorization_events" OWNER TO "postgres";


ALTER TABLE "public"."architect_authorization_events" ALTER COLUMN "id" ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME "public"."architect_authorization_events_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."base_plan_option_availability" (
    "base_plan_id" "uuid" NOT NULL,
    "option_id" "uuid" NOT NULL
);


ALTER TABLE "public"."base_plan_option_availability" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."base_plan_option_defaults" (
    "base_plan_id" "uuid" NOT NULL,
    "group_id" "uuid" NOT NULL,
    "option_id" "uuid" NOT NULL
);


ALTER TABLE "public"."base_plan_option_defaults" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."base_plan_option_exclusions" (
    "base_plan_id" "uuid" NOT NULL,
    "first_option_id" "uuid" NOT NULL,
    "second_option_id" "uuid" NOT NULL,
    CONSTRAINT "base_plan_option_exclusions_check" CHECK (("first_option_id" < "second_option_id"))
);


ALTER TABLE "public"."base_plan_option_exclusions" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."base_plan_option_requirements" (
    "base_plan_id" "uuid" NOT NULL,
    "option_id" "uuid" NOT NULL,
    "required_option_id" "uuid" NOT NULL,
    CONSTRAINT "base_plan_option_requirements_check" CHECK (("option_id" <> "required_option_id"))
);


ALTER TABLE "public"."base_plan_option_requirements" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."base_plans" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "code" "text" NOT NULL,
    "name" "text" NOT NULL,
    "description" "text",
    "status" "text" DEFAULT 'active'::"text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "base_plans_code_check" CHECK (("length"("btrim"("code")) > 0)),
    CONSTRAINT "base_plans_name_check" CHECK (("length"("btrim"("name")) > 0)),
    CONSTRAINT "base_plans_status_check" CHECK (("status" = ANY (ARRAY['active'::"text", 'archived'::"text"])))
);


ALTER TABLE "public"."base_plans" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."customer_customizations" (
    "unit_id" "uuid" NOT NULL,
    "group_id" "uuid" NOT NULL,
    "option_id" "uuid" NOT NULL,
    "plan_id" "uuid" NOT NULL,
    "customer_id" "uuid" NOT NULL,
    "revision" integer NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_by" "uuid",
    CONSTRAINT "customer_customizations_revision_check" CHECK (("revision" > 0))
);


ALTER TABLE "public"."customer_customizations" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."customer_units" (
    "customer_id" "uuid" NOT NULL,
    "unit_id" "uuid" NOT NULL,
    "active" boolean DEFAULT true NOT NULL,
    "ownership_role" "text" DEFAULT 'owner'::"text" NOT NULL,
    "purchase_date" "date",
    "external_ref" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "customer_units_active_owner_only" CHECK (((NOT "active") OR ("ownership_role" = 'owner'::"text"))),
    CONSTRAINT "customer_units_ownership_role_valid" CHECK (("ownership_role" = ANY (ARRAY['owner'::"text", 'co_owner'::"text"])))
);


ALTER TABLE "public"."customer_units" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."customer_users" (
    "customer_id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "active" boolean DEFAULT true NOT NULL
);


ALTER TABLE "public"."customer_users" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."customers" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "name" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "email" "text",
    "external_ref" "text"
);


ALTER TABLE "public"."customers" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."customization_groups" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "code" "text" NOT NULL,
    "name" "text" NOT NULL,
    "sort_order" integer DEFAULT 0 NOT NULL,
    "status" "text" DEFAULT 'active'::"text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "module_code" "text",
    "required_for_submission" boolean DEFAULT true NOT NULL,
    CONSTRAINT "customization_groups_code_check" CHECK (("length"("btrim"("code")) > 0)),
    CONSTRAINT "customization_groups_name_check" CHECK (("length"("btrim"("name")) > 0)),
    CONSTRAINT "customization_groups_status_check" CHECK (("status" = ANY (ARRAY['active'::"text", 'archived'::"text"])))
);


ALTER TABLE "public"."customization_groups" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."customization_history" (
    "unit_id" "uuid" NOT NULL,
    "revision" integer NOT NULL,
    "plan_id" "uuid",
    "selections" "jsonb" NOT NULL,
    "actor_customer_id" "uuid",
    "actor_user_id" "uuid" NOT NULL,
    "actor_ownership_role" "text",
    "action" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "selection_format" "text" DEFAULT 'catalog_ids'::"text" NOT NULL,
    "actor_staff_role" "text",
    CONSTRAINT "customization_history_action_check" CHECK (("action" = 'draft_saved'::"text")),
    CONSTRAINT "customization_history_actor_kind_check" CHECK (((("actor_customer_id" IS NOT NULL) AND ("actor_ownership_role" IS NOT NULL) AND ("actor_staff_role" IS NULL)) OR (("actor_customer_id" IS NULL) AND ("actor_ownership_role" IS NULL) AND ("actor_staff_role" IS NOT NULL)))),
    CONSTRAINT "customization_history_actor_ownership_role_check" CHECK (("actor_ownership_role" = ANY (ARRAY['owner'::"text", 'co_owner'::"text"]))),
    CONSTRAINT "customization_history_actor_staff_role_check" CHECK (("actor_staff_role" = ANY (ARRAY['admin'::"text", 'architect'::"text"]))),
    CONSTRAINT "customization_history_revision_check" CHECK (("revision" > 0)),
    CONSTRAINT "customization_history_selection_format_check" CHECK (("selection_format" = ANY (ARRAY['catalog_ids'::"text", 'ui_draft'::"text"]))),
    CONSTRAINT "customization_history_selections_check" CHECK (("jsonb_typeof"("selections") = 'object'::"text"))
);


ALTER TABLE "public"."customization_history" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."customization_modules" (
    "code" "text" NOT NULL,
    "name" "text" NOT NULL,
    "active" boolean DEFAULT true NOT NULL,
    "sort_order" integer DEFAULT 0 NOT NULL,
    CONSTRAINT "customization_modules_code_check" CHECK (("length"("btrim"("code")) > 0)),
    CONSTRAINT "customization_modules_name_check" CHECK (("length"("btrim"("name")) > 0))
);


ALTER TABLE "public"."customization_modules" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."customization_options" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "group_id" "uuid" NOT NULL,
    "code" "text" NOT NULL,
    "name" "text" NOT NULL,
    "description" "text",
    "sort_order" integer DEFAULT 0 NOT NULL,
    "status" "text" DEFAULT 'active'::"text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "customization_options_code_check" CHECK (("length"("btrim"("code")) > 0)),
    CONSTRAINT "customization_options_name_check" CHECK (("length"("btrim"("name")) > 0)),
    CONSTRAINT "customization_options_status_check" CHECK (("status" = ANY (ARRAY['active'::"text", 'archived'::"text"])))
);


ALTER TABLE "public"."customization_options" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."customization_windows" (
    "unit_id" "uuid" NOT NULL,
    "opens_at" timestamp with time zone NOT NULL,
    "closes_at" timestamp with time zone NOT NULL,
    "status" "text" DEFAULT 'active'::"text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "customization_windows_check" CHECK (("opens_at" < "closes_at")),
    CONSTRAINT "customization_windows_status_check" CHECK (("status" = ANY (ARRAY['active'::"text", 'suspended'::"text"])))
);


ALTER TABLE "public"."customization_windows" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."draft_history" (
    "id" bigint NOT NULL,
    "unit_id" "uuid" NOT NULL,
    "revision" integer NOT NULL,
    "selections" "jsonb" NOT NULL,
    "actor_id" "uuid" NOT NULL,
    "actor_role" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."draft_history" OWNER TO "postgres";


ALTER TABLE "public"."draft_history" ALTER COLUMN "id" ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME "public"."draft_history_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."import_rows" (
    "id" bigint NOT NULL,
    "batch_id" "uuid" NOT NULL,
    "line_number" integer NOT NULL,
    "status" "text" NOT NULL,
    "reason" "text",
    "customer_external_ref" "text",
    "unit_external_ref" "text",
    "link_external_ref" "text",
    "raw_payload" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "normalized_payload" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "applied_at" timestamp with time zone,
    "apply_result" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    CONSTRAINT "import_rows_line_valid" CHECK (("line_number" > 0)),
    CONSTRAINT "import_rows_status_valid" CHECK (("status" = ANY (ARRAY['aceito'::"text", 'repetido'::"text", 'pendente'::"text"])))
);


ALTER TABLE "public"."import_rows" OWNER TO "postgres";


ALTER TABLE "public"."import_rows" ALTER COLUMN "id" ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME "public"."import_rows_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."option_compatibilities" (
    "plan_id" "uuid" NOT NULL,
    "option_id" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."option_compatibilities" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."plan_features" (
    "plan_id" "uuid" NOT NULL,
    "feature_key" "text" NOT NULL,
    "feature_value" "jsonb" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "plan_features_feature_key_check" CHECK (("length"("btrim"("feature_key")) > 0)),
    CONSTRAINT "plan_features_feature_value_check" CHECK (("jsonb_typeof"("feature_value") = 'object'::"text"))
);


ALTER TABLE "public"."plan_features" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."plans" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "code" "text" NOT NULL,
    "name" "text" NOT NULL,
    "description" "text",
    "status" "text" DEFAULT 'active'::"text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "plans_code_check" CHECK (("length"("btrim"("code")) > 0)),
    CONSTRAINT "plans_name_check" CHECK (("length"("btrim"("name")) > 0)),
    CONSTRAINT "plans_status_check" CHECK (("status" = ANY (ARRAY['active'::"text", 'archived'::"text"])))
);


ALTER TABLE "public"."plans" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."staff_unit_assignments" (
    "user_id" "uuid" NOT NULL,
    "unit_id" "uuid" NOT NULL,
    "active" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."staff_unit_assignments" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."staff_users" (
    "user_id" "uuid" NOT NULL,
    "name" "text" NOT NULL,
    "role" "text" NOT NULL,
    "active" boolean DEFAULT true NOT NULL,
    CONSTRAINT "staff_users_role_check" CHECK (("role" = ANY (ARRAY['admin'::"text", 'architect'::"text"])))
);


ALTER TABLE "public"."staff_users" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."unit_activity_events" (
    "id" bigint NOT NULL,
    "unit_id" "uuid",
    "actor_user_id" "uuid" NOT NULL,
    "actor_role" "text" NOT NULL,
    "actor_name" "text" DEFAULT "public"."current_actor_name"() NOT NULL,
    "action" "text" NOT NULL,
    "details" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "clock_timestamp"() NOT NULL,
    CONSTRAINT "unit_activity_events_actor_role_check" CHECK (("actor_role" = ANY (ARRAY['customer'::"text", 'architect'::"text", 'admin'::"text"])))
);


ALTER TABLE "public"."unit_activity_events" OWNER TO "postgres";


ALTER TABLE "public"."unit_activity_events" ALTER COLUMN "id" ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME "public"."unit_activity_events_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."unit_base_plan_assignments" (
    "unit_id" "uuid" NOT NULL,
    "base_plan_id" "uuid" NOT NULL,
    "assigned_by" "uuid",
    "assigned_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."unit_base_plan_assignments" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."unit_module_history" (
    "unit_id" "uuid" NOT NULL,
    "module_code" "text" NOT NULL,
    "revision" integer NOT NULL,
    "base_plan_id" "uuid" NOT NULL,
    "selections" "jsonb" NOT NULL,
    "actor_user_id" "uuid" NOT NULL,
    "actor_customer_id" "uuid",
    "actor_ownership_role" "text",
    "actor_staff_role" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "unit_module_history_check" CHECK (((("actor_customer_id" IS NOT NULL) AND ("actor_ownership_role" = ANY (ARRAY['owner'::"text", 'co_owner'::"text"])) AND ("actor_staff_role" IS NULL)) OR (("actor_customer_id" IS NULL) AND ("actor_ownership_role" IS NULL) AND ("actor_staff_role" = ANY (ARRAY['admin'::"text", 'architect'::"text"]))))),
    CONSTRAINT "unit_module_history_revision_check" CHECK (("revision" > 0)),
    CONSTRAINT "unit_module_history_selections_check" CHECK (("jsonb_typeof"("selections") = 'object'::"text"))
);


ALTER TABLE "public"."unit_module_history" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."unit_module_selections" (
    "unit_id" "uuid" NOT NULL,
    "module_code" "text" NOT NULL,
    "group_id" "uuid" NOT NULL,
    "option_id" "uuid" NOT NULL,
    "updated_by" "uuid" NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."unit_module_selections" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."unit_module_windows" (
    "unit_id" "uuid" NOT NULL,
    "module_code" "text" NOT NULL,
    "opens_at" timestamp with time zone NOT NULL,
    "closes_at" timestamp with time zone NOT NULL,
    "status" "text" DEFAULT 'active'::"text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "unit_module_windows_check" CHECK (("opens_at" < "closes_at")),
    CONSTRAINT "unit_module_windows_status_check" CHECK (("status" = ANY (ARRAY['active'::"text", 'suspended'::"text"])))
);


ALTER TABLE "public"."unit_module_windows" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."unit_plans" (
    "unit_id" "uuid" NOT NULL,
    "plan_id" "uuid" NOT NULL,
    "status" "text" DEFAULT 'available'::"text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "unit_plans_status_check" CHECK (("status" = ANY (ARRAY['available'::"text", 'unavailable'::"text"])))
);


ALTER TABLE "public"."unit_plans" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."unit_proposal_versions" (
    "proposal_id" "uuid" NOT NULL,
    "revision" integer NOT NULL,
    "action" "text" NOT NULL,
    "base_plan_id" "uuid" NOT NULL,
    "selections" "jsonb" NOT NULL,
    "module_revisions" "jsonb" NOT NULL,
    "actor_user_id" "uuid" NOT NULL,
    "actor_customer_id" "uuid",
    "actor_ownership_role" "text",
    "actor_staff_role" "text",
    "source_module_code" "text",
    "source_module_revision" integer,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "unit_proposal_versions_action_check" CHECK (("action" = ANY (ARRAY['submitted'::"text", 'choices_updated'::"text"]))),
    CONSTRAINT "unit_proposal_versions_check" CHECK (((("action" = 'submitted'::"text") AND ("revision" = 1) AND ("source_module_code" IS NULL) AND ("source_module_revision" IS NULL)) OR (("action" = 'choices_updated'::"text") AND ("revision" > 1) AND ((("source_module_code" IS NULL) AND ("source_module_revision" IS NULL)) OR (("source_module_code" IS NOT NULL) AND ("source_module_revision" > 0)))))),
    CONSTRAINT "unit_proposal_versions_check1" CHECK (((("actor_customer_id" IS NOT NULL) AND ("actor_ownership_role" = ANY (ARRAY['owner'::"text", 'co_owner'::"text"])) AND ("actor_staff_role" IS NULL)) OR (("actor_customer_id" IS NULL) AND ("actor_ownership_role" IS NULL) AND ("actor_staff_role" = ANY (ARRAY['admin'::"text", 'architect'::"text"]))))),
    CONSTRAINT "unit_proposal_versions_module_revisions_check" CHECK (("jsonb_typeof"("module_revisions") = 'object'::"text")),
    CONSTRAINT "unit_proposal_versions_revision_check" CHECK (("revision" > 0)),
    CONSTRAINT "unit_proposal_versions_selections_check" CHECK (("jsonb_typeof"("selections") = 'object'::"text"))
);


ALTER TABLE "public"."unit_proposal_versions" OWNER TO "postgres";


ALTER TABLE ONLY "public"."architect_assistance_events"
    ADD CONSTRAINT "architect_assistance_events_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."architect_assistance_requests"
    ADD CONSTRAINT "architect_assistance_requests_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."architect_authorization_events"
    ADD CONSTRAINT "architect_authorization_events_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."architect_authorizations"
    ADD CONSTRAINT "architect_authorizations_pkey" PRIMARY KEY ("unit_id", "architect_user_id");



ALTER TABLE ONLY "public"."base_plan_option_availability"
    ADD CONSTRAINT "base_plan_option_availability_pkey" PRIMARY KEY ("base_plan_id", "option_id");



ALTER TABLE ONLY "public"."base_plan_option_defaults"
    ADD CONSTRAINT "base_plan_option_defaults_pkey" PRIMARY KEY ("base_plan_id", "group_id");



ALTER TABLE ONLY "public"."base_plan_option_exclusions"
    ADD CONSTRAINT "base_plan_option_exclusions_pkey" PRIMARY KEY ("base_plan_id", "first_option_id", "second_option_id");



ALTER TABLE ONLY "public"."base_plan_option_requirements"
    ADD CONSTRAINT "base_plan_option_requirements_pkey" PRIMARY KEY ("base_plan_id", "option_id", "required_option_id");



ALTER TABLE ONLY "public"."base_plans"
    ADD CONSTRAINT "base_plans_code_key" UNIQUE ("code");



ALTER TABLE ONLY "public"."base_plans"
    ADD CONSTRAINT "base_plans_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."configuration_reviews"
    ADD CONSTRAINT "configuration_reviews_pkey" PRIMARY KEY ("unit_id", "revision");



ALTER TABLE ONLY "public"."customer_customizations"
    ADD CONSTRAINT "customer_customizations_pkey" PRIMARY KEY ("unit_id", "group_id");



ALTER TABLE ONLY "public"."customer_units"
    ADD CONSTRAINT "customer_units_pkey" PRIMARY KEY ("customer_id", "unit_id");



ALTER TABLE ONLY "public"."customer_users"
    ADD CONSTRAINT "customer_users_pkey" PRIMARY KEY ("customer_id", "user_id");



ALTER TABLE ONLY "public"."customers"
    ADD CONSTRAINT "customers_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."customization_groups"
    ADD CONSTRAINT "customization_groups_code_key" UNIQUE ("code");



ALTER TABLE ONLY "public"."customization_groups"
    ADD CONSTRAINT "customization_groups_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."customization_history"
    ADD CONSTRAINT "customization_history_pkey" PRIMARY KEY ("unit_id", "revision");



ALTER TABLE ONLY "public"."customization_modules"
    ADD CONSTRAINT "customization_modules_pkey" PRIMARY KEY ("code");



ALTER TABLE ONLY "public"."customization_options"
    ADD CONSTRAINT "customization_options_group_id_code_key" UNIQUE ("group_id", "code");



ALTER TABLE ONLY "public"."customization_options"
    ADD CONSTRAINT "customization_options_group_id_id_key" UNIQUE ("group_id", "id");



ALTER TABLE ONLY "public"."customization_options"
    ADD CONSTRAINT "customization_options_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."customization_windows"
    ADD CONSTRAINT "customization_windows_pkey" PRIMARY KEY ("unit_id");



ALTER TABLE ONLY "public"."deadline_notifications"
    ADD CONSTRAINT "deadline_notifications_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."deadline_notifications"
    ADD CONSTRAINT "deadline_notifications_unit_id_customer_id_scope_deadline_d_key" UNIQUE ("unit_id", "customer_id", "scope", "deadline", "days_before");



ALTER TABLE ONLY "public"."draft_history"
    ADD CONSTRAINT "draft_history_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."import_batches"
    ADD CONSTRAINT "import_batches_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."import_rows"
    ADD CONSTRAINT "import_rows_batch_line_unique" UNIQUE ("batch_id", "line_number");



ALTER TABLE ONLY "public"."import_rows"
    ADD CONSTRAINT "import_rows_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."option_compatibilities"
    ADD CONSTRAINT "option_compatibilities_pkey" PRIMARY KEY ("plan_id", "option_id");



ALTER TABLE ONLY "public"."plan_features"
    ADD CONSTRAINT "plan_features_pkey" PRIMARY KEY ("plan_id", "feature_key");



ALTER TABLE ONLY "public"."plans"
    ADD CONSTRAINT "plans_code_key" UNIQUE ("code");



ALTER TABLE ONLY "public"."plans"
    ADD CONSTRAINT "plans_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."staff_unit_assignments"
    ADD CONSTRAINT "staff_unit_assignments_pkey" PRIMARY KEY ("user_id", "unit_id");



ALTER TABLE ONLY "public"."staff_users"
    ADD CONSTRAINT "staff_users_pkey" PRIMARY KEY ("user_id");



ALTER TABLE ONLY "public"."unit_activity_events"
    ADD CONSTRAINT "unit_activity_events_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."unit_base_plan_assignments"
    ADD CONSTRAINT "unit_base_plan_assignments_pkey" PRIMARY KEY ("unit_id");



ALTER TABLE ONLY "public"."unit_configuration_state"
    ADD CONSTRAINT "unit_configuration_state_pkey" PRIMARY KEY ("unit_id");



ALTER TABLE ONLY "public"."unit_configuration_state"
    ADD CONSTRAINT "unit_configuration_state_unit_id_plan_id_key" UNIQUE ("unit_id", "plan_id");



ALTER TABLE ONLY "public"."unit_drafts"
    ADD CONSTRAINT "unit_drafts_pkey" PRIMARY KEY ("unit_id");



ALTER TABLE ONLY "public"."unit_module_history"
    ADD CONSTRAINT "unit_module_history_pkey" PRIMARY KEY ("unit_id", "module_code", "revision");



ALTER TABLE ONLY "public"."unit_module_selections"
    ADD CONSTRAINT "unit_module_selections_pkey" PRIMARY KEY ("unit_id", "group_id");



ALTER TABLE ONLY "public"."unit_module_states"
    ADD CONSTRAINT "unit_module_states_pkey" PRIMARY KEY ("unit_id", "module_code");



ALTER TABLE ONLY "public"."unit_module_windows"
    ADD CONSTRAINT "unit_module_windows_pkey" PRIMARY KEY ("unit_id", "module_code");



ALTER TABLE ONLY "public"."unit_plans"
    ADD CONSTRAINT "unit_plans_pkey" PRIMARY KEY ("unit_id", "plan_id");



ALTER TABLE ONLY "public"."unit_proposal_reviews"
    ADD CONSTRAINT "unit_proposal_reviews_pkey" PRIMARY KEY ("proposal_id", "revision");



ALTER TABLE ONLY "public"."unit_proposal_versions"
    ADD CONSTRAINT "unit_proposal_versions_pkey" PRIMARY KEY ("proposal_id", "revision");



ALTER TABLE ONLY "public"."unit_proposals"
    ADD CONSTRAINT "unit_proposals_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."units"
    ADD CONSTRAINT "units_code_key" UNIQUE ("code");



ALTER TABLE ONLY "public"."units"
    ADD CONSTRAINT "units_pkey" PRIMARY KEY ("id");



CREATE INDEX "architect_assistance_events_request_idx" ON "public"."architect_assistance_events" USING "btree" ("request_id", "created_at");



CREATE INDEX "architect_assistance_queue_idx" ON "public"."architect_assistance_requests" USING "btree" ("architect_user_id", "status", "created_at");



CREATE INDEX "architect_authorization_events_unit_idx" ON "public"."architect_authorization_events" USING "btree" ("unit_id", "created_at" DESC, "id" DESC);



CREATE INDEX "architect_authorizations_architect_active_idx" ON "public"."architect_authorizations" USING "btree" ("architect_user_id", "unit_id") WHERE "active";



CREATE INDEX "base_plan_option_availability_option_idx" ON "public"."base_plan_option_availability" USING "btree" ("option_id", "base_plan_id");



CREATE INDEX "configuration_reviews_reviewer_idx" ON "public"."configuration_reviews" USING "btree" ("reviewer_user_id", "reviewed_at" DESC);



CREATE INDEX "customer_customizations_customer_idx" ON "public"."customer_customizations" USING "btree" ("customer_id", "unit_id");



CREATE INDEX "customer_customizations_option_idx" ON "public"."customer_customizations" USING "btree" ("option_id");



CREATE UNIQUE INDEX "customer_units_external_ref_unique" ON "public"."customer_units" USING "btree" ("external_ref") WHERE ("external_ref" IS NOT NULL);



CREATE UNIQUE INDEX "customer_units_one_active_customer" ON "public"."customer_units" USING "btree" ("unit_id") WHERE "active";



CREATE INDEX "customer_units_unit_idx" ON "public"."customer_units" USING "btree" ("unit_id");



CREATE UNIQUE INDEX "customer_users_one_active_account" ON "public"."customer_users" USING "btree" ("customer_id") WHERE "active";



CREATE UNIQUE INDEX "customer_users_one_active_customer" ON "public"."customer_users" USING "btree" ("user_id") WHERE "active";



CREATE INDEX "customer_users_user_idx" ON "public"."customer_users" USING "btree" ("user_id");



CREATE UNIQUE INDEX "customers_external_ref_unique" ON "public"."customers" USING "btree" ("external_ref") WHERE ("external_ref" IS NOT NULL);



CREATE INDEX "customization_groups_module_idx" ON "public"."customization_groups" USING "btree" ("module_code");



CREATE INDEX "customization_history_actor_idx" ON "public"."customization_history" USING "btree" ("actor_customer_id", "created_at" DESC);



CREATE INDEX "customization_options_group_idx" ON "public"."customization_options" USING "btree" ("group_id", "sort_order");



CREATE UNIQUE INDEX "import_batches_source_hash_unique" ON "public"."import_batches" USING "btree" ("source_hash");



CREATE INDEX "import_rows_batch_id_index" ON "public"."import_rows" USING "btree" ("batch_id");



CREATE INDEX "import_rows_customer_external_ref_index" ON "public"."import_rows" USING "btree" ("customer_external_ref");



CREATE INDEX "import_rows_link_external_ref_index" ON "public"."import_rows" USING "btree" ("link_external_ref");



CREATE INDEX "import_rows_unit_external_ref_index" ON "public"."import_rows" USING "btree" ("unit_external_ref");



CREATE UNIQUE INDEX "one_open_architect_assistance_per_unit" ON "public"."architect_assistance_requests" USING "btree" ("unit_id") WHERE ("status" = ANY (ARRAY['requested'::"text", 'in_progress'::"text"]));



CREATE INDEX "option_compatibilities_option_idx" ON "public"."option_compatibilities" USING "btree" ("option_id", "plan_id");



CREATE INDEX "staff_unit_assignments_unit_idx" ON "public"."staff_unit_assignments" USING "btree" ("unit_id", "user_id") WHERE "active";



CREATE INDEX "unit_activity_events_unit_time" ON "public"."unit_activity_events" USING "btree" ("unit_id", "created_at" DESC, "id" DESC);



CREATE INDEX "unit_base_plan_assignments_plan_idx" ON "public"."unit_base_plan_assignments" USING "btree" ("base_plan_id");



CREATE INDEX "unit_module_history_actor_idx" ON "public"."unit_module_history" USING "btree" ("actor_user_id", "created_at" DESC);



CREATE INDEX "unit_module_selections_module_idx" ON "public"."unit_module_selections" USING "btree" ("unit_id", "module_code");



CREATE INDEX "unit_module_windows_module_idx" ON "public"."unit_module_windows" USING "btree" ("module_code", "closes_at");



CREATE INDEX "unit_plans_plan_idx" ON "public"."unit_plans" USING "btree" ("plan_id", "unit_id");



CREATE INDEX "unit_proposal_versions_actor_idx" ON "public"."unit_proposal_versions" USING "btree" ("actor_user_id", "created_at" DESC);



CREATE UNIQUE INDEX "unit_proposals_one_open_cycle_per_unit" ON "public"."unit_proposals" USING "btree" ("unit_id") WHERE ("status" = 'open'::"text");



CREATE UNIQUE INDEX "unit_proposals_unit_cycle_key" ON "public"."unit_proposals" USING "btree" ("unit_id", "cycle_number");



CREATE UNIQUE INDEX "units_external_ref_unique" ON "public"."units" USING "btree" ("external_ref") WHERE ("external_ref" IS NOT NULL);



CREATE UNIQUE INDEX "units_location_unique" ON "public"."units" USING "btree" ("tower_code", "floor_number", "termination_code") WHERE (("tower_code" IS NOT NULL) AND ("floor_number" IS NOT NULL) AND ("termination_code" IS NOT NULL));



CREATE OR REPLACE TRIGGER "clear_completed_ui_draft_before_write" BEFORE INSERT OR UPDATE ON "public"."unit_configuration_state" FOR EACH ROW EXECUTE FUNCTION "public"."clear_completed_ui_draft"();



CREATE OR REPLACE TRIGGER "draft_audit" AFTER INSERT OR UPDATE ON "public"."unit_drafts" FOR EACH ROW EXECUTE FUNCTION "public"."record_draft_history"();



CREATE OR REPLACE TRIGGER "guard_legacy_architect_draft_before_write" BEFORE INSERT OR UPDATE ON "public"."unit_drafts" FOR EACH ROW EXECUTE FUNCTION "public"."guard_legacy_architect_draft"();



CREATE OR REPLACE TRIGGER "guard_open_proposal_edit_limit" BEFORE INSERT ON "public"."unit_module_history" FOR EACH ROW EXECUTE FUNCTION "public"."guard_open_proposal_edit_limit"();



CREATE OR REPLACE TRIGGER "guard_submitted_base_plan_assignment" BEFORE DELETE OR UPDATE ON "public"."unit_base_plan_assignments" FOR EACH ROW EXECUTE FUNCTION "public"."guard_submitted_base_plan_assignment"();



CREATE OR REPLACE TRIGGER "guard_unit_final_deadline_on_choices" BEFORE INSERT ON "public"."unit_module_history" FOR EACH ROW EXECUTE FUNCTION "public"."guard_unit_customization_deadline"();



CREATE OR REPLACE TRIGGER "guard_unit_final_deadline_on_submission" BEFORE INSERT ON "public"."unit_proposal_versions" FOR EACH ROW EXECUTE FUNCTION "public"."guard_unit_customization_deadline"();



CREATE OR REPLACE TRIGGER "record_customization_actor_before_insert" BEFORE INSERT ON "public"."customer_customizations" FOR EACH ROW EXECUTE FUNCTION "public"."record_customization_actor"();



ALTER TABLE ONLY "public"."architect_assistance_events"
    ADD CONSTRAINT "architect_assistance_events_actor_user_id_fkey" FOREIGN KEY ("actor_user_id") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."architect_assistance_events"
    ADD CONSTRAINT "architect_assistance_events_request_id_fkey" FOREIGN KEY ("request_id") REFERENCES "public"."architect_assistance_requests"("id");



ALTER TABLE ONLY "public"."architect_assistance_requests"
    ADD CONSTRAINT "architect_assistance_requests_architect_user_id_fkey" FOREIGN KEY ("architect_user_id") REFERENCES "public"."staff_users"("user_id");



ALTER TABLE ONLY "public"."architect_assistance_requests"
    ADD CONSTRAINT "architect_assistance_requests_requester_customer_id_unit_i_fkey" FOREIGN KEY ("requester_customer_id", "unit_id") REFERENCES "public"."customer_units"("customer_id", "unit_id");



ALTER TABLE ONLY "public"."architect_assistance_requests"
    ADD CONSTRAINT "architect_assistance_requests_requester_user_id_fkey" FOREIGN KEY ("requester_user_id") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."architect_assistance_requests"
    ADD CONSTRAINT "architect_assistance_requests_unit_id_fkey" FOREIGN KEY ("unit_id") REFERENCES "public"."units"("id");



ALTER TABLE ONLY "public"."architect_authorization_events"
    ADD CONSTRAINT "architect_authorization_events_actor_customer_id_unit_id_fkey" FOREIGN KEY ("actor_customer_id", "unit_id") REFERENCES "public"."customer_units"("customer_id", "unit_id");



ALTER TABLE ONLY "public"."architect_authorization_events"
    ADD CONSTRAINT "architect_authorization_events_actor_user_id_fkey" FOREIGN KEY ("actor_user_id") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."architect_authorization_events"
    ADD CONSTRAINT "architect_authorization_events_architect_user_id_fkey" FOREIGN KEY ("architect_user_id") REFERENCES "public"."staff_users"("user_id");



ALTER TABLE ONLY "public"."architect_authorization_events"
    ADD CONSTRAINT "architect_authorization_events_unit_id_fkey" FOREIGN KEY ("unit_id") REFERENCES "public"."units"("id");



ALTER TABLE ONLY "public"."architect_authorizations"
    ADD CONSTRAINT "architect_authorizations_architect_user_id_fkey" FOREIGN KEY ("architect_user_id") REFERENCES "public"."staff_users"("user_id");



ALTER TABLE ONLY "public"."architect_authorizations"
    ADD CONSTRAINT "architect_authorizations_granted_by_customer_id_unit_id_fkey" FOREIGN KEY ("granted_by_customer_id", "unit_id") REFERENCES "public"."customer_units"("customer_id", "unit_id");



ALTER TABLE ONLY "public"."architect_authorizations"
    ADD CONSTRAINT "architect_authorizations_granted_by_user_id_fkey" FOREIGN KEY ("granted_by_user_id") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."architect_authorizations"
    ADD CONSTRAINT "architect_authorizations_revoked_by_user_id_fkey" FOREIGN KEY ("revoked_by_user_id") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."architect_authorizations"
    ADD CONSTRAINT "architect_authorizations_unit_id_fkey" FOREIGN KEY ("unit_id") REFERENCES "public"."units"("id");



ALTER TABLE ONLY "public"."base_plan_option_availability"
    ADD CONSTRAINT "base_plan_option_availability_base_plan_id_fkey" FOREIGN KEY ("base_plan_id") REFERENCES "public"."base_plans"("id");



ALTER TABLE ONLY "public"."base_plan_option_availability"
    ADD CONSTRAINT "base_plan_option_availability_option_id_fkey" FOREIGN KEY ("option_id") REFERENCES "public"."customization_options"("id");



ALTER TABLE ONLY "public"."base_plan_option_defaults"
    ADD CONSTRAINT "base_plan_option_defaults_base_plan_id_option_id_fkey" FOREIGN KEY ("base_plan_id", "option_id") REFERENCES "public"."base_plan_option_availability"("base_plan_id", "option_id");



ALTER TABLE ONLY "public"."base_plan_option_defaults"
    ADD CONSTRAINT "base_plan_option_defaults_group_id_option_id_fkey" FOREIGN KEY ("group_id", "option_id") REFERENCES "public"."customization_options"("group_id", "id");



ALTER TABLE ONLY "public"."base_plan_option_exclusions"
    ADD CONSTRAINT "base_plan_option_exclusions_base_plan_id_first_option_id_fkey" FOREIGN KEY ("base_plan_id", "first_option_id") REFERENCES "public"."base_plan_option_availability"("base_plan_id", "option_id");



ALTER TABLE ONLY "public"."base_plan_option_exclusions"
    ADD CONSTRAINT "base_plan_option_exclusions_base_plan_id_fkey" FOREIGN KEY ("base_plan_id") REFERENCES "public"."base_plans"("id");



ALTER TABLE ONLY "public"."base_plan_option_exclusions"
    ADD CONSTRAINT "base_plan_option_exclusions_base_plan_id_second_option_id_fkey" FOREIGN KEY ("base_plan_id", "second_option_id") REFERENCES "public"."base_plan_option_availability"("base_plan_id", "option_id");



ALTER TABLE ONLY "public"."base_plan_option_requirements"
    ADD CONSTRAINT "base_plan_option_requirements_base_plan_id_option_id_fkey" FOREIGN KEY ("base_plan_id", "option_id") REFERENCES "public"."base_plan_option_availability"("base_plan_id", "option_id");



ALTER TABLE ONLY "public"."base_plan_option_requirements"
    ADD CONSTRAINT "base_plan_option_requirements_base_plan_id_required_option_fkey" FOREIGN KEY ("base_plan_id", "required_option_id") REFERENCES "public"."base_plan_option_availability"("base_plan_id", "option_id");



ALTER TABLE ONLY "public"."configuration_reviews"
    ADD CONSTRAINT "configuration_reviews_reviewer_user_id_fkey" FOREIGN KEY ("reviewer_user_id") REFERENCES "public"."staff_users"("user_id");



ALTER TABLE ONLY "public"."configuration_reviews"
    ADD CONSTRAINT "configuration_reviews_unit_id_revision_fkey" FOREIGN KEY ("unit_id", "revision") REFERENCES "public"."customization_history"("unit_id", "revision");



ALTER TABLE ONLY "public"."customer_customizations"
    ADD CONSTRAINT "customer_customizations_customer_id_unit_id_fkey" FOREIGN KEY ("customer_id", "unit_id") REFERENCES "public"."customer_units"("customer_id", "unit_id");



ALTER TABLE ONLY "public"."customer_customizations"
    ADD CONSTRAINT "customer_customizations_group_id_fkey" FOREIGN KEY ("group_id") REFERENCES "public"."customization_groups"("id");



ALTER TABLE ONLY "public"."customer_customizations"
    ADD CONSTRAINT "customer_customizations_group_id_option_id_fkey" FOREIGN KEY ("group_id", "option_id") REFERENCES "public"."customization_options"("group_id", "id");



ALTER TABLE ONLY "public"."customer_customizations"
    ADD CONSTRAINT "customer_customizations_plan_id_option_id_fkey" FOREIGN KEY ("plan_id", "option_id") REFERENCES "public"."option_compatibilities"("plan_id", "option_id") DEFERRABLE INITIALLY DEFERRED;



ALTER TABLE ONLY "public"."customer_customizations"
    ADD CONSTRAINT "customer_customizations_unit_id_plan_id_fkey" FOREIGN KEY ("unit_id", "plan_id") REFERENCES "public"."unit_configuration_state"("unit_id", "plan_id") DEFERRABLE INITIALLY DEFERRED;



ALTER TABLE ONLY "public"."customer_customizations"
    ADD CONSTRAINT "customer_customizations_updated_by_fkey" FOREIGN KEY ("updated_by") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."customer_units"
    ADD CONSTRAINT "customer_units_customer_id_fkey" FOREIGN KEY ("customer_id") REFERENCES "public"."customers"("id");



ALTER TABLE ONLY "public"."customer_units"
    ADD CONSTRAINT "customer_units_unit_id_fkey" FOREIGN KEY ("unit_id") REFERENCES "public"."units"("id");



ALTER TABLE ONLY "public"."customer_users"
    ADD CONSTRAINT "customer_users_customer_id_fkey" FOREIGN KEY ("customer_id") REFERENCES "public"."customers"("id");



ALTER TABLE ONLY "public"."customer_users"
    ADD CONSTRAINT "customer_users_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."customization_groups"
    ADD CONSTRAINT "customization_groups_module_code_fkey" FOREIGN KEY ("module_code") REFERENCES "public"."customization_modules"("code");



ALTER TABLE ONLY "public"."customization_history"
    ADD CONSTRAINT "customization_history_actor_customer_id_unit_id_fkey" FOREIGN KEY ("actor_customer_id", "unit_id") REFERENCES "public"."customer_units"("customer_id", "unit_id");



ALTER TABLE ONLY "public"."customization_history"
    ADD CONSTRAINT "customization_history_actor_user_id_fkey" FOREIGN KEY ("actor_user_id") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."customization_history"
    ADD CONSTRAINT "customization_history_unit_id_fkey" FOREIGN KEY ("unit_id") REFERENCES "public"."units"("id");



ALTER TABLE ONLY "public"."customization_history"
    ADD CONSTRAINT "customization_history_unit_id_plan_id_fkey" FOREIGN KEY ("unit_id", "plan_id") REFERENCES "public"."unit_plans"("unit_id", "plan_id");



ALTER TABLE ONLY "public"."customization_options"
    ADD CONSTRAINT "customization_options_group_id_fkey" FOREIGN KEY ("group_id") REFERENCES "public"."customization_groups"("id");



ALTER TABLE ONLY "public"."customization_windows"
    ADD CONSTRAINT "customization_windows_unit_id_fkey" FOREIGN KEY ("unit_id") REFERENCES "public"."units"("id");



ALTER TABLE ONLY "public"."deadline_notifications"
    ADD CONSTRAINT "deadline_notifications_customer_id_fkey" FOREIGN KEY ("customer_id") REFERENCES "public"."customers"("id");



ALTER TABLE ONLY "public"."deadline_notifications"
    ADD CONSTRAINT "deadline_notifications_unit_id_fkey" FOREIGN KEY ("unit_id") REFERENCES "public"."units"("id");



ALTER TABLE ONLY "public"."draft_history"
    ADD CONSTRAINT "draft_history_actor_id_fkey" FOREIGN KEY ("actor_id") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."draft_history"
    ADD CONSTRAINT "draft_history_unit_id_fkey" FOREIGN KEY ("unit_id") REFERENCES "public"."units"("id");



ALTER TABLE ONLY "public"."import_rows"
    ADD CONSTRAINT "import_rows_batch_id_fkey" FOREIGN KEY ("batch_id") REFERENCES "public"."import_batches"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."option_compatibilities"
    ADD CONSTRAINT "option_compatibilities_option_id_fkey" FOREIGN KEY ("option_id") REFERENCES "public"."customization_options"("id");



ALTER TABLE ONLY "public"."option_compatibilities"
    ADD CONSTRAINT "option_compatibilities_plan_id_fkey" FOREIGN KEY ("plan_id") REFERENCES "public"."plans"("id");



ALTER TABLE ONLY "public"."plan_features"
    ADD CONSTRAINT "plan_features_plan_id_fkey" FOREIGN KEY ("plan_id") REFERENCES "public"."plans"("id");



ALTER TABLE ONLY "public"."staff_unit_assignments"
    ADD CONSTRAINT "staff_unit_assignments_unit_id_fkey" FOREIGN KEY ("unit_id") REFERENCES "public"."units"("id");



ALTER TABLE ONLY "public"."staff_unit_assignments"
    ADD CONSTRAINT "staff_unit_assignments_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."staff_users"("user_id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."staff_users"
    ADD CONSTRAINT "staff_users_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."unit_activity_events"
    ADD CONSTRAINT "unit_activity_events_actor_user_id_fkey" FOREIGN KEY ("actor_user_id") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."unit_activity_events"
    ADD CONSTRAINT "unit_activity_events_unit_id_fkey" FOREIGN KEY ("unit_id") REFERENCES "public"."units"("id");



ALTER TABLE ONLY "public"."unit_base_plan_assignments"
    ADD CONSTRAINT "unit_base_plan_assignments_assigned_by_fkey" FOREIGN KEY ("assigned_by") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."unit_base_plan_assignments"
    ADD CONSTRAINT "unit_base_plan_assignments_base_plan_id_fkey" FOREIGN KEY ("base_plan_id") REFERENCES "public"."base_plans"("id");



ALTER TABLE ONLY "public"."unit_base_plan_assignments"
    ADD CONSTRAINT "unit_base_plan_assignments_unit_id_fkey" FOREIGN KEY ("unit_id") REFERENCES "public"."units"("id");



ALTER TABLE ONLY "public"."unit_configuration_state"
    ADD CONSTRAINT "unit_configuration_state_unit_id_fkey" FOREIGN KEY ("unit_id") REFERENCES "public"."units"("id");



ALTER TABLE ONLY "public"."unit_configuration_state"
    ADD CONSTRAINT "unit_configuration_state_unit_id_plan_id_fkey" FOREIGN KEY ("unit_id", "plan_id") REFERENCES "public"."unit_plans"("unit_id", "plan_id");



ALTER TABLE ONLY "public"."unit_configuration_state"
    ADD CONSTRAINT "unit_configuration_state_updated_by_fkey" FOREIGN KEY ("updated_by") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."unit_drafts"
    ADD CONSTRAINT "unit_drafts_unit_id_fkey" FOREIGN KEY ("unit_id") REFERENCES "public"."units"("id");



ALTER TABLE ONLY "public"."unit_drafts"
    ADD CONSTRAINT "unit_drafts_updated_by_fkey" FOREIGN KEY ("updated_by") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."unit_module_history"
    ADD CONSTRAINT "unit_module_history_actor_customer_id_unit_id_fkey" FOREIGN KEY ("actor_customer_id", "unit_id") REFERENCES "public"."customer_units"("customer_id", "unit_id");



ALTER TABLE ONLY "public"."unit_module_history"
    ADD CONSTRAINT "unit_module_history_actor_user_id_fkey" FOREIGN KEY ("actor_user_id") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."unit_module_history"
    ADD CONSTRAINT "unit_module_history_base_plan_id_fkey" FOREIGN KEY ("base_plan_id") REFERENCES "public"."base_plans"("id");



ALTER TABLE ONLY "public"."unit_module_history"
    ADD CONSTRAINT "unit_module_history_unit_id_module_code_fkey" FOREIGN KEY ("unit_id", "module_code") REFERENCES "public"."unit_module_states"("unit_id", "module_code");



ALTER TABLE ONLY "public"."unit_module_selections"
    ADD CONSTRAINT "unit_module_selections_group_id_fkey" FOREIGN KEY ("group_id") REFERENCES "public"."customization_groups"("id");



ALTER TABLE ONLY "public"."unit_module_selections"
    ADD CONSTRAINT "unit_module_selections_group_id_option_id_fkey" FOREIGN KEY ("group_id", "option_id") REFERENCES "public"."customization_options"("group_id", "id");



ALTER TABLE ONLY "public"."unit_module_selections"
    ADD CONSTRAINT "unit_module_selections_unit_id_module_code_fkey" FOREIGN KEY ("unit_id", "module_code") REFERENCES "public"."unit_module_states"("unit_id", "module_code");



ALTER TABLE ONLY "public"."unit_module_selections"
    ADD CONSTRAINT "unit_module_selections_updated_by_fkey" FOREIGN KEY ("updated_by") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."unit_module_states"
    ADD CONSTRAINT "unit_module_states_module_code_fkey" FOREIGN KEY ("module_code") REFERENCES "public"."customization_modules"("code");



ALTER TABLE ONLY "public"."unit_module_states"
    ADD CONSTRAINT "unit_module_states_unit_id_fkey" FOREIGN KEY ("unit_id") REFERENCES "public"."units"("id");



ALTER TABLE ONLY "public"."unit_module_states"
    ADD CONSTRAINT "unit_module_states_updated_by_fkey" FOREIGN KEY ("updated_by") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."unit_module_windows"
    ADD CONSTRAINT "unit_module_windows_module_code_fkey" FOREIGN KEY ("module_code") REFERENCES "public"."customization_modules"("code");



ALTER TABLE ONLY "public"."unit_module_windows"
    ADD CONSTRAINT "unit_module_windows_unit_id_fkey" FOREIGN KEY ("unit_id") REFERENCES "public"."units"("id");



ALTER TABLE ONLY "public"."unit_plans"
    ADD CONSTRAINT "unit_plans_plan_id_fkey" FOREIGN KEY ("plan_id") REFERENCES "public"."plans"("id");



ALTER TABLE ONLY "public"."unit_plans"
    ADD CONSTRAINT "unit_plans_unit_id_fkey" FOREIGN KEY ("unit_id") REFERENCES "public"."units"("id");



ALTER TABLE ONLY "public"."unit_proposal_reviews"
    ADD CONSTRAINT "unit_proposal_reviews_proposal_id_revision_fkey" FOREIGN KEY ("proposal_id", "revision") REFERENCES "public"."unit_proposal_versions"("proposal_id", "revision");



ALTER TABLE ONLY "public"."unit_proposal_reviews"
    ADD CONSTRAINT "unit_proposal_reviews_reviewer_user_id_fkey" FOREIGN KEY ("reviewer_user_id") REFERENCES "public"."staff_users"("user_id");



ALTER TABLE ONLY "public"."unit_proposal_versions"
    ADD CONSTRAINT "unit_proposal_versions_actor_user_id_fkey" FOREIGN KEY ("actor_user_id") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."unit_proposal_versions"
    ADD CONSTRAINT "unit_proposal_versions_base_plan_id_fkey" FOREIGN KEY ("base_plan_id") REFERENCES "public"."base_plans"("id");



ALTER TABLE ONLY "public"."unit_proposal_versions"
    ADD CONSTRAINT "unit_proposal_versions_proposal_id_fkey" FOREIGN KEY ("proposal_id") REFERENCES "public"."unit_proposals"("id");



ALTER TABLE ONLY "public"."unit_proposal_versions"
    ADD CONSTRAINT "unit_proposal_versions_source_module_code_fkey" FOREIGN KEY ("source_module_code") REFERENCES "public"."customization_modules"("code");



ALTER TABLE ONLY "public"."unit_proposals"
    ADD CONSTRAINT "unit_proposals_submitted_by_customer_id_unit_id_fkey" FOREIGN KEY ("submitted_by_customer_id", "unit_id") REFERENCES "public"."customer_units"("customer_id", "unit_id");



ALTER TABLE ONLY "public"."unit_proposals"
    ADD CONSTRAINT "unit_proposals_submitted_by_user_id_fkey" FOREIGN KEY ("submitted_by_user_id") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."unit_proposals"
    ADD CONSTRAINT "unit_proposals_unit_id_fkey" FOREIGN KEY ("unit_id") REFERENCES "public"."units"("id");



CREATE POLICY "admin_customer_accounts" ON "public"."customer_users" FOR SELECT TO "authenticated" USING ((( SELECT "public"."current_staff_role"() AS "current_staff_role") = 'admin'::"text"));



CREATE POLICY "admin_deadline_notifications" ON "public"."deadline_notifications" FOR SELECT TO "authenticated" USING ((( SELECT "public"."current_staff_role"() AS "current_staff_role") = 'admin'::"text"));



ALTER TABLE "public"."architect_assistance_events" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."architect_assistance_requests" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."architect_authorization_events" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."architect_authorizations" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."base_plan_option_availability" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."base_plan_option_defaults" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."base_plan_option_exclusions" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."base_plan_option_requirements" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."base_plans" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."configuration_reviews" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."customer_customizations" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."customer_units" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."customer_users" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."customers" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."customization_groups" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."customization_history" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."customization_modules" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."customization_options" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."customization_windows" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."deadline_notifications" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."draft_history" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."import_batches" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."import_rows" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."option_compatibilities" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "own_customer_links" ON "public"."customer_users" FOR SELECT TO "authenticated" USING ((("user_id" = ( SELECT "auth"."uid"() AS "uid")) AND "active"));



CREATE POLICY "own_customers" ON "public"."customers" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."customer_users" "cu"
  WHERE ("cu"."customer_id" = "customers"."id"))));



CREATE POLICY "own_drafts" ON "public"."unit_drafts" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."units" "u"
  WHERE ("u"."id" = "unit_drafts"."unit_id"))));



CREATE POLICY "own_staff_role" ON "public"."staff_users" FOR SELECT TO "authenticated" USING (("user_id" = ( SELECT "auth"."uid"() AS "uid")));



CREATE POLICY "own_unit_links" ON "public"."customer_units" FOR SELECT TO "authenticated" USING (("active" AND ("ownership_role" = 'owner'::"text") AND (EXISTS ( SELECT 1
   FROM "public"."customer_users" "usr"
  WHERE (("usr"."customer_id" = "customer_units"."customer_id") AND "usr"."active" AND ("usr"."user_id" = ( SELECT "auth"."uid"() AS "uid")))))));



CREATE POLICY "own_units" ON "public"."units" FOR SELECT TO "authenticated" USING ("public"."customer_can_access_unit"("id"));



ALTER TABLE "public"."plan_features" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."plans" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "readable_architect_assistance_events" ON "public"."architect_assistance_events" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."architect_assistance_requests" "r"
  WHERE ("r"."id" = "architect_assistance_events"."request_id"))));



CREATE POLICY "readable_architect_assistance_requests" ON "public"."architect_assistance_requests" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."units" "u"
  WHERE ("u"."id" = "architect_assistance_requests"."unit_id"))));



CREATE POLICY "readable_architect_authorization_events" ON "public"."architect_authorization_events" FOR SELECT TO "authenticated" USING ((("architect_user_id" = ( SELECT "auth"."uid"() AS "uid")) OR (( SELECT "public"."current_staff_role"() AS "current_staff_role") = 'admin'::"text") OR (EXISTS ( SELECT 1
   FROM (("public"."customer_units" "cu"
     JOIN "public"."customer_users" "usr" ON ((("usr"."customer_id" = "cu"."customer_id") AND "usr"."active")))
     JOIN "public"."units" "u" ON ((("u"."id" = "cu"."unit_id") AND "u"."active")))
  WHERE (("cu"."unit_id" = "architect_authorization_events"."unit_id") AND "cu"."active" AND ("usr"."user_id" = ( SELECT "auth"."uid"() AS "uid")))))));



CREATE POLICY "readable_architect_authorizations" ON "public"."architect_authorizations" FOR SELECT TO "authenticated" USING ((("architect_user_id" = ( SELECT "auth"."uid"() AS "uid")) OR (( SELECT "public"."current_staff_role"() AS "current_staff_role") = 'admin'::"text") OR (EXISTS ( SELECT 1
   FROM (("public"."customer_units" "cu"
     JOIN "public"."customer_users" "usr" ON ((("usr"."customer_id" = "cu"."customer_id") AND "usr"."active")))
     JOIN "public"."units" "u" ON ((("u"."id" = "cu"."unit_id") AND "u"."active")))
  WHERE (("cu"."unit_id" = "architect_authorizations"."unit_id") AND "cu"."active" AND ("usr"."user_id" = ( SELECT "auth"."uid"() AS "uid")))))));



CREATE POLICY "readable_base_plan_assignments" ON "public"."unit_base_plan_assignments" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."units" "u"
  WHERE ("u"."id" = "unit_base_plan_assignments"."unit_id"))));



CREATE POLICY "readable_base_plan_module_groups" ON "public"."customization_groups" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM ((("public"."customization_options" "o"
     JOIN "public"."base_plan_option_availability" "a" ON (("a"."option_id" = "o"."id")))
     JOIN "public"."unit_base_plan_assignments" "assignment" ON (("assignment"."base_plan_id" = "a"."base_plan_id")))
     JOIN "public"."units" "u" ON (("u"."id" = "assignment"."unit_id")))
  WHERE ("o"."group_id" = "customization_groups"."id"))));



CREATE POLICY "readable_base_plan_module_options" ON "public"."customization_options" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM (("public"."base_plan_option_availability" "a"
     JOIN "public"."unit_base_plan_assignments" "assignment" ON (("assignment"."base_plan_id" = "a"."base_plan_id")))
     JOIN "public"."units" "u" ON (("u"."id" = "assignment"."unit_id")))
  WHERE ("a"."option_id" = "customization_options"."id"))));



CREATE POLICY "readable_base_plan_option_availability" ON "public"."base_plan_option_availability" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."base_plans" "p"
  WHERE ("p"."id" = "base_plan_option_availability"."base_plan_id"))));



CREATE POLICY "readable_base_plan_option_exclusions" ON "public"."base_plan_option_exclusions" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."base_plans" "p"
  WHERE ("p"."id" = "base_plan_option_exclusions"."base_plan_id"))));



CREATE POLICY "readable_base_plans" ON "public"."base_plans" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."unit_base_plan_assignments" "a"
  WHERE ("a"."base_plan_id" = "base_plans"."id"))));



CREATE POLICY "readable_compatibilities" ON "public"."option_compatibilities" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."unit_plans" "up"
  WHERE ("up"."plan_id" = "option_compatibilities"."plan_id"))));



CREATE POLICY "readable_configuration" ON "public"."unit_configuration_state" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."units" "u"
  WHERE ("u"."id" = "unit_configuration_state"."unit_id"))));



CREATE POLICY "readable_configuration_reviews" ON "public"."configuration_reviews" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."units" "u"
  WHERE ("u"."id" = "configuration_reviews"."unit_id"))));



CREATE POLICY "readable_customization_history" ON "public"."customization_history" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."units" "u"
  WHERE ("u"."id" = "customization_history"."unit_id"))));



CREATE POLICY "readable_customizations" ON "public"."customer_customizations" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."units" "u"
  WHERE ("u"."id" = "customer_customizations"."unit_id"))));



CREATE POLICY "readable_groups" ON "public"."customization_groups" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."customization_options" "o"
  WHERE ("o"."group_id" = "customization_groups"."id"))));



CREATE POLICY "readable_modules" ON "public"."customization_modules" FOR SELECT TO "authenticated" USING ("active");



CREATE POLICY "readable_option_defaults" ON "public"."base_plan_option_defaults" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."base_plans" "p"
  WHERE ("p"."id" = "base_plan_option_defaults"."base_plan_id"))));



CREATE POLICY "readable_option_requirements" ON "public"."base_plan_option_requirements" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."base_plans" "p"
  WHERE ("p"."id" = "base_plan_option_requirements"."base_plan_id"))));



CREATE POLICY "readable_options" ON "public"."customization_options" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."option_compatibilities" "oc"
  WHERE ("oc"."option_id" = "customization_options"."id"))));



CREATE POLICY "readable_plan_features" ON "public"."plan_features" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."plans" "p"
  WHERE ("p"."id" = "plan_features"."plan_id"))));



CREATE POLICY "readable_plans" ON "public"."plans" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."unit_plans" "up"
  WHERE ("up"."plan_id" = "plans"."id"))));



CREATE POLICY "readable_staff_assignments" ON "public"."staff_unit_assignments" FOR SELECT TO "authenticated" USING (((( SELECT "public"."current_staff_role"() AS "current_staff_role") = 'admin'::"text") OR (("user_id" = ( SELECT "auth"."uid"() AS "uid")) AND (( SELECT "public"."current_staff_role"() AS "current_staff_role") = 'architect'::"text"))));



CREATE POLICY "readable_unit_module_history" ON "public"."unit_module_history" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."units" "u"
  WHERE ("u"."id" = "unit_module_history"."unit_id"))));



CREATE POLICY "readable_unit_module_selections" ON "public"."unit_module_selections" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."units" "u"
  WHERE ("u"."id" = "unit_module_selections"."unit_id"))));



CREATE POLICY "readable_unit_module_states" ON "public"."unit_module_states" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."units" "u"
  WHERE ("u"."id" = "unit_module_states"."unit_id"))));



CREATE POLICY "readable_unit_module_windows" ON "public"."unit_module_windows" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."units" "u"
  WHERE ("u"."id" = "unit_module_windows"."unit_id"))));



CREATE POLICY "readable_unit_plans" ON "public"."unit_plans" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."units" "u"
  WHERE ("u"."id" = "unit_plans"."unit_id"))));



CREATE POLICY "readable_unit_proposal_reviews" ON "public"."unit_proposal_reviews" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."unit_proposals" "p"
  WHERE ("p"."id" = "unit_proposal_reviews"."proposal_id"))));



CREATE POLICY "readable_unit_proposal_versions" ON "public"."unit_proposal_versions" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."unit_proposals" "p"
  WHERE ("p"."id" = "unit_proposal_versions"."proposal_id"))));



CREATE POLICY "readable_unit_proposals" ON "public"."unit_proposals" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."units" "u"
  WHERE ("u"."id" = "unit_proposals"."unit_id"))));



CREATE POLICY "readable_windows" ON "public"."customization_windows" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."units" "u"
  WHERE ("u"."id" = "customization_windows"."unit_id"))));



CREATE POLICY "staff_activity_events" ON "public"."unit_activity_events" FOR SELECT TO "authenticated" USING ((( SELECT "public"."current_staff_role"() AS "current_staff_role") = ANY (ARRAY['architect'::"text", 'admin'::"text"])));



CREATE POLICY "staff_customer_links" ON "public"."customer_units" FOR SELECT TO "authenticated" USING ((( SELECT "public"."current_staff_role"() AS "current_staff_role") = ANY (ARRAY['architect'::"text", 'admin'::"text"])));



CREATE POLICY "staff_customers" ON "public"."customers" FOR SELECT TO "authenticated" USING ((( SELECT "public"."current_staff_role"() AS "current_staff_role") = ANY (ARRAY['architect'::"text", 'admin'::"text"])));



CREATE POLICY "staff_drafts" ON "public"."unit_drafts" FOR SELECT TO "authenticated" USING ("public"."staff_can_access_unit"("unit_id"));



CREATE POLICY "staff_history" ON "public"."draft_history" FOR SELECT TO "authenticated" USING ("public"."staff_can_access_unit"("unit_id"));



ALTER TABLE "public"."staff_unit_assignments" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "staff_units" ON "public"."units" FOR SELECT TO "authenticated" USING ("public"."staff_can_access_unit"("id"));



ALTER TABLE "public"."staff_users" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."unit_activity_events" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."unit_base_plan_assignments" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."unit_configuration_state" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."unit_drafts" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."unit_module_history" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."unit_module_selections" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."unit_module_states" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."unit_module_windows" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."unit_plans" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."unit_proposal_reviews" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."unit_proposal_versions" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."unit_proposals" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."units" ENABLE ROW LEVEL SECURITY;


GRANT USAGE ON SCHEMA "public" TO "postgres";
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT USAGE ON SCHEMA "public" TO "service_role";



GRANT ALL ON TABLE "public"."architect_assistance_requests" TO "service_role";
GRANT SELECT ON TABLE "public"."architect_assistance_requests" TO "authenticated";



REVOKE ALL ON FUNCTION "public"."accept_architect_assistance"("p_request_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."accept_architect_assistance"("p_request_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."apply_import_batch"("p_batch_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."apply_import_batch"("p_batch_id" "uuid") TO "service_role";



GRANT ALL ON TABLE "public"."import_batches" TO "service_role";



REVOKE ALL ON FUNCTION "public"."approve_import_batch"("p_batch_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."approve_import_batch"("p_batch_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."cancel_architect_assistance"("p_request_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."cancel_architect_assistance"("p_request_id" "uuid") TO "service_role";



GRANT ALL ON TABLE "public"."deadline_notifications" TO "service_role";
GRANT SELECT ON TABLE "public"."deadline_notifications" TO "authenticated";



REVOKE ALL ON FUNCTION "public"."claim_deadline_notifications"("p_limit" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."claim_deadline_notifications"("p_limit" integer) TO "service_role";



REVOKE ALL ON FUNCTION "public"."clear_completed_ui_draft"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."clear_completed_ui_draft"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."current_actor_name"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."current_actor_name"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."current_architect_authorization"("p_unit_id" "uuid", "p_architect_user_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."current_architect_authorization"("p_unit_id" "uuid", "p_architect_user_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."current_staff_role"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."current_staff_role"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."current_staff_role"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."customer_can_access_unit"("p_unit_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."customer_can_access_unit"("p_unit_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."customer_can_access_unit"("p_unit_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."find_customer_auth_user"("p_email" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."find_customer_auth_user"("p_email" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."find_customer_auth_user"("p_email" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."finish_deadline_notification"("p_id" "uuid", "p_success" boolean, "p_error" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."finish_deadline_notification"("p_id" "uuid", "p_success" boolean, "p_error" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."guard_legacy_architect_draft"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."guard_legacy_architect_draft"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."guard_open_proposal_edit_limit"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."guard_open_proposal_edit_limit"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."guard_submitted_base_plan_assignment"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."guard_submitted_base_plan_assignment"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."guard_unit_customization_deadline"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."guard_unit_customization_deadline"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."list_customer_unit_cards"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."list_customer_unit_cards"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."list_customer_unit_cards"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."list_unit_architects"("p_unit_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."list_unit_architects"("p_unit_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."manage_unit"("p_unit_id" "uuid", "p_customer_id" "uuid", "p_closes_at" timestamp with time zone, "p_module_deadlines" "jsonb") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."manage_unit"("p_unit_id" "uuid", "p_customer_id" "uuid", "p_closes_at" timestamp with time zone, "p_module_deadlines" "jsonb") TO "authenticated";
GRANT ALL ON FUNCTION "public"."manage_unit"("p_unit_id" "uuid", "p_customer_id" "uuid", "p_closes_at" timestamp with time zone, "p_module_deadlines" "jsonb") TO "service_role";



REVOKE ALL ON FUNCTION "public"."record_customization_actor"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."record_customization_actor"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."record_draft_history"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."record_draft_history"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."record_unit_access"("p_unit_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."record_unit_access"("p_unit_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."record_unit_access"("p_unit_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."register_customer_account"("p_name" "text", "p_email" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."register_customer_account"("p_name" "text", "p_email" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."register_customer_account"("p_name" "text", "p_email" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."request_architect_assistance"("p_customer_id" "uuid", "p_unit_id" "uuid", "p_architect_user_id" "uuid", "p_message" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."request_architect_assistance"("p_customer_id" "uuid", "p_unit_id" "uuid", "p_architect_user_id" "uuid", "p_message" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."resolve_architect_assistance"("p_request_id" "uuid", "p_note" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."resolve_architect_assistance"("p_request_id" "uuid", "p_note" "text") TO "service_role";



GRANT ALL ON TABLE "public"."configuration_reviews" TO "service_role";
GRANT SELECT ON TABLE "public"."configuration_reviews" TO "authenticated";



REVOKE ALL ON FUNCTION "public"."review_unit_configuration"("p_unit_id" "uuid", "p_expected_revision" integer, "p_decision" "text", "p_note" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."review_unit_configuration"("p_unit_id" "uuid", "p_expected_revision" integer, "p_decision" "text", "p_note" "text") TO "service_role";



GRANT ALL ON TABLE "public"."unit_proposal_reviews" TO "service_role";
GRANT SELECT ON TABLE "public"."unit_proposal_reviews" TO "authenticated";



REVOKE ALL ON FUNCTION "public"."review_unit_proposal"("p_unit_id" "uuid", "p_expected_revision" integer, "p_decision" "text", "p_note" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."review_unit_proposal"("p_unit_id" "uuid", "p_expected_revision" integer, "p_decision" "text", "p_note" "text") TO "service_role";



GRANT ALL ON TABLE "public"."unit_configuration_state" TO "service_role";
GRANT SELECT ON TABLE "public"."unit_configuration_state" TO "authenticated";



REVOKE ALL ON FUNCTION "public"."save_partial_unit_configuration"("p_customer_id" "uuid", "p_unit_id" "uuid", "p_selections" "jsonb", "p_expected_revision" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."save_partial_unit_configuration"("p_customer_id" "uuid", "p_unit_id" "uuid", "p_selections" "jsonb", "p_expected_revision" integer) TO "service_role";



REVOKE ALL ON FUNCTION "public"."save_staff_unit_configuration"("p_unit_id" "uuid", "p_plan_id" "uuid", "p_option_ids" "uuid"[], "p_partial_selections" "jsonb", "p_expected_revision" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."save_staff_unit_configuration"("p_unit_id" "uuid", "p_plan_id" "uuid", "p_option_ids" "uuid"[], "p_partial_selections" "jsonb", "p_expected_revision" integer) TO "service_role";



REVOKE ALL ON FUNCTION "public"."save_unit_configuration"("p_customer_id" "uuid", "p_unit_id" "uuid", "p_plan_id" "uuid", "p_option_ids" "uuid"[], "p_expected_revision" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."save_unit_configuration"("p_customer_id" "uuid", "p_unit_id" "uuid", "p_plan_id" "uuid", "p_option_ids" "uuid"[], "p_expected_revision" integer) TO "service_role";



GRANT ALL ON TABLE "public"."unit_drafts" TO "service_role";
GRANT SELECT ON TABLE "public"."unit_drafts" TO "authenticated";



REVOKE ALL ON FUNCTION "public"."save_unit_draft"("p_unit_id" "uuid", "p_selections" "jsonb", "p_expected_revision" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."save_unit_draft"("p_unit_id" "uuid", "p_selections" "jsonb", "p_expected_revision" integer) TO "service_role";



GRANT ALL ON TABLE "public"."unit_module_states" TO "service_role";
GRANT SELECT ON TABLE "public"."unit_module_states" TO "authenticated";



REVOKE ALL ON FUNCTION "public"."save_unit_module_choices"("p_customer_id" "uuid", "p_unit_id" "uuid", "p_module_code" "text", "p_selections" "jsonb", "p_expected_revision" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."save_unit_module_choices"("p_customer_id" "uuid", "p_unit_id" "uuid", "p_module_code" "text", "p_selections" "jsonb", "p_expected_revision" integer) TO "service_role";



GRANT ALL ON TABLE "public"."architect_authorizations" TO "service_role";
GRANT SELECT ON TABLE "public"."architect_authorizations" TO "authenticated";



REVOKE ALL ON FUNCTION "public"."set_architect_authorization"("p_customer_id" "uuid", "p_unit_id" "uuid", "p_architect_user_id" "uuid", "p_active" boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."set_architect_authorization"("p_customer_id" "uuid", "p_unit_id" "uuid", "p_architect_user_id" "uuid", "p_active" boolean) TO "service_role";



REVOKE ALL ON FUNCTION "public"."set_module_deadline"("p_unit_id" "uuid", "p_module_code" "text", "p_closes_at" timestamp with time zone) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."set_module_deadline"("p_unit_id" "uuid", "p_module_code" "text", "p_closes_at" timestamp with time zone) TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_module_deadline"("p_unit_id" "uuid", "p_module_code" "text", "p_closes_at" timestamp with time zone) TO "service_role";



GRANT ALL ON TABLE "public"."units" TO "service_role";
GRANT SELECT ON TABLE "public"."units" TO "authenticated";



REVOKE ALL ON FUNCTION "public"."set_unit_active"("p_unit_id" "uuid", "p_active" boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."set_unit_active"("p_unit_id" "uuid", "p_active" boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_unit_active"("p_unit_id" "uuid", "p_active" boolean) TO "service_role";



REVOKE ALL ON FUNCTION "public"."set_unit_customer"("p_unit_id" "uuid", "p_customer_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."set_unit_customer"("p_unit_id" "uuid", "p_customer_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_unit_customer"("p_unit_id" "uuid", "p_customer_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."set_unit_deadline"("p_unit_id" "uuid", "p_closes_at" timestamp with time zone) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."set_unit_deadline"("p_unit_id" "uuid", "p_closes_at" timestamp with time zone) TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_unit_deadline"("p_unit_id" "uuid", "p_closes_at" timestamp with time zone) TO "service_role";



REVOKE ALL ON FUNCTION "public"."staff_can_access_unit"("p_unit_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."staff_can_access_unit"("p_unit_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."staff_can_access_unit"("p_unit_id" "uuid") TO "service_role";



GRANT ALL ON TABLE "public"."unit_proposals" TO "service_role";
GRANT SELECT ON TABLE "public"."unit_proposals" TO "authenticated";



REVOKE ALL ON FUNCTION "public"."submit_unit_proposal"("p_customer_id" "uuid", "p_unit_id" "uuid", "p_expected_module_revisions" "jsonb") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."submit_unit_proposal"("p_customer_id" "uuid", "p_unit_id" "uuid", "p_expected_module_revisions" "jsonb") TO "service_role";



REVOKE ALL ON FUNCTION "public"."unit_module_choice_snapshot"("p_unit_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."unit_module_choice_snapshot"("p_unit_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."unit_module_revision_snapshot"("p_unit_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."unit_module_revision_snapshot"("p_unit_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."validate_unit_session"("p_unit_id" "uuid", "p_selections" "jsonb") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."validate_unit_session"("p_unit_id" "uuid", "p_selections" "jsonb") TO "authenticated";
GRANT ALL ON FUNCTION "public"."validate_unit_session"("p_unit_id" "uuid", "p_selections" "jsonb") TO "service_role";



GRANT ALL ON TABLE "public"."architect_assistance_events" TO "service_role";
GRANT SELECT ON TABLE "public"."architect_assistance_events" TO "authenticated";



GRANT ALL ON SEQUENCE "public"."architect_assistance_events_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."architect_assistance_events_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."architect_assistance_events_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."architect_authorization_events" TO "service_role";
GRANT SELECT ON TABLE "public"."architect_authorization_events" TO "authenticated";



GRANT ALL ON SEQUENCE "public"."architect_authorization_events_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."architect_authorization_events_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."architect_authorization_events_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."base_plan_option_availability" TO "service_role";
GRANT SELECT ON TABLE "public"."base_plan_option_availability" TO "authenticated";



GRANT ALL ON TABLE "public"."base_plan_option_defaults" TO "service_role";
GRANT SELECT ON TABLE "public"."base_plan_option_defaults" TO "authenticated";



GRANT ALL ON TABLE "public"."base_plan_option_exclusions" TO "service_role";
GRANT SELECT ON TABLE "public"."base_plan_option_exclusions" TO "authenticated";



GRANT ALL ON TABLE "public"."base_plan_option_requirements" TO "service_role";
GRANT SELECT ON TABLE "public"."base_plan_option_requirements" TO "authenticated";



GRANT ALL ON TABLE "public"."base_plans" TO "service_role";
GRANT SELECT ON TABLE "public"."base_plans" TO "authenticated";



GRANT ALL ON TABLE "public"."customer_customizations" TO "service_role";
GRANT SELECT ON TABLE "public"."customer_customizations" TO "authenticated";



GRANT ALL ON TABLE "public"."customer_units" TO "service_role";
GRANT SELECT ON TABLE "public"."customer_units" TO "authenticated";



GRANT ALL ON TABLE "public"."customer_users" TO "service_role";
GRANT SELECT ON TABLE "public"."customer_users" TO "authenticated";



GRANT ALL ON TABLE "public"."customers" TO "service_role";
GRANT SELECT ON TABLE "public"."customers" TO "authenticated";



GRANT ALL ON TABLE "public"."customization_groups" TO "service_role";
GRANT SELECT ON TABLE "public"."customization_groups" TO "authenticated";



GRANT ALL ON TABLE "public"."customization_history" TO "service_role";
GRANT SELECT ON TABLE "public"."customization_history" TO "authenticated";



GRANT ALL ON TABLE "public"."customization_modules" TO "service_role";
GRANT SELECT ON TABLE "public"."customization_modules" TO "authenticated";



GRANT ALL ON TABLE "public"."customization_options" TO "service_role";
GRANT SELECT ON TABLE "public"."customization_options" TO "authenticated";



GRANT ALL ON TABLE "public"."customization_windows" TO "service_role";
GRANT SELECT ON TABLE "public"."customization_windows" TO "authenticated";



GRANT ALL ON TABLE "public"."draft_history" TO "service_role";
GRANT SELECT ON TABLE "public"."draft_history" TO "authenticated";



GRANT ALL ON SEQUENCE "public"."draft_history_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."draft_history_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."draft_history_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."import_rows" TO "service_role";



GRANT ALL ON SEQUENCE "public"."import_rows_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."import_rows_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."import_rows_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."option_compatibilities" TO "service_role";
GRANT SELECT ON TABLE "public"."option_compatibilities" TO "authenticated";



GRANT ALL ON TABLE "public"."plan_features" TO "service_role";
GRANT SELECT ON TABLE "public"."plan_features" TO "authenticated";



GRANT ALL ON TABLE "public"."plans" TO "service_role";
GRANT SELECT ON TABLE "public"."plans" TO "authenticated";



GRANT ALL ON TABLE "public"."staff_unit_assignments" TO "service_role";
GRANT SELECT ON TABLE "public"."staff_unit_assignments" TO "authenticated";



GRANT ALL ON TABLE "public"."staff_users" TO "service_role";
GRANT SELECT ON TABLE "public"."staff_users" TO "authenticated";



GRANT ALL ON TABLE "public"."unit_activity_events" TO "service_role";
GRANT SELECT ON TABLE "public"."unit_activity_events" TO "authenticated";



GRANT ALL ON SEQUENCE "public"."unit_activity_events_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."unit_activity_events_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."unit_activity_events_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."unit_base_plan_assignments" TO "service_role";
GRANT SELECT ON TABLE "public"."unit_base_plan_assignments" TO "authenticated";



GRANT ALL ON TABLE "public"."unit_module_history" TO "service_role";
GRANT SELECT ON TABLE "public"."unit_module_history" TO "authenticated";



GRANT ALL ON TABLE "public"."unit_module_selections" TO "service_role";
GRANT SELECT ON TABLE "public"."unit_module_selections" TO "authenticated";



GRANT ALL ON TABLE "public"."unit_module_windows" TO "service_role";
GRANT SELECT ON TABLE "public"."unit_module_windows" TO "authenticated";



GRANT ALL ON TABLE "public"."unit_plans" TO "service_role";
GRANT SELECT ON TABLE "public"."unit_plans" TO "authenticated";



GRANT ALL ON TABLE "public"."unit_proposal_versions" TO "service_role";
GRANT SELECT ON TABLE "public"."unit_proposal_versions" TO "authenticated";



ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "service_role";







