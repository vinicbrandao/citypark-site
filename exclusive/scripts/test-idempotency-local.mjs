import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createClient } from '@supabase/supabase-js';
import { localEnvironment } from './local-env.mjs';

const { apiUrl, secretKey } = localEnvironment();

const admin = createClient(apiUrl, secretKey, {
  auth: {
    persistSession: false,
    autoRefreshToken: false,
  },
});

function check(result) {
  if (result.error) throw result.error;
  return result.data;
}

async function countByExternalRef(table, externalRef) {
  const result = await admin
    .from(table)
    .select('*', { count: 'exact', head: true })
    .eq('external_ref', externalRef);

  if (result.error) throw result.error;

  return result.count ?? 0;
}

async function expectUniqueViolation(promise, label) {
  const result = await promise;

  assert.ok(
    result.error,
    `${label}: era esperado erro de duplicidade, mas a gravação foi aceita.`,
  );

  assert.equal(
    result.error.code,
    '23505',
    `${label}: era esperado PostgreSQL 23505, recebido ${result.error.code}.`,
  );
}

// -----------------------------------------------------------------------------
// 1. Confirma que os registros de referência existem uma única vez.
// -----------------------------------------------------------------------------

assert.equal(
  await countByExternalRef('customers', 'CLI-TESTE-003'),
  1,
  'Cliente C deveria existir exatamente uma vez.',
);

assert.equal(
  await countByExternalRef('units', 'UNI-TESTE-1301A'),
  1,
  'Unidade 1301A deveria existir exatamente uma vez.',
);

assert.equal(
  await countByExternalRef('customer_units', 'VINC-TESTE-003'),
  1,
  'Vínculo Cliente C -> 1301A deveria existir exatamente uma vez.',
);

// -----------------------------------------------------------------------------
// 2. Executa o mesmo seed novamente.
//    O número de registros deve continuar exatamente igual.
// -----------------------------------------------------------------------------

const scriptDirectory = dirname(fileURLToPath(import.meta.url));
const projectDirectory = resolve(scriptDirectory, '..');
const seedPath = resolve(scriptDirectory, 'seed-local.mjs');

execFileSync(process.execPath, [seedPath], {
  cwd: projectDirectory,
  stdio: 'ignore',
});

assert.equal(
  await countByExternalRef('customers', 'CLI-TESTE-003'),
  1,
  'Reexecutar o seed duplicou o Cliente C.',
);

assert.equal(
  await countByExternalRef('units', 'UNI-TESTE-1301A'),
  1,
  'Reexecutar o seed duplicou a unidade 1301A.',
);

assert.equal(
  await countByExternalRef('customer_units', 'VINC-TESTE-003'),
  1,
  'Reexecutar o seed duplicou o vínculo Cliente C -> 1301A.',
);

// -----------------------------------------------------------------------------
// 3. external_ref de cliente não pode ser reutilizado por outra pessoa.
// -----------------------------------------------------------------------------

const temporaryCustomerId = '00000000-0000-4000-8000-000000000099';

try {
  await expectUniqueViolation(
    admin.from('customers').insert({
      id: temporaryCustomerId,
      name: 'Cliente duplicado',
      email: 'duplicado@example.test',
      external_ref: 'CLI-TESTE-003',
    }),
    'customers.external_ref',
  );
} finally {
  await admin
    .from('customers')
    .delete()
    .eq('id', temporaryCustomerId);
}

// -----------------------------------------------------------------------------
// 4. external_ref de unidade não pode ser reutilizado.
// -----------------------------------------------------------------------------

const temporaryUnitId = '10000000-0000-4000-8000-000000000099';

try {
  await expectUniqueViolation(
    admin.from('units').insert({
      id: temporaryUnitId,
      code: '9999Z',
      tower: 'Torre Teste',
      floor_label: '99º andar',
      floor_number: 99,
      termination: '99Z',
      typology: 'Teste',
      external_ref: 'UNI-TESTE-1301A',
      active: true,
    }),
    'units.external_ref',
  );
} finally {
  await admin
    .from('units')
    .delete()
    .eq('id', temporaryUnitId);
}

// -----------------------------------------------------------------------------
// 5. external_ref de vínculo também não pode ser reutilizado.
// -----------------------------------------------------------------------------

try {
  await expectUniqueViolation(
    admin.from('customer_units').insert({
      customer_id: '00000000-0000-4000-8000-000000000001',
      unit_id: '10000000-0000-4000-8000-000000000002',
      ownership_role: 'owner',
      purchase_date: '2026-09-29',
      external_ref: 'VINC-TESTE-003',
      active: true,
    }),
    'customer_units.external_ref',
  );
} finally {
  await admin
    .from('customer_units')
    .delete()
    .eq('customer_id', '00000000-0000-4000-8000-000000000001')
    .eq('unit_id', '10000000-0000-4000-8000-000000000002');
}

// -----------------------------------------------------------------------------
// 6. Atualizar um registro existente mantém a mesma identidade.
// -----------------------------------------------------------------------------

const clienteC = check(
  await admin
    .from('customers')
    .select('id, name, email, external_ref')
    .eq('external_ref', 'CLI-TESTE-003')
    .single(),
);

check(
  await admin
    .from('customers')
    .update({
      name: clienteC.name,
      email: clienteC.email,
    })
    .eq('id', clienteC.id),
);

assert.equal(
  await countByExternalRef('customers', 'CLI-TESTE-003'),
  1,
  'Atualizar o Cliente C criou uma duplicação.',
);

console.log(
  'PASS: seed idempotente, external_ref único em clientes, unidades e vínculos, e atualização sem duplicação.',
);