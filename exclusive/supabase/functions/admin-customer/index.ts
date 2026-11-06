import { createClient } from 'npm:@supabase/supabase-js@2.116.0';
const cors = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, apikey, content-type, x-client-info' };
const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: { ...cors, 'Content-Type': 'application/json' } });
Deno.serve(async req => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  if (req.method !== 'POST') return json({ error: 'Método não permitido.' }, 405);
  const url = Deno.env.get('SUPABASE_URL')!;
  const auth = req.headers.get('Authorization') || '';
  const user = createClient(url, Deno.env.get('SUPABASE_ANON_KEY')!, { global: { headers: { Authorization: auth } }, auth: { persistSession: false } });
  const identity = await user.auth.getUser();
  const role = await user.rpc('current_staff_role');
  if (identity.error || !identity.data.user || role.error || role.data !== 'admin') return json({ error: 'Acesso exclusivo do Admin.' }, 403);
  let body;
  try { body = await req.json(); } catch { return json({ error: 'Dados inválidos.' }, 400); }
  if (!body || typeof body !== 'object' || Array.isArray(body)) return json({error:'Dados inválidos.'},400);
  const name = String(body.name || '').trim();
  const email = String(body.email || '').trim().toLowerCase();
  const phone = body.phone == null ? null : String(body.phone).trim() || null;
  const action = body.action || 'create';
  if (!['create','update'].includes(action) || !name || name.length > 200 || email.length > 254 || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) ||
      (phone && (phone.length > 40 || !/^[+0-9() .-]+$/.test(phone) || !/^\d{8,15}$/.test(phone.replace(/\D/g,''))))) return json({ error: 'Confira nome, e-mail e telefone.' }, 400);
  if (action === 'update') {
    if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(body.customerId || '')) return json({ error: 'Cliente inválido.' }, 400);
    const current = await user.from('customers').select('email').eq('id',body.customerId).single();
    if (current.error || !current.data) return json({ error: 'Cliente não encontrado.' }, 400);
    const contact = await user.rpc('update_customer_contact',{p_customer_id:body.customerId,p_name:name,p_phone:phone});
    if (contact.error) return json({ error: 'Não foi possível atualizar o contato.' },400);
    if (current.data.email.toLowerCase() !== email) {
      const permission = await user.rpc('prepare_customer_email',{p_customer_id:body.customerId,p_email:email});
      if (permission.error || !permission.data) return json({ error: 'Nome e telefone salvos. O e-mail não foi alterado: endereço em uso ou atualização em andamento.' },400);
      const service = createClient(url,Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,{auth:{persistSession:false}});
      let changed;
      try { changed = await service.auth.admin.updateUserById(permission.data,{email,email_confirm:false}); }
      catch { changed = {error:true}; }
      finally { await user.rpc('cancel_customer_email',{p_customer_id:body.customerId,p_email:email}); }
      if (changed.error) return json({ error: 'Nome e telefone salvos. Não foi possível alterar o e-mail; tente novamente.' },400);
    }
    return json({customerId:body.customerId});
  }
  const existing = await user.rpc('find_customer_auth_user', { p_email: email });
  if (existing.error) return json({ error: 'Não foi possível consultar a conta.' }, 400);
  if (!existing.data) {
    const service = createClient(url, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!, { auth: { persistSession: false } });
    // No invitation is sent. The customer confirms their e-mail on first access.
    const created = await service.auth.admin.createUser({ email, email_confirm: false });
    if (created.error) {
      const retry = await user.rpc('find_customer_auth_user', { p_email: email });
      if (!retry.data) return json({ error: 'Não foi possível criar a conta de acesso.' }, 400);
    }
  }
  const result = await user.rpc('register_customer_account', { p_name: name, p_email: email, p_phone: phone });
  if (result.error) return json({ error: 'Não foi possível cadastrar o cliente. Confira se o e-mail pertence a uma conta de equipe.' }, 400);
  return json({ customerId: result.data });
});
