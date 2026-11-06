import assert from 'node:assert/strict';
import { createClient } from '@supabase/supabase-js';
import { localEnvironment } from './local-env.mjs';

const { apiUrl, publicKey, secretKey } = localEnvironment();

const options = {
  auth: {
    persistSession: false,
    autoRefreshToken: false,
  },
};

const admin = createClient(apiUrl, secretKey, options);

function check(result) {
  if (result.error) throw result.error;
  return result.data;
}

async function login(email) {
  const link = check(
    await admin.auth.admin.generateLink({
      type: 'magiclink',
      email,
    }),
  );

  const client = createClient(apiUrl, publicKey, options);

  check(
    await client.auth.verifyOtp({
      email,
      token: link.properties.email_otp,
      type: 'email',
    }),
  );

  return client;
}

const clientA = await login('cliente.a@example.test');
const clientC = await login('cliente.c@example.test');
const clientD = await login('cliente.d@example.test');
const clientE = await login('cliente.e@example.test');

// Cliente A continua vendo somente 1209A.
const aUnits = check(
  await clientA
    .from('units')
    .select('code')
    .order('code'),
);

assert.deepEqual(
  aUnits.map((unit) => unit.code),
  ['1209A'],
);

// Cliente C deve visualizar duas unidades.
const cUnits = check(
  await clientC
    .from('units')
    .select('code')
    .order('code'),
);

assert.deepEqual(
  cUnits.map((unit) => unit.code),
  ['1301A', '1302A'],
);

// Proprietário da 1401A.
const dUnits = check(
  await clientD
    .from('units')
    .select('code')
    .order('code'),
);

assert.deepEqual(
  dUnits.map((unit) => unit.code),
  ['1401A'],
);

// Coproprietário também deve acessar a 1401A.
const eUnits = check(
  await clientE
    .from('units')
    .select('code')
    .order('code'),
);

assert.deepEqual(
  eUnits.map((unit) => unit.code),
  ['1401A'],
);

// Confirma os papéis owner/co_owner.
const dOwnership = check(
  await clientD
    .from('customer_units')
    .select('ownership_role, units(code)')
    .single(),
);

assert.equal(dOwnership.ownership_role, 'owner');
assert.equal(dOwnership.units.code, '1401A');

const eOwnership = check(
  await clientE
    .from('customer_units')
    .select('ownership_role, units(code)')
    .single(),
);

assert.equal(eOwnership.ownership_role, 'co_owner');
assert.equal(eOwnership.units.code, '1401A');

// Cliente A não deve visualizar 1401A.
const unauthorized = check(
  await clientA
    .from('units')
    .select('code')
    .eq('code', '1401A'),
);

assert.deepEqual(unauthorized, []);

await Promise.all([
  clientA.auth.signOut(),
  clientC.auth.signOut(),
  clientD.auth.signOut(),
  clientE.auth.signOut(),
]);

console.log(
  'PASS: uma unidade, múltiplas unidades, proprietário, coproprietário e isolamento entre clientes.',
);