const {test}=require('node:test');
const assert=require('node:assert/strict');
const {readFileSync}=require('node:fs');
const {stripTypeScriptTypes}=require('node:module');
const vm=require('node:vm');
const source=stripTypeScriptTypes(readFileSync('supabase/functions/deadline-reminders/index.ts','utf8').replace(/^import[^\n]+\n/,''));
function setup(options={}) {
 const token='fixture-worker-token-32-characters-minimum';
 const env={DEADLINE_REMINDER_TOKEN:token,DEADLINE_EMAIL_PROVIDER:'resend',RESEND_API_KEY:'fixture-private-key',DEADLINE_EMAIL_FROM:'Exclusive <access@example.test>',...options.env};
 const calls=[],requests=[];let handler;
 const rows=options.rows||[{id:'notice-15',recipient:'owner@example.test',unit_code:'1505A',module_name:null,deadline:'2026-11-13T15:00:00Z',days_before:15}];
 const service={async rpc(name,args){calls.push({name,args});if(name==='deadline_notification_eligible')return {data:options.ineligible?false:true,error:options.eligibilityError?{}:null};if(name==='claim_deadline_notifications')return {data:rows,error:options.claimError?{}:null};return {error:options.finishError?{}:null};}};
 vm.runInNewContext(source,{Response,URL,Intl,Date,AbortSignal,Error,Promise,setTimeout:resolve=>resolve(),
  Deno:{env:{get:name=>env[name]},serve:fn=>handler=fn},createClient:()=>service,
  fetch:async(url,init)=>{requests.push({url,...init,body:JSON.parse(init.body)});if(options.networkError)throw Error('secret-containing transport exception');return {ok:!options.httpError,status:options.httpError||200,json:async()=>options.noReceipt?{}:{id:'provider-receipt'}};}
 });
 return {calls,requests,run:(authorization=`Bearer ${token}`,method='POST')=>handler({method,headers:new Headers(authorization?{Authorization:authorization}:{})})};
}
test('worker rejects unauthenticated and wrong-secret requests without accessing the queue',async()=>{
 const f=setup();assert.equal((await f.run('')).status,401);assert.equal((await f.run('Bearer invalid')).status,401);assert.equal((await f.run(undefined,'GET')).status,401);assert.equal(f.calls.length,0);
});
test('missing provider configuration fails before reserving any notification',async()=>{
 const f=setup({env:{RESEND_API_KEY:''}});assert.equal((await f.run()).status,503);assert.equal(f.calls.length,0);
});
test('a matching but short worker secret is refused before accessing the queue',async()=>{
 const f=setup({env:{DEADLINE_REMINDER_TOKEN:'short'}});assert.equal((await f.run('Bearer short')).status,401);assert.equal(f.calls.length,0);
});
test('invalid webhook endpoints fail closed without reserving notifications',async()=>{
 for(const url of ['invalid','http://external.example.test','ftp://localhost']) {const f=setup({env:{DEADLINE_EMAIL_PROVIDER:'webhook',DEADLINE_EMAIL_WEBHOOK_URL:url,DEADLINE_EMAIL_WEBHOOK_TOKEN:'fixture'}});assert.equal((await f.run()).status,503);assert.equal(f.calls.length,0);}
});
test('Resend receives an idempotency key, official sender and Sao Paulo deadline',async()=>{
 const f=setup();assert.equal((await f.run()).status,200);const sent=f.requests[0];assert.equal(sent.url,'https://api.resend.com/emails');assert.equal(sent.headers['Idempotency-Key'],'notice-15');assert.equal(sent.body.from,'Exclusive <access@example.test>');assert.deepEqual(Array.from(sent.body.to),['owner@example.test']);assert.match(sent.body.text,/Faltam 15 dias/);assert.match(sent.body.text,/13\/11\/2026, 12:00/);assert.equal(f.calls[0].args.p_limit,10);assert.equal(f.calls.find(c=>c.name==='finish_deadline_notification').args.p_success,true);
});
test('all four milestones render with module name and correct singular wording',async()=>{
 for(const days of [15,10,5,1]) {const f=setup({rows:[{id:'module-'+days,recipient:'owner@example.test',unit_code:'1505A',module_name:'Planta',deadline:'2026-11-13T15:00:00Z',days_before:days}]});await f.run();const text=f.requests[0].body.text;assert.match(text,/módulo Planta da unidade 1505A/);assert.ok(text.includes(days===1?'Falta 1 dia':`Faltam ${days} dias`));}
});
test('HTTP failure, missing provider receipt and network failure never mark a message sent',async()=>{
 for(const option of [{httpError:429},{noReceipt:true},{networkError:true}]){const f=setup(option);assert.deepEqual(await (await f.run()).json(),{sent:0,failed:1});assert.equal(f.calls.find(c=>c.name==='finish_deadline_notification').args.p_success,false);assert.ok(!f.calls.find(c=>c.name==='finish_deadline_notification').args.p_error.includes('secret-containing'));}
});
test('a delivery-record failure returns an error; retry uses exactly the same key and body',async()=>{
 const f=setup({finishError:true});assert.equal((await f.run()).status,500);assert.equal((await f.run()).status,500);assert.equal(f.requests[0].headers['Idempotency-Key'],f.requests[1].headers['Idempotency-Key']);assert.equal(JSON.stringify(f.requests[0].body),JSON.stringify(f.requests[1].body));
});
test('empty queue does not call provider, and claim failures are reported',async()=>{
 const f=setup({rows:[]});assert.deepEqual(await (await f.run()).json(),{sent:0,failed:0});assert.equal(f.requests.length,0);const bad=setup({claimError:true});assert.equal((await bad.run()).status,500);assert.equal(bad.requests.length,0);
});
test('existing local HTTP mock transport remains supported',async()=>{
 const f=setup({env:{DEADLINE_EMAIL_PROVIDER:'webhook',DEADLINE_EMAIL_WEBHOOK_URL:'http://host.docker.internal:4000',DEADLINE_EMAIL_WEBHOOK_TOKEN:'mock-secret'}});assert.equal((await f.run()).status,200);assert.equal(f.requests[0].body.to,'owner@example.test');assert.equal(f.requests[0].body.id,'notice-15');
});

test('worker rechecks eligibility before sending and fails closed on revocation or lookup failure',async()=>{
 for(const options of [{ineligible:true},{eligibilityError:true}]) {const f=setup(options);assert.deepEqual(await (await f.run()).json(),{sent:0,failed:1});assert.equal(f.requests.length,0);assert.equal(f.calls.find(c=>c.name==='finish_deadline_notification').args.p_success,false);}
});
