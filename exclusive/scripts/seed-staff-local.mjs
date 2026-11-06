import {createClient} from '@supabase/supabase-js';
import {localEnvironment} from './local-env.mjs';
const {apiUrl,secretKey}=localEnvironment();const admin=createClient(apiUrl,secretKey,{auth:{persistSession:false,autoRefreshToken:false}});
const users=(await admin.auth.admin.listUsers({perPage:1000})).data.users;
for(const [role,n] of [['admin',3],['architect',2]])for(let i=1;i<=n;i++){
 const email=`${role}.${i}@example.test`;let user=users.find(u=>u.email===email);
 if(!user){const r=await admin.auth.admin.createUser({email,email_confirm:false});if(r.error)throw r.error;user=r.data.user;}
 const r=await admin.from('staff_users').upsert({user_id:user.id,name:`${role==='admin'?'Admin':'Arquiteta'} de teste ${i}`,role,active:true});if(r.error)throw r.error;
}
console.log('Perfis fictícios de equipe preparados somente no Supabase local. Nenhum e-mail enviado.');
