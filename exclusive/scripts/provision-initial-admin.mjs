import { createClient } from '@supabase/supabase-js';
import { localEnvironment } from './local-env.mjs';
const local=process.argv.includes('--local');
const settings=local?localEnvironment():{apiUrl:process.env.SUPABASE_URL,secretKey:process.env.SUPABASE_SERVICE_ROLE_KEY};
if(!settings.apiUrl||!settings.secretKey)throw Error('Defina SUPABASE_URL e SUPABASE_SERVICE_ROLE_KEY no ambiente do servidor, ou use --local.');
const client=createClient(settings.apiUrl,settings.secretKey,{auth:{persistSession:false,autoRefreshToken:false}});
const email='exclusive@planoaengenharia.com.br';let account;
for(let page=1;page<=100&&!account;page++){const r=await client.auth.admin.listUsers({page,perPage:200});if(r.error)throw r.error;account=r.data.users.find(u=>u.email?.toLowerCase()===email);if(r.data.users.length<200)break;}
if(!account){const r=await client.auth.admin.createUser({email,email_confirm:false});if(r.error)throw r.error;account=r.data.user;}
const links=await client.from('customer_users').select('user_id').eq('user_id',account.id).eq('active',true);if(links.error)throw links.error;if(links.data.length)throw Error('Esta conta já possui perfil de cliente. Revise o cadastro antes de atribuir Admin.');
const saved=await client.from('staff_users').upsert({user_id:account.id,name:'Admin Exclusive',role:'admin',active:true});if(saved.error)throw saved.error;
console.log('Administrador inicial provisionado. Nenhum e-mail foi enviado; a senha será definida em Primeiro acesso.');
