import { createClient } from 'npm:@supabase/supabase-js@2.116.0';

Deno.serve(async request => {
  const token = Deno.env.get('COMMERCIAL_INVENTORY_TOKEN');
  if (request.method !== 'POST') return new Response(null, { status: 405 });
  if (!token || token.length < 32 || request.headers.get('Authorization') !== `Bearer ${token}`) {
    return new Response(null, { status: 401 });
  }

  let snapshot;
  try {
    const body = await request.text();
    if (body.length > 300_000) return new Response(null, { status: 413 });
    snapshot = JSON.parse(body);
    if (typeof snapshot?.capturedAt !== 'string' || !Array.isArray(snapshot.units)) {
      return new Response(null, { status: 400 });
    }
  } catch {
    return new Response(null, { status: 400 });
  }

  const client = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!, {
    auth: { persistSession: false }
  });
  const { data, error } = await client.rpc('sync_commercial_inventory', {
    p_captured_at: snapshot.capturedAt,
    p_units: snapshot.units
  });
  if (error) {
    const invalid = ['22007', '22008', '22023'].includes(error.code);
    return Response.json({ error: invalid ? 'Inventário inválido.' : 'Falha ao gravar inventário.' }, {
      status: invalid ? 422 : 500
    });
  }
  return Response.json(data);
});