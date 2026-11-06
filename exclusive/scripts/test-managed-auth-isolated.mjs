import {createHmac,randomBytes} from 'node:crypto';
import {spawnSync} from 'node:child_process';
import assert from 'node:assert/strict';

// Real Auth API against the disposable database; no connection to cloud or SMTP.
export async function testManagedAuth(database,psql) {
 assert.match(database,/^citypark_permissions_check_[a-f0-9]{12}$/,'Disposable database only');
 const container=`${database}_auth`;
 function docker(args,env){const r=spawnSync('docker',args,{encoding:'utf8',env:{...process.env,...env},maxBuffer:4*1024*1024,timeout:60000});if(r.error||r.status!==0)throw Error('Isolated Auth container operation failed');return r.stdout.trim();}
 const original=JSON.parse(docker(['inspect','supabase_auth_citypark-exclusive']))[0];
 const originalEnv=Object.fromEntries(original.Config.Env.map(s=>{const i=s.indexOf('=');return [s.slice(0,i),s.slice(i+1)];}));
 const dbUrl=new URL(originalEnv.GOTRUE_DB_DATABASE_URL);dbUrl.pathname=`/${database}`;
 const jwtSecret=randomBytes(32).toString('hex');
 const env={GOTRUE_API_HOST:'0.0.0.0',GOTRUE_API_PORT:'9999',API_EXTERNAL_URL:'http://127.0.0.1:9999',GOTRUE_SITE_URL:'http://127.0.0.1',
 GOTRUE_DB_DRIVER:'postgres',GOTRUE_DB_DATABASE_URL:dbUrl.href,DB_NAMESPACE:'auth',GOTRUE_DB_MAX_POOL_SIZE:'2',GOTRUE_DISABLE_SIGNUP:'true',
 GOTRUE_JWT_SECRET:jwtSecret,GOTRUE_JWT_AUD:'authenticated',GOTRUE_JWT_DEFAULT_GROUP_NAME:'authenticated',GOTRUE_JWT_ADMIN_ROLES:'service_role',
 GOTRUE_MAILER_AUTOCONFIRM:'false',GOTRUE_SMTP_HOST:'127.0.0.1',GOTRUE_SMTP_PORT:'1',GOTRUE_SMTP_ADMIN_EMAIL:'test@example.test'};
 if(originalEnv.GOTRUE_DB_MIGRATIONS_PATH)env.GOTRUE_DB_MIGRATIONS_PATH=originalEnv.GOTRUE_DB_MIGRATIONS_PATH;
 const network=Object.keys(original.NetworkSettings.Networks)[0];
 const authVersions=docker(['exec','supabase_db_citypark-exclusive','pg_dump','-U','postgres','-d','postgres','--data-only','--inserts','--table=auth.schema_migrations']);
 psql(database,authVersions);
 assert.ok(Number(psql(database,'select count(*) from auth.schema_migrations;').trim())>0,'Auth migration history was not copied');
 const ownershipSql=`grant usage,create on schema auth to supabase_auth_admin;
 do $$ declare t record;begin for t in select tablename from pg_tables where schemaname='auth' loop
 execute format('alter table auth.%I owner to supabase_auth_admin',t.tablename);end loop;end $$;
 grant all on all tables in schema auth to supabase_auth_admin;grant all on all sequences in schema auth to supabase_auth_admin;`;
 const ownership=spawnSync('docker',['exec','-i','supabase_db_citypark-exclusive','psql','-U','supabase_admin','-d',database,'-qAt','-v','ON_ERROR_STOP=1'],{input:ownershipSql,encoding:'utf8'});
 if(ownership.status!==0)throw Error('Unable to restore Auth ownership in the disposable database');
 let started=false;
 function authFailure(){
  const logs=spawnSync('docker',['logs','--tail','12',container],{encoding:'utf8'});
  return (logs.stdout+'\n'+logs.stderr).replaceAll(dbUrl.href,'[database]').replaceAll(jwtSecret,'[secret]').replace(/postgres(?:ql)?:\/\/[^\s"']+/g,'[database]');
 }
 try {
  docker(['run','-d','--name',container,'--volumes-from','supabase_auth_citypark-exclusive:ro','--network',network,'-p','127.0.0.1::9999',...Object.keys(env).flatMap(k=>['-e',k]),original.Config.Image],env);started=true;
  const address=JSON.parse(docker(['inspect',container]))[0].NetworkSettings.Ports['9999/tcp']?.[0];
  if(!address)throw Error('Isolated Auth exited: '+authFailure());
  const base=`http://127.0.0.1:${address.HostPort}`;
  let ready=false;
  for(let i=0;i<40;i++){try{ready=(await fetch(base+'/health',{signal:AbortSignal.timeout(500)})).ok;if(ready)break;}catch{}await new Promise(r=>setTimeout(r,200));}
  if(!ready){
    throw Error('Isolated Auth did not become healthy: '+authFailure());
  }
  const enc=s=>Buffer.from(JSON.stringify(s)).toString('base64url');
  const unsigned=enc({alg:'HS256',typ:'JWT'})+'.'+enc({role:'service_role',iss:'supabase',exp:Math.floor(Date.now()/1000)+600});
  const serviceToken=unsigned+'.'+createHmac('sha256',jwtSecret).update(unsigned).digest('base64url');
  async function call(path,method,body,token=serviceToken){const res=await fetch(base+path,{method,headers:{Authorization:`Bearer ${token}`,'Content-Type':'application/json'},body:body?JSON.stringify(body):undefined});return {status:res.status,body:await res.json()};}
  const password=randomBytes(24).toString('hex')+'T!';
  const created=await call('/admin/users','POST',{email:'isolated-auth@example.test',password,email_confirm:true});
  assert.equal(created.status,200,'Real Auth account creation failed');
  const uid=created.body.id;
  assert.match(uid,/^[0-9a-f-]{36}$/);
  psql(database,`insert into public.customers(id,name,email) values('42000000-0000-4000-8000-000000000099','Isolated Auth','isolated-auth@example.test');insert into public.customer_users(customer_id,user_id) values('42000000-0000-4000-8000-000000000099','${uid}');`);
  const login=await call('/token?grant_type=password','POST',{email:'isolated-auth@example.test',password});
  assert.equal(login.status,200,'Login was broken by the Auth trigger');
  const changed=await call('/user','PUT',{email:'self-change@example.test'},login.body.access_token);
  assert.ok(changed.status>=400,'Customer changed own login email');
  psql(database,`do $$ begin if exists(select 1 from auth.users where id='${uid}' and coalesce(email_change,'')<>'') then raise exception 'Unauthorized email-change request persisted';end if;end $$;`);
  psql(database,`begin;set local role authenticated;select set_config('request.jwt.claim.sub','41000000-0000-4000-8000-000000000001',true);select public.prepare_customer_email('42000000-0000-4000-8000-000000000099','admin-updated@example.test');commit;`);
  const approved=await call(`/admin/users/${uid}`,'PUT',{email:'admin-updated@example.test',email_confirm:false});
  assert.equal(approved.status,200,'Authorized Admin email update failed in real Auth');
  psql(database,`do $$ begin if not exists(select 1 from public.customers where id='42000000-0000-4000-8000-000000000099' and email='admin-updated@example.test' and authorized_email is null) then raise exception 'Real Auth/profile synchronization failed';end if;end $$;`);
  console.log('PASS: isolated real Auth API login, self-email rejection and Admin email/profile synchronization; no SMTP or cloud calls.');
 } finally {if(started)docker(['rm','-f',container]);}
}
