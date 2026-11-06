import { createClient } from 'npm:@supabase/supabase-js@2.116.0';
Deno.serve(async req => {
  const token = Deno.env.get('DEADLINE_REMINDER_TOKEN');
  if (req.method !== 'POST' || !token || token.length < 32 || req.headers.get('Authorization') !== `Bearer ${token}`) return new Response('Unauthorized', { status: 401 });
  const endpoint = Deno.env.get('DEADLINE_EMAIL_WEBHOOK_URL');
  const transportToken = Deno.env.get('DEADLINE_EMAIL_WEBHOOK_TOKEN');
  const provider = Deno.env.get('DEADLINE_EMAIL_PROVIDER') || 'webhook';
  const apiKey = Deno.env.get('RESEND_API_KEY');
  const from = Deno.env.get('DEADLINE_EMAIL_FROM');
  if (!['resend', 'webhook'].includes(provider)) return Response.json({ error: 'Invalid email provider.' }, { status: 503 });
  if (provider === 'resend' && (!apiKey || !from || /[\r\n]/.test(from))) return Response.json({ error: 'Resend is not configured.' }, { status: 503 });
  if (provider === 'webhook') {
    if (!endpoint || !transportToken) return Response.json({ error: 'Email transport is not configured.' }, { status: 503 });
    try {
      const parsed = new URL(endpoint);
      if (parsed.protocol !== 'https:' && !(parsed.protocol === 'http:' && ['localhost','127.0.0.1','host.docker.internal'].includes(parsed.hostname))) throw new Error();
    } catch { return Response.json({ error: 'HTTPS transport required.' }, { status: 503 }); }
  }
  const service = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!, { auth: { persistSession: false } });
  // Bounded sequential batch: avoid exceeding Edge wall time and provider bursts.
  const claimed = await service.rpc('claim_deadline_notifications', { p_limit: 10 });
  if (claimed.error) return Response.json({ error: 'Unable to claim reminders.' }, { status: 500 });
  let sent = 0; let failed = 0;
  for (const reminder of claimed.data) {
    let success = false; let error = null;
    try {
      const eligible = await service.rpc('deadline_notification_eligible', { p_id: reminder.id });
      if (eligible.error || eligible.data !== true) throw new Error('No longer eligible');
      const scope = reminder.module_name ? `do módulo ${reminder.module_name} da unidade ${reminder.unit_code}` : `da unidade ${reminder.unit_code}`;
      const date = new Intl.DateTimeFormat('pt-BR', { timeZone: 'America/Sao_Paulo', dateStyle: 'short', timeStyle: 'short' }).format(new Date(reminder.deadline));
      const subject = `CityPark Exclusive — prazo da unidade ${reminder.unit_code}`;
      const remaining = reminder.days_before === 1 ? 'Falta 1 dia' : `Faltam ${reminder.days_before} dias`;
      const text = `O prazo de personalização ${scope} está acabando! ${remaining} para o encerramento em ${date}.`;
      const payload = provider === 'resend' ? { from, to: [reminder.recipient], subject, text } :
        { id: reminder.id, to: reminder.recipient, subject, text, unitCode: reminder.unit_code, module: reminder.module_name, deadline: reminder.deadline, daysBefore: reminder.days_before };
      const response = await fetch(provider === 'resend' ? 'https://api.resend.com/emails' : endpoint!, { method: 'POST',
        headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${provider === 'resend' ? apiKey : transportToken}`, 'Idempotency-Key': reminder.id },
        body: JSON.stringify(payload), signal: AbortSignal.timeout(8000) });
      if (!response.ok) throw new Error(`Transport HTTP ${response.status}`);
      if (provider === 'resend' && !(await response.json()).id) throw new Error('Provider did not acknowledge the message');
      success = true; sent++;
    } catch (e) { error = e instanceof Error && /^Transport HTTP \d{3}$/.test(e.message) ? e.message : 'Transport failed'; failed++; }
    const saved = await service.rpc('finish_deadline_notification', { p_id: reminder.id, p_success: success, p_error: error });
    if (saved.error) return Response.json({ error: 'Unable to record delivery. Retry using the same idempotency key.' }, { status: 500 });
    // Pace calls below the default provider request rate; retries retain the same key.
    if (provider === 'resend') await new Promise(resolve => setTimeout(resolve, 600));
  }
  return Response.json({ sent, failed });
});
