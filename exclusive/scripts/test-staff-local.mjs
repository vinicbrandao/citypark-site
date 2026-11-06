import assert from 'node:assert/strict';
import { createClient } from '@supabase/supabase-js';
import { localEnvironment } from './local-env.mjs';
const {apiUrl,publicKey,secretKey} = localEnvironment();
const options = {auth:{persistSession:false,autoRefreshToken:false}};
const service = createClient(apiUrl,secretKey,options);
const check = r => {if(r.error) throw r.error;return r.data;};
async function login(email) {
 const link = check(await service.auth.admin.generateLink({type:'magiclink',email}));
 const c = createClient(apiUrl,publicKey,options);
 check(await c.auth.verifyOtp({email,token:link.properties.email_otp,type:'email'})); return c;
}
for (const [role,count] of [['admin',3],['architect',2]]) for(let i=1;i<=count;i++) {
 const c = await login(`${role}.${i}@example.test`);
 try {
  assert.equal(check(await c.rpc('current_staff_role')),role);
  const units = check(await c.from('units').select('id')); assert.ok(units.length>=2);
  const draft = check(await c.from('unit_drafts').select('*').eq('unit_id',units[0].id).maybeSingle());
  const selections = draft?.selections || {socialPlant:null,suitePlant:null,counter:'counter-standard',stone:'sao-marco',rodamao:'padrao',service:'service-no'};
  const args = {p_unit_id:units[0].id,p_selections:selections,p_expected_revision:draft?.revision||0};
  assert.equal((await c.rpc('save_unit_draft',{...args,p_selections:{...selections,price:1}})).error?.code,'22023');
  const saved = check(await c.rpc('save_unit_draft',args));
  const audit = check(await c.from('draft_history').select('*').eq('unit_id',units[0].id).eq('revision',saved.revision).single());
  assert.equal(audit.actor_role,role);
  assert.equal(audit.actor_id,check(await c.auth.getUser()).user.id);
  assert.ok((await c.from('staff_users').update({role:'admin'}).eq('user_id',audit.actor_id)).error);
  assert.ok((await c.from('unit_drafts').update({selections:{price:0}}).eq('unit_id',units[0].id)).error);
  if(role==='architect' && i===2) {
   check(await service.from('staff_users').update({active:false}).eq('user_id',audit.actor_id));
   try { assert.equal((await c.rpc('save_unit_draft',{...args,p_expected_revision:saved.revision})).error?.code,'42501'); }
   finally { check(await service.from('staff_users').update({active:true}).eq('user_id',audit.actor_id)); }
  }
 } finally { await c.auth.signOut(); }
}
console.log('PASS: cinco logins, perfis, atendimento de unidades, auditoria, rejeição de preço, bloqueio de promoção e revogação imediata.');
