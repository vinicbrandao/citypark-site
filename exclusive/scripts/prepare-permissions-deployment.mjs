import {readFileSync,mkdirSync,writeFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
const version='20261030000100';
const name='production_permissions';
const source=readFileSync(new URL(`../supabase/migrations/${version}_${name}.sql`,import.meta.url),'utf8').replace(/\r\n/g,'\n');
const hash=createHash('sha256').update(source).digest('hex');
const tag='$citypark_permissions_source$';
if(source.includes(tag))throw Error('SQL delimiter conflict');
const sql=`-- REVIEW: official project grfmiuopojbxxbdymqax. Existing installation only.
-- No reset, seed, new account or new public table. Source SHA256: ${hash}
begin;
set local lock_timeout='5s';
set local statement_timeout='120s';
do $guard$ begin
 if (select count(*) from supabase_migrations.schema_migrations)<>26
   or not exists(select 1 from supabase_migrations.schema_migrations where version='20261028000100')
   or exists(select 1 from supabase_migrations.schema_migrations where version='${version}') then
   raise exception 'Expected the reviewed 26-version official schema; stop and reconcile';
 end if;
 if (select count(*) from pg_tables where schemaname='public')<>19 then
   raise exception 'Unexpected public schema';
 end if;
 if (select count(*) from public.staff_users s join auth.users u on u.id=s.user_id
   where lower(u.email)='exclusive@planoaengenharia.com.br' and s.role='admin' and s.active
     and u.deleted_at is null and (u.banned_until is null or u.banned_until<=clock_timestamp()))<>1 then
   raise exception 'Expected active principal Admin';
 end if;
end $guard$;
${source}
insert into supabase_migrations.schema_migrations(version,name,statements)
values('${version}','${name}',array[${tag}${source}${tag}]);
do $result$ begin
 if exists(select 1 from pg_tables t where t.schemaname='public' and not t.rowsecurity)
  or (select count(*) from pg_tables where schemaname='public')<>19 then raise exception 'Schema validation failed';end if;
 if not exists(select 1 from public.staff_users s join auth.users u on u.id=s.user_id where s.protected and s.active and s.role='admin' and lower(u.email)='exclusive@planoaengenharia.com.br') then raise exception 'Principal protection missing';end if;
end $result$;
commit;
select 'Permissions updated' as result,(select count(*) from supabase_migrations.schema_migrations) as versions;
`;
const dir=new URL('../outputs/deployment/grfmiuopojbxxbdymqax/',import.meta.url);
mkdirSync(dir,{recursive:true});
writeFileSync(new URL('permissions-upgrade.sql',dir),sql);
writeFileSync(new URL('permissions-manifest.json',dir),JSON.stringify({projectRef:'grfmiuopojbxxbdymqax',version,sourceSha256:hash,packageSha256:createHash('sha256').update(sql).digest('hex'),expectedTables:19,createsAccounts:false},null,2)+'\n');
console.log('Atualização incremental preparada; nenhuma conexão remota realizada.');
