import {randomBytes} from 'node:crypto';
import {readFileSync,readdirSync} from 'node:fs';
import {spawnSync} from 'node:child_process';
import './prepare-permissions-deployment.mjs';
import {testManagedAuth} from './test-managed-auth-isolated.mjs';
const database=`citypark_permissions_check_${randomBytes(6).toString('hex')}`;
const container='supabase_db_citypark-exclusive';
function docker(args,input){const r=spawnSync('docker',args,{input,encoding:'utf8',maxBuffer:8*1024*1024,timeout:120000});if(r.error||r.status!==0)throw Error((r.stderr||r.error?.message||'Docker failed').trim());return r.stdout;}
const psql=(db,sql)=>docker(['exec','-i',container,'psql','-X','-U','postgres','-d',db,'-qAt','-v','ON_ERROR_STOP=1'],sql);
let created=false;
try {
 const authSchema=docker(['exec',container,'pg_dump','-U','postgres','-d','postgres','--schema-only','--schema=auth','--no-owner','--no-privileges']);
 psql('postgres',`create database "${database}" template template0;`);created=true;
 psql(database,authSchema);
 psql(database,'revoke create on schema public from public; grant usage on schema public,auth to anon,authenticated,service_role;create schema supabase_migrations;create table supabase_migrations.schema_migrations(version text primary key,name text,statements text[]);');
 const dir=new URL('../supabase/migrations/',import.meta.url);
 const files=readdirSync(dir).filter(n=>/^\d+_.+\.sql$/.test(n)&&n<'20261030000100').sort();
 const baseline=files.map(n=>readFileSync(new URL(n,dir),'utf8')+`\ninsert into supabase_migrations.schema_migrations(version,name) values('${n.split('_')[0]}','baseline');`).join('\n');
 psql(database,`begin;set local citypark.optimized_initial_install='on';${baseline}\ncommit;`);
 psql(database,`insert into auth.users(id,email) values('41000000-0000-4000-8000-000000000001','exclusive@planoaengenharia.com.br'),('41000000-0000-4000-8000-000000000002','upgrade-owner@example.test');
 insert into public.staff_users(user_id,name,role) values('41000000-0000-4000-8000-000000000001','Principal','admin');
 insert into public.customers(id,name,email) values('42000000-0000-4000-8000-000000000001','Preservar','upgrade-owner@example.test');
 insert into public.customer_users(customer_id,user_id) values('42000000-0000-4000-8000-000000000001','41000000-0000-4000-8000-000000000002');
 insert into public.units(id,code,tower,floor_label,termination,typology) values('43000000-0000-4000-8000-000000000001','UPGRADE-1','Teste','Teste','01','Teste');
 insert into public.customer_units(customer_id,unit_id) values('42000000-0000-4000-8000-000000000001','43000000-0000-4000-8000-000000000001');
 insert into public.unit_activity_events(actor_user_id,actor_role,actor_name,action) values('41000000-0000-4000-8000-000000000001','admin','Principal','preserved_event');`);
 const upgrade=readFileSync(new URL('../outputs/deployment/grfmiuopojbxxbdymqax/permissions-upgrade.sql',import.meta.url),'utf8');
 psql(database,upgrade);
 psql(database,`do $$ begin
 if (select count(*) from public.customers)<>1 or not exists(select 1 from public.customers where name='Preservar' and active and phone is null) then raise exception 'Customer data changed';end if;
 if (select count(*) from auth.users)<>2 or (select count(*) from public.units)<>1 or (select count(*) from public.customer_units where active)<>1 then raise exception 'Identity or unit links changed';end if;
 if not exists(select 1 from public.staff_users where protected and active and role='admin') then raise exception 'Principal missing';end if;
 if (select count(*) from public.unit_activity_events where action='preserved_event')<>1 then raise exception 'History changed';end if;
 end $$;`);
 let refused=false;try{psql(database,upgrade);}catch(e){refused=e.message.includes('Expected the reviewed 26-version official schema');if(!refused)throw e;}
 if(!refused)throw Error('Repeat upgrade accepted');
 await testManagedAuth(database,psql);
 console.log('PASS: 26 -> 27 versions on a populated temporary database; identities, unit, links and history preserved; principal protected; repeat refused; remote untouched.');
} finally {if(created)psql('postgres',`drop database "${database}" with (force);`);}
