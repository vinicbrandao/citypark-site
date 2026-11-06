import { createHash } from 'node:crypto';
import { mkdirSync, readFileSync, readdirSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { resolve } from 'node:path';

export const officialProjectRef = 'grfmiuopojbxxbdymqax';
const root = fileURLToPath(new URL('../', import.meta.url));

export function prepareOfficialDeployment() {
  const migrationsPath = resolve(root, 'supabase/migrations');
  const migrations = readdirSync(migrationsPath).filter(name => /^\d+_.+\.sql$/.test(name)).sort().map(filename => {
    const source = readFileSync(resolve(migrationsPath, filename), 'utf8').replace(/\r\n/g, '\n');
    if (/^\s*(begin|commit|rollback)\s*;/im.test(source) || /^\s*\\/m.test(source)) {
      throw new Error(`Revisão manual necessária para transação/comando psql: ${filename}`);
    }
    const [, version, name] = filename.match(/^(\d+)_(.+)\.sql$/);
    return { filename, version, name, source, sha256: createHash('sha256').update(source).digest('hex') };
  });
  const tag = '$citypark_source_20261028$';
  if (migrations.some(migration => migration.source.includes(tag))) throw new Error('Delimitador SQL em conflito.');
  const quote = value => `'${value.replaceAll("'", "''")}'`;
  const sql = `-- REVIEW REQUIRED: initial deployment of CityPark Exclusive.
-- Target project: ${officialProjectRef}; organization: CityPark Exclusive.
-- Schema and versioned reference records only; no local seed or Auth user data.
-- One transaction: a failed migration rolls back this entire bootstrap.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '120s';
set local citypark.optimized_initial_install = 'on';
do $citypark_empty_guard$
begin
  if exists (select 1 from pg_tables where schemaname = 'public')
     or exists (select 1 from auth.users) then
    raise exception 'Initial bootstrap requires an empty public schema and no Auth users';
  end if;
end;
$citypark_empty_guard$;
create schema if not exists supabase_migrations;
create table if not exists supabase_migrations.schema_migrations (
  version text primary key,
  statements text[],
  name text
);
alter table supabase_migrations.schema_migrations enable row level security;
revoke all on schema supabase_migrations from public, anon, authenticated;
revoke all on supabase_migrations.schema_migrations from public, anon, authenticated;
do $citypark_history_guard$
begin
  if exists (select 1 from supabase_migrations.schema_migrations) then
    raise exception 'Migration history is not empty; stop and reconcile before deployment';
  end if;
end;
$citypark_history_guard$;

${migrations.map(migration => `-- MIGRATION: ${migration.filename}\n-- SHA256: ${migration.sha256}\n${migration.source.trim()}\ninsert into supabase_migrations.schema_migrations(version, name, statements)\nvalues (${quote(migration.version)}, ${quote(migration.name)}, ARRAY[${tag}${migration.source}${tag}]);`).join('\n\n')}

do $citypark_result_guard$
begin
  if exists (select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relkind in ('r', 'p') and not c.relrowsecurity) then
    raise exception 'A public table is missing RLS';
  end if;
  if exists(select 1 from auth.users) or exists(select 1 from public.customers)
    or exists(select 1 from public.units) or exists(select 1 from public.staff_users) then
    raise exception 'Initial deployment unexpectedly created application accounts or customer data';
  end if;
end;
$citypark_result_guard$;
commit;
select 'CityPark initial schema installed' as result,
  (select count(*) from supabase_migrations.schema_migrations) as migrations,
  (select count(*) from pg_tables where schemaname = 'public') as public_tables,
  (select count(*) from auth.users) as auth_users;
`;
  const outputPath = resolve(root, 'outputs/deployment', officialProjectRef);
  mkdirSync(outputPath, { recursive: true });
  const sqlPath = resolve(outputPath, 'initial-schema.sql');
  writeFileSync(sqlPath, sql);
  const manifest = {
    projectRef: officialProjectRef,
    organization: 'CityPark Exclusive',
    schemaOnly: true,
    includesLocalSeeds: false,
    createsAdminAccount: false,
    optimizedInitialInstall: true,
    expectedPublicTables: 19,
    sha256: createHash('sha256').update(sql).digest('hex'),
    migrations: migrations.map(({ source, ...metadata }) => metadata),
  };
  writeFileSync(resolve(outputPath, 'manifest.json'), JSON.stringify(manifest, null, 2) + '\n');
  return { sql, sqlPath, manifest };
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const { sqlPath, manifest } = prepareOfficialDeployment();
  console.log(`Pacote preparado para revisão: ${sqlPath}`);
  console.log(`${manifest.migrations.length} migrations; nenhum seed, conta Auth ou Admin incluído. Nenhuma conexão remota realizada.`);
}
