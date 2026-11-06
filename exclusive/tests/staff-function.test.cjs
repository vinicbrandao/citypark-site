const {test}=require('node:test');
const assert=require('node:assert/strict');
const {readFileSync}=require('node:fs');
const {stripTypeScriptTypes}=require('node:module');
const vm=require('node:vm');
const source=stripTypeScriptTypes(readFileSync('supabase/functions/admin-staff/index.ts','utf8').replace(/^import[^\n]+\n/,''));
function fixture(options={}) {
 const calls=[];let handler;
 const user={auth:{async getUser(){return {data:{user:options.invalid?null:{id:'admin'}},error:options.invalid?{}:null};}},async rpc(name,args){
  calls.push({name,args});
  if(name==='current_staff_role')return {data:options.role??'admin'};
  if(name==='find_customer_auth_user')return {data:options.existing?'existing':null};
  if(name==='manage_staff')return {data:'staff-id',error:options.refused?{}:null};
  throw Error(name);
 }};
 const service={auth:{admin:{async createUser(data){calls.push({name:'createUser',data});return {error:options.createError?{}:null};}}}};
 vm.runInNewContext(source,{Response,Request,createClient:(_url,key)=>key==='service'?service:user,Deno:{serve:fn=>handler=fn,env:{get:name=>({SUPABASE_URL:'https://fixture.example.test',SUPABASE_ANON_KEY:'public',SUPABASE_SERVICE_ROLE_KEY:'service'})[name]}}});
 return {calls,run:(body={name:'Arquiteta',email:'architect@example.test',role:'architect',active:true},method='POST')=>handler(new Request('https://fixture.example.test/functions/v1/admin-staff',{method,headers:{Authorization:'Bearer fixture'},...(method==='POST'?{body:JSON.stringify(body)}:{})}))};
}
test('staff handler requires a real active Admin before any provisioning',async()=>{
 for(const options of [{invalid:true},{role:'architect'},{role:'customer'},{role:''}]){const f=fixture(options);assert.equal((await f.run()).status,403);assert.equal(f.calls.some(c=>['createUser','manage_staff'].includes(c.name)),false);}
});
test('staff handler validates profiles and never accepts arbitrary privileges',async()=>{
 for(const body of [null,[],{name:'X',email:'x@example.test',role:'owner',active:true},{name:'X',email:'x@example.test',role:'admin',active:'false'}]){const f=fixture();assert.equal((await f.run(body)).status,400);assert.equal(f.calls.some(c=>c.name==='createUser'),false);}
});
test('new staff identity has no operator-chosen password, invitation or confirmation bypass',async()=>{
 const f=fixture();assert.equal((await f.run()).status,200);const data=f.calls.find(c=>c.name==='createUser').data;assert.deepEqual(Object.keys(data).sort(),['email','email_confirm']);assert.equal(data.email_confirm,false);assert.equal(f.calls.at(-1).name,'manage_staff');
});
test('revocation preserves an existing identity and delegates protected-principal checks to the database',async()=>{
 const f=fixture({existing:true,refused:true});assert.equal((await f.run({name:'Principal',email:'exclusive@planoaengenharia.com.br',role:'admin',active:false})).status,400);assert.equal(f.calls.some(c=>c.name==='createUser'),false);assert.equal(f.calls.at(-1).name,'manage_staff');
});
test('failed creation and nonexistent revocation cannot grant a staff role',async()=>{
 const failed=fixture({createError:true});assert.equal((await failed.run()).status,400);assert.equal(failed.calls.some(c=>c.name==='manage_staff'),false);
 const absent=fixture();assert.equal((await absent.run({name:'Ausente',email:'absent@example.test',role:'admin',active:false})).status,400);assert.equal(absent.calls.some(c=>c.name==='createUser'),false);
});
test('staff preflight and unsupported requests do not access accounts',async()=>{
 const f=fixture();assert.equal((await f.run(undefined,'OPTIONS')).status,200);assert.equal((await f.run(undefined,'GET')).status,405);assert.equal(f.calls.length,0);
});
