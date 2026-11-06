import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { createRequire } from 'node:module';
import { mkdirSync } from 'node:fs';
import { resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';
import { localEnvironment } from './local-env.mjs';

// Uses a local browser and temporary accounts. No seed/reset is run.
const require = createRequire(import.meta.url);
const { chromium } = require(process.env.CITYPARK_PLAYWRIGHT_PATH || 'playwright');
const url = process.env.CITYPARK_UI_URL || 'http://127.0.0.1:5173/exclusive/';
assert.ok(['127.0.0.1', 'localhost'].includes(new URL(url).hostname), 'Local UI only');
const unitId = randomUUID();
const code = `E2E-CICLOS-${unitId.slice(0, 8)}`;
const customers = ['owner', 'co_owner'].map(role => ({
  id: randomUUID(), role, email: `e2e-proposal-${role}-${unitId}@example.test`, password: `${randomUUID()}T!`
}));
const { apiUrl, secretKey } = localEnvironment();
const admin = createClient(apiUrl, secretKey, { auth: { persistSession: false, autoRefreshToken: false } });
const architectEmail = `e2e-architect-${unitId}@example.test`;
const architectPassword = `${randomUUID()}T!`;

function sql(statement) {
  const result = spawnSync('docker', [
    'exec', '-i', 'supabase_db_citypark-exclusive',
    'psql', '-U', 'postgres', '-d', 'postgres', '-qAt', '-v', 'ON_ERROR_STOP=1'
  ], { input: statement, encoding: 'utf8', maxBuffer: 1024 * 1024 });
  if (result.error || result.status !== 0) {
    throw new Error((result.stderr || result.error?.message || 'Local SQL failed').trim());
  }
  return result.stdout.trim();
}

function proposals() {
  return JSON.parse(sql(`select coalesce(json_agg(p order by cycle_number), '[]')
    from (select id, cycle_number, latest_revision, status from public.unit_proposals
          where unit_id = '${unitId}'::uuid) p;`));
}

let browser;
let created = false;
let architectId;
try {
  for (const customer of customers) {
    const account = await admin.auth.admin.createUser({ email: customer.email, password: customer.password, email_confirm: true });
    if (account.error) throw account.error;
    customer.userId = account.data.user.id;
  }
  const account = await admin.auth.admin.createUser({
    email: architectEmail, password: architectPassword, email_confirm: true
  });
  if (account.error) throw account.error;
  architectId = account.data.user.id;
  sql(`begin;
    do $$ begin
      if not exists (select 1 from public.unit_base_plan_assignments a
        join public.base_plans p on p.id = a.base_plan_id
        join public.units u on u.id = a.unit_id
        where u.code = '1401A' and p.code like 'DEMO-%') then
        raise exception 'Demo plan missing for 1401A';
      end if;
    end $$;
    insert into public.units(id, code, tower, floor_label, termination, typology)
      select '${unitId}'::uuid, '${code}', tower, floor_label, termination, typology
      from public.units where code = '1401A';
    ${customers.map(customer => `
      insert into public.customers(id,name) values ('${customer.id}'::uuid,'Cliente temporário de propostas E2E');
      insert into public.customer_users(customer_id,user_id) values ('${customer.id}'::uuid,'${customer.userId}'::uuid);
      insert into public.customer_units(customer_id,unit_id,ownership_role)
        values ('${customer.id}'::uuid,'${unitId}'::uuid,'${customer.role}');`).join('\n')}
    insert into public.staff_users(user_id, name, role)
      values ('${architectId}'::uuid, 'Arquiteta temporária E2E', 'architect');
    insert into public.staff_unit_assignments(user_id, unit_id)
      values ('${architectId}'::uuid, '${unitId}'::uuid);
    insert into public.architect_authorizations
      (unit_id, architect_user_id, granted_by_customer_id, granted_by_user_id)
      values ('${unitId}'::uuid, '${architectId}'::uuid, '${customers[0].id}'::uuid, '${customers[0].userId}'::uuid);
    insert into public.unit_base_plan_assignments(unit_id, base_plan_id)
      select '${unitId}'::uuid, a.base_plan_id from public.unit_base_plan_assignments a
      join public.units u on u.id = a.unit_id where u.code = '1401A';
    insert into public.unit_module_windows(unit_id, module_code, opens_at, closes_at)
      values ('${unitId}'::uuid, 'planta', now() - interval '1 day', now() + interval '1 day'),
             ('${unitId}'::uuid, 'bancadas', now() - interval '1 day', now() + interval '1 day');
    commit;`);
  created = true;
  browser = await chromium.launch({ channel: process.env.CITYPARK_BROWSER_CHANNEL || 'msedge', headless: true });
  const errors = [];
  async function login(email, testPassword) {
    const context = await browser.newContext({ viewport: { width: 1365, height: 768 } });
    const page = await context.newPage();
    page.on('pageerror', error => errors.push(error.message));
    await page.goto(url);
    await page.locator('#email').fill(email);
    await page.locator('#password').fill(testPassword);
    await page.locator('#login-form button').click();
    await page.locator(`[data-unit="${unitId}"]`).click();
    await page.locator('.config-shell').waitFor();
    return page;
  }
  async function reloadUnit(page) {
    await page.reload();
    await page.locator(`[data-unit="${unitId}"]`).click();
    await page.locator('.config-shell').waitFor();
  }
  async function review(page) {
    await page.locator('[data-action="review"]').click();
    await page.locator('.exclusive-workflow').waitFor();
  }
  async function edit(page) {
    await page.locator('[data-action="edit-proposal"]').click();
    await page.locator('.review-modal').waitFor({ state: 'hidden' });
  }
  async function choose(page, group, value) {
    await page.locator(`[data-plant-group="${group === 'socialPlant' ? 'social' : 'suite'}"]`).click();
    await page.locator(`[data-plant-choice="${group}"][data-value="${value}"]`).click();
  }
  async function save(page) {
    await page.locator('[data-action="save"]').click();
    await page.locator('.toast').filter({ hasText: 'Progresso salvo na sua unidade.' }).waitFor();
  }
  async function submit(page, cycle, revision) {
    const responsePromise = page.waitForResponse(response =>
      response.url().endsWith('/rpc/submit_unit_proposal') && response.request().method() === 'POST');
    await page.locator('[data-action="submit-proposal"]').click();
    const response = await responsePromise;
    const body = await response.json();
    assert.equal(response.ok(), true, JSON.stringify(body));
    assert.equal(body.cycle_number, cycle);
    assert.equal(body.latest_revision, revision);
    await page.waitForFunction(({ cycle, revision }) => {
      const text = document.querySelector('.exclusive-workflow')?.textContent.replace(/\s+/g, ' ');
      return text?.includes(`Proposta ${cycle}`) && text.includes(`Envio ${revision} de 4`);
    }, { cycle, revision });
  }

  const owner = await login(customers[0].email, customers[0].password);
  const coOwner = await login(customers[1].email, customers[1].password);
  const architect = await login(architectEmail, architectPassword);
  await choose(owner, 'socialPlant', 'social-original');
  await choose(owner, 'suitePlant', 'suite-standard');
  await save(owner);
  assert.equal(proposals().length, 0, 'Saving must not create a proposal');
  await review(owner);
  await submit(owner, 1, 1);
  const firstId = proposals()[0].id;
  console.log('OK: envio inicial 1/4 pela interface');

  await edit(owner);
  await choose(owner, 'socialPlant', 'social-standard');
  await save(owner);
  assert.equal(proposals()[0].latest_revision, 1, 'Draft save consumed a submission');
  await reloadUnit(architect);
  await review(architect);
  const rejectedReview = architect.waitForResponse(response =>
    response.url().endsWith('/rpc/review_unit_proposal') && response.request().method() === 'POST');
  await architect.locator('[data-action="review-approved"]').click();
  const rejection = await rejectedReview;
  assert.equal(rejection.ok(), false, 'Unsubmitted changes must block review');
  assert.match((await rejection.json()).message, /Proposal has unsent changes/);
  await architect.locator('.toast').filter({ hasText: 'Existem alterações salvas que o cliente ainda não reenviou.' }).waitFor();
  assert.equal(proposals()[0].status, 'open');
  console.log('OK: salvar mantém 1/4 e rascunho não reenviado bloqueia parecer');
  await review(owner);
  await submit(owner, 1, 2);

  await reloadUnit(coOwner);
  await review(coOwner);
  await edit(coOwner);
  await choose(coOwner, 'suitePlant', 'suite-closet');
  await review(coOwner);
  await submit(coOwner, 1, 3);
  assert.equal(proposals()[0].id, firstId, 'Co-owner created a different proposal');
  console.log('OK: coproprietário reenvia a mesma proposta em 3/4');

  await reloadUnit(owner);
  await review(owner);
  await edit(owner);
  await choose(owner, 'socialPlant', 'social-veranda');
  await review(owner);
  await submit(owner, 1, 4);
  assert.equal(await owner.locator('[data-action="edit-proposal"]').count(), 0);
  assert.equal(await owner.locator('[data-action="submit-proposal"]').count(), 0);
  await owner.locator('[data-action="close-review"]').last().click();
  assert.equal(await owner.locator('[data-plant-choice]:enabled').count(), 0);
  await reloadUnit(architect);
  assert.equal(await architect.locator('[data-plant-choice]:enabled').count(), 0);
  console.log('OK: 4/4 bloqueia edição do cliente e da arquiteta');

  await review(architect);
  await architect.locator('#technical-note').fill('Parecer fictício para teste automatizado de ciclos.');
  const acceptedReview = architect.waitForResponse(response =>
    response.url().endsWith('/rpc/review_unit_proposal') && response.request().method() === 'POST');
  await architect.locator('[data-action="review-approved"]').click();
  assert.equal((await acceptedReview).ok(), true);
  await architect.locator('.exclusive-workflow').filter({ hasText: 'Viabilidade técnica confirmada' }).waitFor();
  await reloadUnit(owner);
  await review(owner);
  await owner.locator('[data-action="edit-proposal"]').filter({ hasText: 'Iniciar nova proposta' }).click();
  await choose(owner, 'socialPlant', 'social-full');
  await review(owner);
  await submit(owner, 2, 1);
  const cycles = proposals();
  assert.equal(cycles.length, 2);
  assert.equal(cycles[0].status, 'reviewed');
  assert.equal(cycles[0].latest_revision, 4);
  assert.equal(cycles[1].status, 'open');
  assert.equal(cycles[1].latest_revision, 1);
  assert.notEqual(cycles[1].id, firstId);
  assert.equal(sql(`select count(*) from public.unit_proposal_versions v
    join public.unit_proposals p on p.id = v.proposal_id where p.unit_id = '${unitId}'::uuid;`), '5');
  assert.deepEqual(errors, [], 'Unexpected browser errors');
  await owner.locator('[data-action="close-review"]').last().click();
  mkdirSync(resolve('outputs/qa'), { recursive: true });
  await owner.screenshot({ path: resolve('outputs/qa/proposal-cycle-local.png') });
  console.log('OK: parecer encerra ciclo 1; novo ciclo inicia em 1/4 e preserva cinco versões');
  console.log('OK: jornada de navegador concluída com o layout aprovado');
} catch (error) {
  for (const context of browser?.contexts() || []) {
    for (const page of context.pages()) {
      const message = await page.locator('.auth-message, .toast').allTextContents().catch(() => []);
      if (message.some(Boolean)) console.error('Mensagem da interface:', message.join(' '));
    }
  }
  throw error;
} finally {
  await browser?.close();
  if (created) {
    sql(`begin;
      do $$ begin
        if not exists (select 1 from public.units where id = '${unitId}'::uuid and code = '${code}') then
          raise exception 'Unexpected UI test fixture';
        end if;
      end $$;
      delete from public.unit_proposal_reviews where proposal_id in
        (select id from public.unit_proposals where unit_id = '${unitId}'::uuid);
      delete from public.unit_proposal_versions where proposal_id in
        (select id from public.unit_proposals where unit_id = '${unitId}'::uuid);
      delete from public.unit_proposals where unit_id = '${unitId}'::uuid;
      delete from public.unit_module_history where unit_id = '${unitId}'::uuid;
      delete from public.unit_module_selections where unit_id = '${unitId}'::uuid;
      delete from public.unit_module_states where unit_id = '${unitId}'::uuid;
      delete from public.unit_module_windows where unit_id = '${unitId}'::uuid;
      delete from public.unit_base_plan_assignments where unit_id = '${unitId}'::uuid;
      delete from public.architect_authorizations where unit_id = '${unitId}'::uuid;
      delete from public.staff_unit_assignments where unit_id = '${unitId}'::uuid;
      delete from public.customer_units where unit_id = '${unitId}'::uuid;
      ${customers.map(customer => `
        delete from public.customer_users where customer_id = '${customer.id}'::uuid;
        delete from public.customers where id = '${customer.id}'::uuid;`).join('\n')}
      delete from public.units where id = '${unitId}'::uuid and code = '${code}';
      delete from public.staff_users where user_id = '${architectId}'::uuid;
      commit;`);
    console.log('OK: somente a unidade temporária e seus registros foram removidos');
  }
  if (architectId) {
    const deleted = await admin.auth.admin.deleteUser(architectId);
    if (deleted.error) throw deleted.error;
    console.log('OK: conta temporária da arquiteta removida');
  }
  for (const customer of customers) {
    if (!customer.userId) continue;
    const deleted = await admin.auth.admin.deleteUser(customer.userId);
    if (deleted.error) throw deleted.error;
  }
  console.log('OK: contas temporárias de clientes removidas; credenciais existentes preservadas');
}
