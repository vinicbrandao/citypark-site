const { test } = require('node:test');
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { stripTypeScriptTypes } = require('node:module');
const vm = require('node:vm');

// Exercise the deployed handler with isolated Auth/database adapters; no network or account creation.
const source = stripTypeScriptTypes(readFileSync('supabase/functions/admin-customer/index.ts', 'utf8')
  .replace(/^import[^\n]+\n/, ''));
function fixture(options = {}) {
  const calls = [];
  let handler;
  const user = {
    from(){return {select(){return this;},eq(){return this;},async single(){return {data:{email:'client@example.test'},error:null};}};},
    auth: { async getUser() { return options.identityError
      ? { error: { message: 'Invalid JWT' }, data: { user: null } }
      : { error: null, data: { user: { id: 'fixture-admin' } } }; } },
    async rpc(name, args) {
      calls.push({ name, args });
      if (name === 'current_staff_role') return { data: options.role || 'admin', error: null };
      if (name === 'find_customer_auth_user') return { data: options.existing ? 'existing-user' : null, error: null };
      if(name==='prepare_customer_email') return {data:'existing-user',error:options.permissionError?{}:null};
      if(['update_customer_contact','cancel_customer_email'].includes(name)) return {data:null,error:null};
      if (name === 'register_customer_account') return { data: 'fixture-customer', error: null };
      throw Error(`Unexpected RPC: ${name}`);
    }
  };
  const service = { auth: { admin: { async updateUserById(id,data){calls.push({name:'updateUserById',id,data});return {error:options.updateError?{}:null};}, async createUser(data) {
    calls.push({ name: 'createUser', data });
    return { data: { user: { id: 'new-user' } }, error: options.creationError ? { message: 'Creation failed' } : null };
  } } } };
  vm.runInNewContext(source, {
    Request, Response,
    createClient(_url, key, settings) {
      if (key === 'fixture-service-key') { calls.push({ name: 'serviceClient' }); return service; }
      calls.push({ name: 'userClient', authorization: settings?.global?.headers?.Authorization });
      return user;
    },
    Deno: { env: { get: name => ({ SUPABASE_URL: 'https://fixture.example.test', SUPABASE_ANON_KEY: 'fixture-public-key', SUPABASE_SERVICE_ROLE_KEY: 'fixture-service-key' })[name] }, serve: fn => { handler = fn; } }
  });
  return {
    calls,
    request(body = { name: 'Cliente', email: 'client@example.test' }, authorization = 'Bearer fixture-user-token', method = 'POST') {
      return handler(new Request('https://fixture.example.test/functions/v1/admin-customer', {
        method, headers: authorization ? { Authorization: authorization } : {},
        ...(method === 'POST' ? { body: JSON.stringify(body) } : {})
      }));
    }
  };
}
function noAccountWrites(f) {
  assert.equal(f.calls.some(c => ['serviceClient', 'createUser', 'register_customer_account'].includes(c.name)), false);
}

test('customer function denies missing identity before any account writes', async () => {
  const f = fixture({ identityError: true });
  assert.equal((await f.request(undefined, '')).status, 403);
  noAccountWrites(f);
});
test('customer function denies an invalid token even if role lookup returned Admin', async () => {
  const f = fixture({ identityError: true });
  assert.equal((await f.request()).status, 403);
  noAccountWrites(f);
});
test('customer function denies an authenticated architect', async () => {
  const f = fixture({ role: 'architect' });
  assert.equal((await f.request()).status, 403);
  noAccountWrites(f);
});
test('customer function rejects malformed customer data without creating Auth users', async () => {
  const f = fixture();
  assert.equal((await f.request({ name: 'Cliente', email: 'invalid' })).status, 400);
  noAccountWrites(f);
});
test('customer function creates unconfirmed accounts without passwords or invitations', async () => {
  const f = fixture();
  const response = await f.request({ name: ' Cliente ', email: ' CLIENT@EXAMPLE.TEST ' });
  assert.equal(response.status, 200);
  const created = f.calls.find(c => c.name === 'createUser').data;
  assert.deepEqual(Object.keys(created).sort(), ['email', 'email_confirm']);
  assert.equal(created.email, 'client@example.test');
  assert.equal(created.email_confirm, false);
  const registration = f.calls.find(c => c.name === 'register_customer_account');
  assert.equal(registration.args.p_name, 'Cliente');
  assert.equal(registration.args.p_email, 'client@example.test');
  assert.deepEqual(await response.json(), { customerId: 'fixture-customer' });
});
test('customer function reuses existing Auth accounts without creating duplicates', async () => {
  const f = fixture({ existing: true });
  assert.equal((await f.request()).status, 200);
  assert.equal(f.calls.some(c => c.name === 'createUser'), false);
  assert.equal(f.calls.filter(c => c.name === 'register_customer_account').length, 1);
});
test('customer function does not register profiles when Auth creation fails', async () => {
  const f = fixture({ creationError: true });
  assert.equal((await f.request()).status, 400);
  assert.equal(f.calls.some(c => c.name === 'register_customer_account'), false);
});
test('customer function preflight and unsupported methods never access Auth or database', async () => {
  const f = fixture();
  assert.equal((await f.request(undefined, '', 'OPTIONS')).status, 200);
  assert.equal((await f.request(undefined, '', 'GET')).status, 405);
  assert.equal(f.calls.length, 0);
});

test('customer function rejects invalid phones and malformed JSON bodies before provisioning',async()=>{
 for(const body of [null,[],{name:'Cliente',email:'client@example.test',phone:'invalid'}]){const f=fixture();assert.equal((await f.request(body)).status,400);noAccountWrites(f);}
});
test('customer edits preserve identity and use the privileged Auth API only after exact-address authorization',async()=>{
 const f=fixture();const response=await f.request({action:'update',customerId:'32000000-0000-4000-8000-000000000001',name:'Cliente',email:'updated@example.test',phone:'+55 82 99999-0000'});assert.equal(response.status,200);assert.equal(f.calls.some(c=>c.name==='createUser'),false);const i=f.calls.findIndex(c=>c.name==='prepare_customer_email');const j=f.calls.findIndex(c=>c.name==='updateUserById');assert.ok(i<j);assert.equal(f.calls[j].id,'existing-user');assert.equal(f.calls[j].data.email,'updated@example.test');assert.equal(f.calls[j].data.email_confirm,false);assert.ok(f.calls.some(c=>c.name==='cancel_customer_email'));
});
test('a refused email authorization never calls the Auth update API',async()=>{
 const f=fixture({permissionError:true});assert.equal((await f.request({action:'update',customerId:'32000000-0000-4000-8000-000000000001',name:'Cliente',email:'taken@example.test'})).status,400);assert.equal(f.calls.some(c=>c.name==='updateUserById'),false);
});
test('failed Auth updates clear the pending authorization and report partial contact success',async()=>{
 const f=fixture({updateError:true});const result=await f.request({action:'update',customerId:'32000000-0000-4000-8000-000000000001',name:'Cliente',email:'updated@example.test'});assert.equal(result.status,400);assert.match((await result.json()).error,/Nome e telefone salvos/);assert.ok(f.calls.some(c=>c.name==='cancel_customer_email'));
});
