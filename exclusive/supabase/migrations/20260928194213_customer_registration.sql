-- Amplia o cadastro de clientes sem alterar o fluxo atual de autenticação.

alter table public.customers
  add column email text,
  add column external_ref text;

-- O e-mail NÃO é único.
-- Duas pessoas diferentes podem compartilhar o mesmo endereço de e-mail.
-- external_ref será usado futuramente quando a origem dos dados fornecer
-- um identificador estável do cliente.

create unique index customers_external_ref_unique
  on public.customers (external_ref)
  where external_ref is not null;


-- Complementa os dados estruturais da unidade.
-- floor_label continua existindo para exibição, por exemplo "12º andar".
-- floor_number será utilizado para filtros e regras futuras.

alter table public.units
  add column floor_number integer,
  add column external_ref text;

alter table public.units
  add constraint units_floor_number_valid
  check (floor_number is null or floor_number >= 0);

create unique index units_external_ref_unique
  on public.units (external_ref)
  where external_ref is not null;


-- Informações referentes à relação entre um cliente e uma unidade.
-- A data da compra pertence ao vínculo, e não ao cliente:
-- uma mesma pessoa pode comprar apartamentos em datas diferentes.

alter table public.customer_units
  add column ownership_role text not null default 'owner',
  add column purchase_date date,
  add column external_ref text,
  add column created_at timestamptz not null default now();

alter table public.customer_units
  add constraint customer_units_ownership_role_valid
  check (ownership_role in ('owner', 'co_owner'));

create unique index customer_units_external_ref_unique
  on public.customer_units (external_ref)
  where external_ref is not null;