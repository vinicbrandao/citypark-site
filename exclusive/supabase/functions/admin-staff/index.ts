import { createClient } from 'npm:@supabase/supabase-js@2.116.0';
const cors = {'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'authorization, apikey, content-type, x-client-info'};
const json = (body:unknown,status=200) => new Response(JSON.stringify(body),{status,headers:{...cors,'Content-Type':'application/json'}});
Deno.serve(async req => {
  if(req.method==='OPTIONS') return new Response('ok',{headers:cors});
  if(req.method!=='POST') return json({error:'Método não permitido.'},405);
  const url=Deno.env.get('SUPABASE_URL')!;
  const user=createClient(url,Deno.env.get('SUPABASE_ANON_KEY')!,{global:{headers:{Authorization:req.headers.get('Authorization')||''}},auth:{persistSession:false}});
  const identity=await user.auth.getUser();
  const role=await user.rpc('current_staff_role');
  if(identity.error || !identity.data.user || role.error || role.data!=='admin') return json({error:'Acesso exclusivo do Admin.'},403);
  let body;
  try {body=await req.json();} catch {return json({error:'Dados inválidos.'},400);}
  if(!body || typeof body!=='object' || Array.isArray(body)) return json({error:'Dados inválidos.'},400);
  const email=String(body.email||'').trim().toLowerCase();
  const name=String(body.name||'').trim();
  if(!name || name.length>200 || email.length>254 || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) ||
    !['admin','architect'].includes(body.role) || typeof body.active!=='boolean') return json({error:'Confira nome, e-mail, perfil e status.'},400);
  const existing=await user.rpc('find_customer_auth_user',{p_email:email});
  if(existing.error) return json({error:'Não foi possível consultar a conta.'},400);
  if(!existing.data) {
    if(!body.active) return json({error:'Não existe conta para desativar.'},400);
    const service=createClient(url,Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,{auth:{persistSession:false}});
    const created=await service.auth.admin.createUser({email,email_confirm:false});
    if(created.error) return json({error:'Não foi possível criar a conta de acesso.'},400);
  }
  const managed=await user.rpc('manage_staff',{p_email:email,p_name:name,p_role:body.role,p_active:body.active});
  if(managed.error) return json({error:'Alteração recusada. O Admin principal é protegido, clientes não podem virar equipe e não é permitido revogar seu próprio acesso.'},400);
  return json({userId:managed.data});
});
