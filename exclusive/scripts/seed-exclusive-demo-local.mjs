import { createClient } from '@supabase/supabase-js';
import { localEnvironment } from './local-env.mjs';

const { apiUrl, secretKey } = localEnvironment();
const admin = createClient(apiUrl, secretKey, {
  auth: { persistSession: false, autoRefreshToken: false }
});
const check = result => { if (result.error) throw result.error; return result.data; };

const units = check(await admin.from('units').select('id,code'));
const byCode = new Map(units.map(unit => [unit.code, unit]));
const assignments = [
  { code: 'DEMO-PLANTA-09', name: 'Planta de demonstração · terminação 09', units: ['1209A'] },
  { code: 'DEMO-PLANTA-10', name: 'Planta de demonstração · terminação 10', units: ['1210A'] },
  { code: 'DEMO-PLANTA-GERAL', name: 'Planta de demonstração · demais unidades', units: ['1301A', '1302A', '1401A', '1501A', '1502A', '1503A', '1505A'] }
];
for (const entry of assignments) for (const code of entry.units) {
  if (!byCode.has(code)) throw new Error(`Unidade fictícia ${code} ausente. Rode npm run db:seed-local antes.`);
}

check(await admin.from('customization_modules').upsert([
  { code: 'planta', name: 'Planta', active: true, sort_order: 0 },
  { code: 'bancadas', name: 'Bancadas', active: true, sort_order: 1 }
], { onConflict: 'code' }));

const groupDefs = [
  { code: 'DEMO-AREA-SOCIAL', name: 'Área social', module_code: 'planta', sort_order: 0,
    options: [
      ['padrao', 'Padrão', 'Mantém a configuração original de demonstração.'],
      ['euroglass', 'Padrão + Euroglass', 'Inclui fechamento Euroglass de demonstração.'],
      ['integrada', 'Sala e varanda integradas + Euroglass', 'Integração usada somente no cenário de teste.'],
      ['ilha', 'Sala, varanda e cozinha integradas com ilha + Euroglass', 'Integra os três ambientes no cenário de teste.']
    ] },
  { code: 'DEMO-SUITE-MASTER', name: 'Suíte Master', module_code: 'planta', sort_order: 1,
    options: [
      ['padrao', 'Suíte padrão', 'Mantém a suíte de demonstração.'],
      ['closet', 'Suíte Master ampliada + closet', 'Ampliação e closet de demonstração.'],
      ['gabinete', 'Suíte Master ampliada + gabinete/quarto', 'Reconfiguração usada somente para teste.']
    ] },
  { code: 'DEMO-BANCADA', name: 'Bancada da cozinha', module_code: 'bancadas', sort_order: 0,
    options: [
      ['padrao', 'Bancada padrão', 'Configuração de teste.'],
      ['estendida', 'Bancada estendida', 'Configuração de teste com bancada maior.']
    ] },
  { code: 'DEMO-GRANITO', name: 'Granito', module_code: 'bancadas', sort_order: 1,
    options: [
      ['sao-marco', 'São Marco', 'Material de teste; preço ainda não oficial.'],
      ['bellagio', 'Bellagio', 'Material de teste; preço ainda não oficial.']
    ] },
  { code: 'DEMO-RODAMAO', name: 'Rodamão', module_code: 'bancadas', sort_order: 2,
    options: [
      ['padrao', 'Altura padrão', 'Configuração de teste.'],
      ['60', 'Rodamão 60 cm', 'Configuração de teste.']
    ] },
  { code: 'DEMO-SERVICO', name: 'Serviço', module_code: 'bancadas', sort_order: 3,
    options: [
      ['padrao', 'Configuração padrão', 'Tanque padrão no cenário de teste.'],
      ['bancada', 'Adicionar bancada de serviço', 'Bancada adicional no cenário de teste.']
    ] }
];
const optionIds = new Map();
const groupIds = new Map();
for (const definition of groupDefs) {
  const group = check(await admin.from('customization_groups').upsert({
    code: definition.code, name: definition.name, module_code: definition.module_code,
    sort_order: definition.sort_order, status: 'active', required_for_submission: true
  }, { onConflict: 'code' }).select('id').single());
  groupIds.set(definition.code, group.id);
  for (const [code, name, description] of definition.options) {
    const option = check(await admin.from('customization_options').upsert({
      group_id: group.id, code, name, description, status: 'active'
    }, { onConflict: 'group_id,code' }).select('id').single());
    optionIds.set(`${definition.code}:${code}`, option.id);
  }
}

const planIds = new Map();
for (const entry of assignments) {
  const plan = check(await admin.from('base_plans').upsert({
    code: entry.code, name: entry.name, status: 'active'
  }, { onConflict: 'code' }).select('id').single());
  planIds.set(entry.code, plan.id);
  for (const unitCode of entry.units) {
    check(await admin.from('unit_base_plan_assignments').upsert({
      unit_id: byCode.get(unitCode).id, base_plan_id: plan.id
    }, { onConflict: 'unit_id' }));
  }
}

for (const entry of assignments) {
  const available = [...optionIds.entries()]
    .filter(([key]) => !(entry.code === 'DEMO-PLANTA-10' && key === 'DEMO-AREA-SOCIAL:ilha'));
  check(await admin.from('base_plan_option_availability').upsert(
    available.map(([, option_id]) => ({ base_plan_id: planIds.get(entry.code), option_id })),
    { onConflict: 'base_plan_id,option_id' }
  ));
}

for (const base_plan_id of planIds.values()) {
  check(await admin.from('base_plan_option_defaults').upsert(groupDefs.map(g => ({
    base_plan_id, group_id: groupIds.get(g.code), option_id: optionIds.get(g.code + ':' + g.options[0][0])
  })), { onConflict: 'base_plan_id,group_id' }));
}

// Explicit demonstration metadata; never infer official areas from a unit code.
const demoAreas = { '1209A': 99.90 };
for (const unitCode of assignments.flatMap(entry => entry.units)) {
  check(await admin.from('units').update({
    customization_closes_at: null,
    ...(demoAreas[unitCode] ? { area_m2: demoAreas[unitCode] } : {})
  }).eq('id', byCode.get(unitCode).id));
  check(await admin.from('unit_module_windows').delete().eq('unit_id', byCode.get(unitCode).id));
}

const users = check(await admin.auth.admin.listUsers({ perPage: 1000 })).users;
const demoPassword = 'CityparkTeste2026!';
const demoEmails = [
  'cliente.a@example.test', 'cliente.b@example.test', 'cliente.d@example.test',
  'cliente.e@example.test', 'architect.1@example.test'
];
for (const email of demoEmails) {
  const user = users.find(entry => entry.email === email);
  if (!user) throw new Error(`Conta ${email} ausente. Rode os seeds locais de clientes e equipe.`);
  check(await admin.auth.admin.updateUserById(user.id, { password: demoPassword }));
}

console.log('Catálogo, plantas, opções e prazos de DEMONSTRAÇÃO cadastrados apenas no Supabase local.');
console.log('Teste com cliente.a@example.test (1209A), cliente.b@example.test (1210A), cliente.d@example.test (1401A), e architect.1@example.test.');
console.log(`Senha das contas de teste: ${demoPassword}`);
console.log('Nenhum dado oficial foi cadastrado.');
