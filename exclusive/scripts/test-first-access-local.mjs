import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { createRequire } from 'node:module';
import { readFileSync, mkdirSync } from 'node:fs';
import { resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';
import { localEnvironment } from './local-env.mjs';
import { requireLegacyFixtureCleanup } from './require-legacy-fixture-cleanup.mjs';
assert.equal(/^\[auth\.email\.smtp\]\s*\nenabled\s*=\s*true/m.test(readFileSync('supabase/config.toml','utf8')),false,'First-access fixtures must use the local mailbox, never real SMTP.');
const require=createRequire(import.meta.url);
const {chromium}=require(process.env.CITYPARK_PLAYWRIGHT_PATH||'playwright');
const url=process.env.CITYPARK_UI_URL||'http://127.0.0.1:5174/exclusive/';
assert.ok(['127.0.0.1','localhost'].includes(new URL(url).hostname));
const {apiUrl,secretKey,publicKey}=localEnvironment();
const service=createClient(apiUrl,secretKey,{auth:{persistSession:false,autoRefreshToken:false}});
await requireLegacyFixtureCleanup(service);
const check=r=>{if(r.error)throw r.error;return r.data;};
const id=randomUUID(),unitId=randomUUID(),email=`first-access-${id}@example.test`;
const adminEmail=`first-access-admin-${id}@example.test`,adminPassword=randomUUID()+'T!';
const customerPassword=randomUUID()+'T!';let adminId,customerId,customerUserId,browser;
const capturedIds=[];
async function mailbox(){const r=await fetch('http://127.0.0.1:54324/api/v1/search?query='+encodeURIComponent('to:'+email));assert.equal(r.ok,true);return r.json();}
async function deliveredCode(){
 for(let i=0;i<40;i++){
  const list=await mailbox();const message=list.messages?.[0];
  if(message){capturedIds.push(message.ID);const mail=await fetch('http://127.0.0.1:54324/api/v1/message/'+message.ID).then(r=>r.json());
   assert.match(mail.Subject,/Defina sua senha/);const token=(mail.Text||mail.HTML||'').match(/\b\d{6}\b/)?.[0];assert.ok(token,'Recovery template did not include a six-digit code');return token;}
  await new Promise(r=>setTimeout(r,200));
 }
 throw Error('The authentication email did not arrive in the local mailbox.');
}
try{
 const settings=await fetch(`${apiUrl}/auth/v1/settings`,{headers:{apikey:publicKey}}).then(r=>r.json());assert.equal(settings.disable_signup,true);
 adminId=check(await service.auth.admin.createUser({email:adminEmail,password:adminPassword,email_confirm:true})).user.id;
 check(await service.from('staff_users').insert({user_id:adminId,name:'Admin do teste de primeiro acesso',role:'admin'}));
 const source=check(await service.from('units').select('id').eq('code','1401A').single());
 const plan=check(await service.from('unit_base_plan_assignments').select('base_plan_id').eq('unit_id',source.id).single());
 check(await service.from('units').insert({id:unitId,code:`FIRST-${id.slice(0,8)}`,tower:'Teste',floor_label:'Teste',termination:'09A',typology:'Demonstração',active:true}));
 check(await service.from('unit_base_plan_assignments').insert({unit_id:unitId,base_plan_id:plan.base_plan_id}));
 browser=await chromium.launch({channel:process.env.CITYPARK_BROWSER_CHANNEL||'msedge',headless:true});
 const page=await browser.newPage({viewport:{width:1366,height:768}});const errors=[];page.on('pageerror',e=>errors.push(e.message));
 await page.goto(url);await page.locator('#email').fill(adminEmail);await page.locator('#password').fill(adminPassword);await page.locator('#login-form button.auth-primary').click();await page.locator('.unit-table').waitFor();
 await page.locator('[data-action="new-customer"]').click();await page.locator('#customer-form input[name="name"]').fill('Cliente do primeiro acesso');await page.locator('#customer-form input[name="email"]').fill(email);await page.locator('#customer-form button[type="submit"]').click();await page.locator('#customer-form').waitFor({state:'detached'});
 customerId=check(await service.from('customers').select('id').eq('email',email).single()).id;
 customerUserId=check(await service.from('customer_users').select('user_id').eq('customer_id',customerId).single()).user_id;
 assert.equal(check(await service.auth.admin.getUserById(customerUserId)).user.email_confirmed_at,undefined,'The newly created account was already confirmed');
 const row=page.locator('tbody tr').filter({hasText:`FIRST-${id.slice(0,8)}`});await row.locator('[data-action="manage-unit"]').click();await page.locator('select[name="customer"]').selectOption(customerId);await page.locator('#unit-management-form button[type="submit"]').click();await page.locator('#unit-management-form').waitFor({state:'detached'});
 await page.locator('[data-action="logout"]').click();await page.locator('#login-form').waitFor();await page.locator('#login-mode').click();await page.locator('#email').fill(email);await page.locator('#login-form button.auth-primary').click();await page.locator('#code').waitFor();
 const code=await deliveredCode();mkdirSync('outputs/qa',{recursive:true});await page.screenshot({path:resolve('outputs/qa/first-access-code-request.png')});
 await page.locator('#resend').click();assert.match(await page.locator('.auth-message').textContent(),/Aguarde um minuto/);assert.equal((await mailbox()).total,1);
 await page.locator('#code').fill(code==='000000'?'111111':'000000');await page.locator('#login-form button.auth-primary').click();await page.getByText('Código inválido ou expirado.',{exact:false}).waitFor();assert.equal(await page.locator('.apartment-selection').count(),0);
 await page.locator('#code').fill(code);await page.locator('#login-form button.auth-primary').click();await page.locator('#password-form').waitFor();assert.equal(await page.locator('.apartment-selection').count(),0,'Units were opened before password setup');
 await page.locator('#new-password').fill(customerPassword);await page.locator('#confirm-password').fill('different-password');await page.locator('#password-form button').click();assert.match(await page.locator('.auth-message').textContent(),/não coincidem/);
 await page.locator('#confirm-password').fill(customerPassword);await page.locator('#password-form button').click();await page.locator('.apartment-selection').waitFor();assert.equal(await page.locator('[data-unit]').count(),1);assert.equal(await page.locator(`[data-unit="${unitId}"]`).count(),1);
 assert.ok(check(await service.auth.admin.getUserById(customerUserId)).user.email_confirmed_at,'Code verification did not confirm the email');
 await page.screenshot({path:resolve('outputs/qa/first-access-linked-unit.png')});
 await page.locator('[data-action="logout"]').click();await page.locator('#email').fill(email);await page.locator('#password').fill(customerPassword);await page.locator('#login-form button.auth-primary').click();await page.locator('.apartment-selection').waitFor();
 const isolated=createClient(apiUrl,publicKey,{auth:{persistSession:false}});const reused=await isolated.auth.verifyOtp({email,token:code,type:'recovery'});assert.ok(reused.error,'The recovery code could be reused');
 assert.deepEqual(errors,[]);console.log('PASS: UI account creation, unit linking, real Auth recovery email in local mailbox, invalid code, resend cooldown, password setup, email confirmation, password login, replay rejection and unit isolation.');
}finally{
 await browser?.close();
 const ids=[adminId,customerUserId].filter(Boolean);if(ids.length)await service.from('unit_activity_events').delete().in('actor_user_id',ids);
 await service.from('unit_activity_events').delete().eq('unit_id',unitId);await service.from('customer_units').delete().eq('unit_id',unitId);await service.from('unit_base_plan_assignments').delete().eq('unit_id',unitId);await service.from('units').delete().eq('id',unitId);
 if(customerId){await service.from('customer_users').delete().eq('customer_id',customerId);await service.from('customers').delete().eq('id',customerId);}
 if(adminId)await service.from('staff_users').delete().eq('user_id',adminId);
 for(const uid of ids)await service.auth.admin.deleteUser(uid);
 if(capturedIds.length)await fetch('http://127.0.0.1:54324/api/v1/messages',{method:'DELETE',headers:{'Content-Type':'application/json'},body:JSON.stringify({IDs:capturedIds})});
}
