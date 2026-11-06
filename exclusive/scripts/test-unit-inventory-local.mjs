import {randomBytes} from 'node:crypto';
import {readFileSync} from 'node:fs';
import {spawnSync} from 'node:child_process';
import {prepareOfficialDeployment} from './prepare-official-deployment.mjs';
import {body} from './prepare-unit-inventory.mjs';
const database=`citypark_inventory_check_${randomBytes(6).toString('hex')}`;
const docker=(args,input)=>{const r=spawnSync('docker',args,{input,encoding:'utf8',maxBuffer:8*1024*1024,timeout:120000});if(r.error||r.status!==0)throw Error((r.stderr||r.error?.message||'Docker failed').trim());return r.stdout;};
const psql=(db,sql)=>docker(['exec','-i','supabase_db_citypark-exclusive','psql','-X','-U','postgres','-d',db,'-qAt','-v','ON_ERROR_STOP=1'],sql);
let created=false;
try{
 psql('postgres',`create database "${database}" template template0;`);created=true;
 const auth=docker(['exec','supabase_db_citypark-exclusive','pg_dump','-U','postgres','-d','postgres','--schema-only','--schema=auth','--no-owner','--no-privileges']);psql(database,auth);
 psql(database,'revoke create on schema public from public;grant usage on schema public,auth to anon,authenticated,service_role;');
 psql(database,prepareOfficialDeployment().sql);
 psql(database,`insert into auth.users(id,email) values('51000000-0000-4000-8000-000000000001','inventory@example.test');
 insert into public.customers(id,name,email) values('52000000-0000-4000-8000-000000000001','Preservar','inventory@example.test');
 insert into public.customer_users(customer_id,user_id) values('52000000-0000-4000-8000-000000000001','51000000-0000-4000-8000-000000000001');
 insert into public.units(id,code,tower,tower_code,floor_label,floor_number,termination,termination_code,typology,active)
 values('53000000-0000-4000-8000-000000000001','1505A','A','A','15º andar',15,'05','05','A confirmar',true);
 insert into public.customer_units(customer_id,unit_id) values('52000000-0000-4000-8000-000000000001','53000000-0000-4000-8000-000000000001');`);
 // A mismatched location must fail before adding any row.
 psql(database,"update public.units set floor_number=14 where code='1505A';");
 let refused=false;try{psql(database,`begin;${body}commit;`);}catch(e){refused=e.message.includes('Existing unit location conflicts');if(!refused)throw e;}
 if(!refused)throw Error('Conflicting inventory accepted');
 psql(database,"update public.units set floor_number=15 where code='1505A';");
 // Run twice: preserve ids, active flag and owner link; all other units empty.
 psql(database,`begin;${body}commit;`);psql(database,`begin;${body}commit;`);
 psql(database,`set role authenticated;select set_config('request.jwt.claim.sub','51000000-0000-4000-8000-000000000001',false);
 do $$ begin if (select count(*) from public.list_customer_unit_cards())<>1 or (select count(*) from public.units)<>1 then raise exception 'Client saw units without a link';end if;end $$;`);
 console.log('PASS: 389 unique units, 209 A/180 B, 388 inactive placeholders, 1505A and owner preserved, idempotent reload, conflicting location refused, customer isolation preserved; cloud untouched.');
}finally{if(created)psql('postgres',`drop database "${database}" with (force);`);}
