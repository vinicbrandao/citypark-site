import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { createRequire } from 'node:module';
import { mkdirSync } from 'node:fs';
import { resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';
import { localEnvironment } from './local-env.mjs';

const require = createRequire(import.meta.url);
const { chromium } = require(process.env.CITYPARK_PLAYWRIGHT_PATH || 'playwright');
const url = process.env.CITYPARK_UI_URL || 'http://127.0.0.1:5173/exclusive/';
assert.ok(['127.0.0.1', 'localhost'].includes(new URL(url).hostname), 'Local UI only');
const { apiUrl, secretKey } = localEnvironment();
const admin = createClient(apiUrl, secretKey, { auth: { persistSession: false, autoRefreshToken: false } });
const customerId = randomUUID();
const units = [0, 1, 2, 3, 4].map(() => randomUUID());
const unitList = units.map(id => `'${id}'::uuid`).join(',');
const email = `e2e-apartments-${customerId}@example.test`;
const password = `${randomUUID()}T!`;
let userId, browser, created = false;
const staffAccounts = [];

function sql(statement) {
  const result = spawnSync('docker', [
    'exec', '-i', 'supabase_db_citypark-exclusive', 'psql', '-U', 'postgres', '-d', 'postgres',
    '-qAt', '-v', 'ON_ERROR_STOP=1'
  ], { input: statement, encoding: 'utf8' });
  if (result.error || result.status !== 0) throw new Error((result.stderr || result.error?.message).trim());
  return result.stdout.trim();
}

try {
  const account = await admin.auth.admin.createUser({ email, password, email_confirm: true });
  if (account.error) throw account.error;
  userId = account.data.user.id;
  sql(`begin;
    insert into public.customers(id, name) values ('${customerId}'::uuid, 'Cliente temporário da seleção E2E');
    insert into public.customer_users(customer_id, user_id) values ('${customerId}'::uuid, '${userId}'::uuid);
    insert into public.units(id,code,tower,tower_code,floor_label,termination,typology,area_m2,customization_closes_at)
    values ('${units[0]}'::uuid,'9909A','Torre Liberty','A','99º andar','09A','3 Quartos',99.90,now()+interval '1 day'),
      ('${units[1]}'::uuid,'9908B','Torre Liberty','B','99º andar','10A','Quarto e sala',41.05,now()+interval '2 days'),
      ('${units[2]}'::uuid,'9809A','Torre Liberty','A','98º andar','09A','3 Quartos',99.90,now()-interval '1 day'),
      ('${units[3]}'::uuid,'9808B','Torre Liberty','B','98º andar','10A','Quarto e sala',41.05,now()+interval '2 days'),
      ('${units[4]}'::uuid,'9709A','Torre Liberty','A','97º andar','09A','3 Quartos',null,null);
    insert into public.customer_units(customer_id,unit_id) values ('${customerId}'::uuid,'${units[0]}'::uuid);
    insert into public.unit_base_plan_assignments(unit_id,base_plan_id)
      select x.id,a.base_plan_id from public.units x cross join public.unit_base_plan_assignments a
      join public.units source on source.id=a.unit_id join public.base_plans p on p.id=a.base_plan_id
      where x.id in (${unitList}) and source.code='1401A' and p.code like 'DEMO-%';
    insert into public.unit_module_windows(unit_id,module_code,opens_at,closes_at)
      select x.id,m.code,now()-interval '1 day',now()+interval '3 days'
      from public.units x cross join public.customization_modules m
      where x.id in (${unitList}) and m.code in ('planta','bancadas');
    commit;`);
  created = true;
  browser = await chromium.launch({ channel: process.env.CITYPARK_BROWSER_CHANNEL || 'msedge', headless: true });
  const context = await browser.newContext({ viewport: { width: 1365, height: 768 } });
  const page = await context.newPage();
  const errors = [];
  page.on('pageerror', error => errors.push(error.message));
  await page.goto(url);
  await page.locator('#email').fill(email);
  await page.locator('#password').fill(password);
  await page.locator('#login-form button').click();
  await page.locator('.apartment-card').waitFor();
  assert.equal(await page.locator('.apartment-card').count(), 1);
  const card = page.locator('.apartment-card');
  const singleBounds = await card.boundingBox();
  assert.ok(Math.abs(singleBounds.x + singleBounds.width / 2 - 1365 / 2) <= 1, 'Single card is not centered');
  assert.match(await card.innerText(), /9909 A/);
  assert.match(await card.innerText(), /Torre Liberty A/);
  assert.match(await card.innerText(), /99,90 m²/);
  assert.equal(await page.locator('article[data-unit]').count(), 0);
  assert.equal(await page.locator('[data-action="resume"]').count(), 0, 'Customer has an alternate entry outside the access button');
  mkdirSync(resolve('outputs/qa'), { recursive: true });
  await page.screenshot({ path: resolve('outputs/qa/apartment-selection-single.png') });
  await card.locator('img').click();
  await card.locator('h2').click();
  assert.equal(await page.locator('.apartment-selection').count(), 1, 'Card content unexpectedly opened unit');
  await card.click({ position: { x: 7, y: singleBounds.height - 7 } });
  assert.equal(await page.locator('.apartment-selection').count(), 1);
  const deadlineBox = await card.locator('.apartment-deadline time').boundingBox();
  const buttonBox = await card.locator('.apartment-access').boundingBox();
  assert.ok(deadlineBox.y > buttonBox.y && deadlineBox.x > singleBounds.x + singleBounds.width / 2);
  await card.locator('.apartment-access').focus();
  await page.keyboard.press('Enter');
  await page.locator('.config-shell').waitFor();
  await page.locator('[data-action="change-unit"]').click();
  await page.getByRole('heading', { name: 'Escolha seu apartamento' }).waitFor();
  console.log('OK: cartão único centralizado; imagem, texto e borda não abrem; botão funciona com teclado');

  sql(`insert into public.customer_units(customer_id,unit_id)
    values ('${customerId}'::uuid,'${units[1]}'::uuid),('${customerId}'::uuid,'${units[2]}'::uuid),('${customerId}'::uuid,'${units[3]}'::uuid);`);
  await page.reload();
  await page.locator('.apartment-card').nth(3).waitFor();
  const boxes = await Promise.all((await page.locator('.apartment-card').all()).map(item => item.boundingBox()));
  assert.ok(Math.abs(boxes[0].y - boxes[1].y) <= 1 && boxes[1].x > boxes[0].x);
  assert.ok(Math.abs(boxes[2].y - boxes[3].y) <= 1 && boxes[2].y > boxes[0].y);
  await page.locator('.unit-screen').evaluate(el => el.scrollTo(0, 0));
  await page.evaluate(() => window.scrollTo(0, 0));
  await page.screenshot({ path: resolve('outputs/qa/apartment-selection-grid.png') });
  sql(`insert into public.customer_units(customer_id,unit_id) values ('${customerId}'::uuid,'${units[4]}'::uuid);`);
  await page.reload();
  await page.locator('.apartment-card').nth(4).waitFor();
  const allBoxes = await Promise.all((await page.locator('.apartment-card').all()).map(item => item.boundingBox()));
  assert.equal(new Set(allBoxes.map(box => Math.round(box.y))).size, 3, 'Five cards should form three rows');
  const missing = page.locator(`[data-apartment-id="${units[4]}"]`);
  assert.match(await missing.innerText(), /Área a confirmar/);
  assert.match(await missing.innerText(), /A definir/);
  console.log('OK: quatro e cinco unidades seguem duas colunas; dados ausentes não são inventados');

  await page.setViewportSize({ width: 390, height: 844 });
  const mobileBoxes = await Promise.all((await page.locator('.apartment-card').all()).map(item => item.boundingBox()));
  assert.ok(mobileBoxes.every(box => box.width <= 358 && box.x >= 0 && box.x + box.width <= 390));
  assert.equal(new Set(mobileBoxes.map(box => Math.round(box.x))).size, 1, 'Mobile cards must have one column');
  assert.equal(await page.locator('.unit-selection-screen').evaluate(el => el.scrollWidth <= el.clientWidth), true);
  const mobileBrand = await page.locator('.wordmark').boundingBox();
  const mobileBack = await page.getByRole('button', { name: 'Voltar ao login', exact: true }).boundingBox();
  assert.ok(Math.abs(mobileBrand.y + mobileBrand.height / 2 - mobileBack.y - mobileBack.height / 2) <= 2,
    'Logo and back button must stay aligned on mobile');
  await page.locator('.unit-screen').evaluate(el => el.scrollTo(0, 0));
  await page.evaluate(() => window.scrollTo(0, 0));
  await page.screenshot({ path: resolve('outputs/qa/apartment-selection-mobile.png') });
  console.log('OK: celular sem rolagem horizontal e com uma coluna');

  await page.setViewportSize({ width: 1365, height: 768 });
  const expired = page.locator(`[data-apartment-id="${units[2]}"]`);
  assert.match(await expired.innerText(), /Prazo encerrado · somente consulta/);
  await expired.locator('.apartment-access').click();
  assert.equal(await page.locator('[data-plant-choice]:enabled').count(), 0);
  assert.equal(await page.locator('[data-action="save"]').isDisabled(), true);
  await page.locator('[data-nav="counters"]').click();
  assert.equal(await page.locator('[data-material-choice]:enabled').count(), 0);
  await page.locator('[data-action="review"]').click();
  assert.equal(await page.locator('[data-action="submit-proposal"]').count(), 0);
  await page.locator('[data-action="close-review"]').last().click();
  await page.locator('[data-action="change-unit"]').click();
  console.log('OK: unidade vencida permite consulta e bloqueia Planta, Bancadas, salvamento e envio');

  sql(`update public.units set customization_closes_at = clock_timestamp() + interval '6 seconds'
    where id = '${units[0]}'::uuid;`);
  await page.reload();
  await page.locator(`[data-unit="${units[0]}"]`).click();
  assert.ok(await page.locator('[data-plant-choice]:enabled').count() > 0);
  await page.waitForFunction(() => document.querySelector('[data-action="save"]')?.disabled === true,
    null, { timeout: 10000 });
  assert.equal(await page.locator('[data-plant-choice]:enabled').count(), 0);
  assert.deepEqual(errors, []);
  console.log('OK: vencimento durante a sessão bloqueia os controles automaticamente');
  await page.locator('[data-action="change-unit"]').click();
  await page.getByRole('button', { name: 'Voltar ao login', exact: true }).click();
  await page.locator('#login-form').waitFor();
  console.log('OK: Voltar ao login encerra a sessão');

  // All profiles share the screen, while RLS still determines visible units.
  for (const role of ['architect', 'admin']) {
    const staffPassword = `${randomUUID()}T!`;
    const staffEmail = `e2e-selection-${role}-${customerId}@example.test`;
    const staff = await admin.auth.admin.createUser({ email: staffEmail, password: staffPassword, email_confirm: true });
    if (staff.error) throw staff.error;
    const staffId = staff.data.user.id;
    staffAccounts.push(staffId);
    sql(`insert into public.staff_users(user_id,name,role)
      values ('${staffId}'::uuid,'Equipe temporária E2E','${role}');`);
    if (role === 'architect') {
      sql(`insert into public.staff_unit_assignments(user_id,unit_id)
        values ('${staffId}'::uuid,'${units[0]}'::uuid),('${staffId}'::uuid,'${units[1]}'::uuid),('${staffId}'::uuid,'${units[2]}'::uuid);
        insert into public.architect_authorizations(unit_id,architect_user_id,granted_by_customer_id,granted_by_user_id)
        values ('${units[0]}'::uuid,'${staffId}'::uuid,'${customerId}'::uuid,'${userId}'::uuid);`);
    }
    const staffContext = await browser.newContext({ viewport: { width: 1365, height: 768 } });
    const staffPage = await staffContext.newPage();
    staffPage.on('pageerror', error => errors.push(error.message));
    await staffPage.goto(url);
    await staffPage.locator('#email').fill(staffEmail);
    await staffPage.locator('#password').fill(staffPassword);
    await staffPage.locator('#login-form button').click();
    await staffPage.locator('.apartment-card').first().waitFor();
    assert.equal((await staffPage.locator('.apartment-profile').textContent()).trim(), role === 'admin' ? 'Administrador' : 'Arquiteta');
    assert.equal(await staffPage.locator('.unit-card, [data-action="resume"]').count(), 0);
    assert.equal(await staffPage.locator('article[data-unit]').count(), 0);
    if (role === 'architect') {
      assert.equal(await staffPage.locator('.apartment-card').count(), 1, 'Architect saw an unauthorized unit');
      const bounds = await staffPage.locator('.apartment-card').boundingBox();
      assert.ok(Math.abs(bounds.x + bounds.width / 2 - 1365 / 2) <= 1);
      sql(`insert into public.architect_authorizations(unit_id,architect_user_id,granted_by_customer_id,granted_by_user_id)
        values ('${units[1]}'::uuid,'${staffId}'::uuid,'${customerId}'::uuid,'${userId}'::uuid);`);
      await staffPage.reload();
      await staffPage.locator('.apartment-card').nth(1).waitFor();
      assert.equal(await staffPage.locator('.apartment-card').count(), 2);
      assert.equal(await staffPage.locator(`[data-apartment-id="${units[2]}"]`).count(), 0,
        'Assignment without authorization must not grant visibility');
    } else {
      assert.equal(await staffPage.locator('.apartment-card').count(), Number(sql('select count(*) from public.units where active;')));
    }
    const staffBoxes = await Promise.all((await staffPage.locator('.apartment-card').all()).map(item => item.boundingBox()));
    assert.ok(Math.abs(staffBoxes[0].y - staffBoxes[1].y) <= 1 && staffBoxes[1].x > staffBoxes[0].x);
    const target = staffPage.locator(`[data-apartment-id="${units[1]}"]`);
    await target.locator('img').click();
    await target.locator('h2').click();
    assert.equal(await staffPage.locator('.unit-selection-screen').count(), 1);
    await staffPage.locator('.unit-screen').evaluate(el => el.scrollTo(0, 0));
    await staffPage.evaluate(() => window.scrollTo(0, 0));
    await staffPage.screenshot({ path: resolve(`outputs/qa/apartment-selection-${role}.png`) });
    await staffPage.setViewportSize({ width: 390, height: 844 });
    const brand = await staffPage.locator('.wordmark').boundingBox();
    const back = await staffPage.getByRole('button', { name: 'Voltar ao login', exact: true }).boundingBox();
    assert.ok(Math.abs(brand.y + brand.height / 2 - back.y - back.height / 2) <= 2);
    assert.equal(await staffPage.locator('.unit-selection-screen').evaluate(el => el.scrollWidth <= el.clientWidth), true);
    const staffMobile = await staffPage.locator('.apartment-card').first().boundingBox();
    assert.ok(staffMobile.width <= 358);
    await staffPage.locator('.unit-screen').evaluate(el => el.scrollTo(0, 0));
    await staffPage.evaluate(() => window.scrollTo(0, 0));
    await staffPage.screenshot({ path: resolve(`outputs/qa/apartment-selection-${role}-mobile.png`) });
    await staffPage.setViewportSize({ width: 1365, height: 768 });
    await target.locator('.apartment-access').click();
    await staffPage.locator('.config-shell').waitFor();
    assert.match(await staffPage.locator('.header-actions').innerText(), /atendimento/);
    await staffPage.locator('[data-action="review"]').click();
    assert.equal(await staffPage.locator('[data-action="submit-proposal"]').count(), 0,
      'Staff must not gain the customer submission action');
    await staffPage.locator('[data-action="close-review"]').last().click();
    await staffPage.locator('[data-action="change-unit"]').click();
    await staffPage.getByRole('button', { name: 'Voltar ao login', exact: true }).click();
    await staffPage.locator('#login-form').waitFor();
    await staffContext.close();
    console.log(`OK: ${role} usa o padrão compartilhado no desktop/celular, somente o botão abre e as permissões são preservadas`);
  }
  assert.deepEqual(errors, []);
} finally {
  if (browser) await browser.close();
  if (created) {
    if (staffAccounts.length) {
      const staffList = staffAccounts.map(id => `'${id}'::uuid`).join(',');
      sql(`begin;
        delete from public.architect_authorizations where architect_user_id in (${staffList}) and unit_id in (${unitList});
        delete from public.staff_unit_assignments where user_id in (${staffList}) and unit_id in (${unitList});
        delete from public.staff_users where user_id in (${staffList});
        commit;`);
    }
    sql(`begin;
      delete from public.unit_module_windows where unit_id in (${unitList});
      delete from public.unit_base_plan_assignments where unit_id in (${unitList});
      delete from public.customer_units where customer_id = '${customerId}'::uuid and unit_id in (${unitList});
      delete from public.units where id in (${unitList}) and code in ('9909A','9908B','9809A','9808B','9709A');
      delete from public.customer_users where customer_id = '${customerId}'::uuid;
      delete from public.customers where id = '${customerId}'::uuid;
      commit;`);
  }
  for (const staffId of staffAccounts) {
    const deleted = await admin.auth.admin.deleteUser(staffId);
    if (deleted.error) throw deleted.error;
  }
  if (userId) {
    const deleted = await admin.auth.admin.deleteUser(userId);
    if (deleted.error) throw deleted.error;
  }
  console.log('OK: cliente, equipe e unidades temporárias removidos; dados existentes preservados');
}
