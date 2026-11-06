import { randomBytes } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { prepareOfficialDeployment } from './prepare-official-deployment.mjs';

// Replay against a disposable database in the existing LOCAL container.
// Never reset or write the project's postgres database except CREATE/DROP of
// this uniquely named database. No remote URL or credentials are accepted.
const container = 'supabase_db_citypark-exclusive';
const database = `citypark_deploy_check_${randomBytes(6).toString('hex')}`;
if (!/^citypark_deploy_check_[a-f0-9]{12}$/.test(database)) throw new Error('Unsafe test database name.');
function docker(args, input) {
  const result = spawnSync('docker', args, { input, encoding: 'utf8', maxBuffer: 8 * 1024 * 1024, timeout: 120000 });
  if (result.error || result.status !== 0) throw new Error((result.stderr || result.error?.message || 'Docker failed').trim());
  return result.stdout;
}
const psql = (name, sql) => docker(['exec', '-i', container, 'psql', '-X', '-U', 'postgres', '-d', name, '-qAt', '-v', 'ON_ERROR_STOP=1'], sql);
let created = false;
try {
  const { sql, manifest } = prepareOfficialDeployment();
  const authSchema = docker(['exec', container, 'pg_dump', '-U', 'postgres', '-d', 'postgres', '--schema-only', '--schema=auth', '--no-owner', '--no-privileges']);
  psql('postgres', `create database "${database}" template template0;`);
  created = true;
  psql(database, authSchema);
  psql(database, 'revoke create on schema public from public; grant usage on schema public, auth to anon, authenticated, service_role;');
  psql(database, sql);
  const cleanup = readFileSync(new URL('../supabase/migrations/20261028000100_optimized_empty_install.sql',import.meta.url),'utf8');
  const legacyFixture = "create table public.unit_drafts(note text); insert into public.unit_drafts values('historical fixture');";
  psql(database, `begin; ${legacyFixture}\n${cleanup}\ndo $$ begin if (select count(*) from public.unit_drafts)<>1 then raise exception 'Normal upgrade removed legacy history'; end if; end $$; rollback;`);
  let historyRefused = false;
  try { psql(database, `begin; ${legacyFixture} set local citypark.optimized_initial_install='on';\n${cleanup}\nrollback;`); }
  catch(error) { historyRefused=error.message.includes('Optimized initial install refuses data'); if(!historyRefused)throw error; }
  if(!historyRefused)throw new Error('Optimized cleanup accepted historical records.');
  const scenario = psql(database, readFileSync(new URL('./test-official-active-schema-local.sql',import.meta.url),'utf8'));
  if (!scenario.includes('PASS: optimized schema')) throw new Error('Current application scenario did not complete.');
  const permissions = psql(database, readFileSync(new URL('./test-production-permissions-local.sql',import.meta.url),'utf8'));
  if (!permissions.includes('PASS: production permissions')) throw new Error('Production permissions scenario did not complete.');
  const result = JSON.parse(psql(database, `select json_build_object(
    'migrations', (select count(*) from supabase_migrations.schema_migrations),
    'tables', (select count(*) from pg_tables where schemaname='public'),
    'tables_without_rls', (select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind in ('r','p') and not c.relrowsecurity),
    'auth_users', (select count(*) from auth.users),
    'customers', (select count(*) from public.customers),
    'units', (select count(*) from public.units),
    'staff', (select count(*) from public.staff_users),
    'customer_rpc', has_function_privilege('authenticated','public.list_customer_unit_cards()','execute'),
    'staff_table', has_table_privilege('authenticated','public.staff_users','select'),
    'customer_table', has_table_privilege('authenticated','public.customers','select'),
    'legacy_write_blocked', to_regprocedure('public.save_unit_draft(uuid,jsonb,integer)') is null,
    'anon_customer_blocked', not has_table_privilege('anon','public.customers','select')
  );`).trim());
  if (result.migrations !== manifest.migrations.length || result.tables !== manifest.expectedPublicTables || result.tables_without_rls !== 0
    || result.auth_users || result.customers || result.units || result.staff
    || !result.customer_rpc || !result.staff_table || !result.customer_table
    || !result.legacy_write_blocked || !result.anon_customer_blocked) {
    throw new Error(`Initial deployment assertions failed: ${JSON.stringify(result)}`);
  }
  // A repeat must refuse before changing anything.
  let refused = false;
  try { psql(database, sql); } catch (error) {
    refused = error.message.includes('Initial bootstrap requires an empty public schema');
    if (!refused) throw error;
  }
  if (!refused) throw new Error('Repeated bootstrap was not rejected.');
  console.log(JSON.stringify({ ...result, repeatRefused: true, normalUpgradePreservesHistory: true, refusesHistoricalData: true, currentRoleScenariosPassed: true, remoteModified: false }, null, 2));
} finally {
  if (created) psql('postgres', `drop database "${database}" with (force);`);
}
