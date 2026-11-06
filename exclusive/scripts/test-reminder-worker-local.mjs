import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { createServer } from 'node:http';
import { randomUUID } from 'node:crypto';
import { existsSync, writeFileSync, unlinkSync } from 'node:fs';
import { createClient } from '@supabase/supabase-js';
import { localEnvironment } from './local-env.mjs';
import { requireLegacyFixtureCleanup } from './require-legacy-fixture-cleanup.mjs';
const envPath='supabase/functions/.env';
assert.equal(existsSync(envPath),false,'Refusing to overwrite an existing function environment.');
const {apiUrl,secretKey}=localEnvironment();
const service=createClient(apiUrl,secretKey,{auth:{persistSession:false}});
await requireLegacyFixtureCleanup(service);
const check=r=>{if(r.error)throw r.error;return r.data;};
const due=spawnSync('docker',['exec','-i','supabase_db_citypark-exclusive','psql','-U','postgres','-d','postgres','-qAt','-c',`select count(*) from public.units u cross join lateral (select u.customization_closes_at d union all select closes_at from public.unit_module_windows where unit_id=u.id and status='active') dates where u.active and u.customization_status='pending' and (d at time zone 'America/Sao_Paulo')::date-(clock_timestamp() at time zone 'America/Sao_Paulo')::date in (15,10,5,1);`],{encoding:'utf8'});
assert.equal(due.status,0,'Unable to check existing reminders');assert.equal(Number(due.stdout.trim()),0,'Refusing to process existing local reminders during the mock test.');
const id=randomUUID(),token=randomUUID(),transportToken=randomUUID(),received=[];let uid,envCreated=false;
const server=createServer(async(req,res)=>{let raw='';for await(const c of req)raw+=c;assert.equal(req.headers.authorization,`Bearer ${transportToken}`);const body=JSON.parse(raw);assert.equal(body.to,`reminder-${id}@example.test`);assert.equal(req.headers['idempotency-key'],body.id);received.push(body);res.writeHead(200).end('ok');});
try{
 await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
 const email=`reminder-${id}@example.test`;
 uid=check(await service.auth.admin.createUser({email,email_confirm:true})).user.id;
 check(await service.from('customers').insert({id,name:'Lembrete de teste',email}));
 check(await service.from('customer_users').insert({customer_id:id,user_id:uid}));
 const deadline=new Date();deadline.setUTCDate(deadline.getUTCDate()+15);deadline.setUTCHours(15,0,0,0);
 check(await service.from('units').insert({id,code:`REMINDER-${id.slice(0,8)}`,tower:'Teste',floor_label:'Teste',termination:'09A',typology:'Teste',customization_closes_at:deadline.toISOString()}));
 check(await service.from('customer_units').insert({customer_id:id,unit_id:id}));
 writeFileSync(envPath,`DEADLINE_REMINDER_TOKEN=${token}\nDEADLINE_EMAIL_PROVIDER=webhook\nDEADLINE_EMAIL_WEBHOOK_URL=http://host.docker.internal:${server.address().port}\nDEADLINE_EMAIL_WEBHOOK_TOKEN=${transportToken}\n`);envCreated=true;
 let response;
 for(let i=0;i<50;i++){await new Promise(r=>setTimeout(r,300));try{response=await fetch(`${apiUrl}/functions/v1/deadline-reminders`,{method:'POST',headers:{Authorization:`Bearer ${token}`}});if(![401,502,503].includes(response.status))break;}catch{}}
 assert.equal(response?.status,200,`Worker status ${response?.status}: ${await response?.text()}`);
 assert.equal(received.length,1);assert.equal(received[0].daysBefore,15);assert.match(received[0].text,/Faltam 15 dias/);
 const again=await fetch(`${apiUrl}/functions/v1/deadline-reminders`,{method:'POST',headers:{Authorization:`Bearer ${token}`}});assert.equal(again.status,200);assert.equal(received.length,1,'Duplicate email sent');
 const denied=await fetch(`${apiUrl}/functions/v1/deadline-reminders`,{method:'POST',headers:{Authorization:'Bearer invalid'}});assert.equal(denied.status,401);
 const queue=check(await service.from('deadline_notifications').select('status,attempts').eq('unit_id',id));assert.equal(queue[0].status,'sent');assert.equal(queue[0].attempts,1);
 console.log('PASS: local Edge worker, authenticated job, configurable HTTP transport, message content, delivery record and duplicate suppression. No real email sent.');
}finally{
 if(envCreated)unlinkSync(envPath);server.close();
 await service.from('deadline_notifications').delete().eq('unit_id',id);await service.from('customer_units').delete().eq('unit_id',id);await service.from('units').delete().eq('id',id);await service.from('customer_users').delete().eq('customer_id',id);await service.from('customers').delete().eq('id',id);if(uid)await service.auth.admin.deleteUser(uid);
}

