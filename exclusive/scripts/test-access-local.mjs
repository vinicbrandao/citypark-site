import assert from 'node:assert/strict';
import { createClient } from '@supabase/supabase-js';
import { localEnvironment } from './local-env.mjs';

const {
  apiUrl,
  publicKey,
  secretKey
} = localEnvironment();

const options = {
  auth: {
    persistSession: false,
    autoRefreshToken: false
  }
};

const admin = createClient(
  apiUrl,
  secretKey,
  options
);

const anonymous = createClient(
  apiUrl,
  publicKey,
  options
);

const settingsResponse = await fetch(
  `${apiUrl}/auth/v1/settings`,
  {
    headers: {
      apikey: publicKey
    }
  }
);

assert.equal(
  settingsResponse.ok,
  true
);

const settings =
  await settingsResponse.json();

assert.equal(
  settings.external.email,
  true,
  'Email login provider must remain enabled'
);

assert.equal(
  settings.disable_signup,
  true,
  'Public signup must be disabled'
);

function check(result) {
  if (result.error) {
    throw result.error;
  }

  return result.data;
}

async function login(email) {
  const link = check(
    await admin.auth.admin.generateLink({
      type: 'magiclink',
      email
    })
  );

  const client = createClient(
    apiUrl,
    publicKey,
    options
  );

  check(
    await client.auth.verifyOtp({
      email,
      token: link.properties.email_otp,
      type: 'email'
    })
  );

  return client;
}

const clientA =
  await login('cliente.a@example.test');

const clientB =
  await login('cliente.b@example.test');

try {
  const aUnits = check(
    await clientA
      .from('units')
      .select('id,code')
      .order('code')
  );

  const bUnits = check(
    await clientB
      .from('units')
      .select('id,code')
      .order('code')
  );

  assert.deepEqual(
    aUnits.map(unit => unit.code),
    ['1209A']
  );

  assert.deepEqual(
    bUnits.map(unit => unit.code),
    ['1210A']
  );

  // Usuário anônimo não pode consultar unidades.
  assert.ok(
    (
      await anonymous
        .from('units')
        .select('id')
    ).error
  );

  // Cliente A não pode enxergar a unidade do Cliente B.
  assert.deepEqual(
    check(
      await clientA
        .from('units')
        .select('id,code')
        .eq(
          'id',
          bUnits[0].id
        )
    ),
    []
  );

  // Cliente não pode criar vínculos manualmente.
  assert.ok(
    (
      await clientA
        .from('customer_units')
        .insert({
          customer_id:
            '00000000-0000-4000-8000-000000000001',

          unit_id:
            bUnits[0].id,

          ownership_role:
            'owner'
        })
    ).error
  );

  // Mesmo chamando o RPC correto,
  // Cliente A não pode alterar a unidade de B.
  const foreignSave =
    await clientA.rpc(
      'save_unit_module_choices',
      {
        p_customer_id:
          '00000000-0000-4000-8000-000000000001',

        p_unit_id:
          bUnits[0].id,

        p_module_code:
          'planta',

        p_selections:
          {},

        p_expected_revision:
          0
      }
    );

  assert.equal(
    foreignSave.error?.code,
    '42501'
  );

  // As tabelas normalizadas não podem ser
  // alteradas diretamente pelo frontend.
  assert.ok(
    (
      await clientA
        .from('unit_module_selections')
        .update({
          option_id:
            crypto.randomUUID()
        })
        .eq(
          'unit_id',
          aUnits[0].id
        )
    ).error
  );

  // RLS também protege as propostas.
  assert.deepEqual(
    check(
      await clientA
        .from('unit_proposals')
        .select('id')
        .eq(
          'unit_id',
          bUnits[0].id
        )
    ),
    []
  );

  // Uma nova sessão continua vendo
  // apenas as unidades permitidas.
  const reopened =
    await login(
      'cliente.a@example.test'
    );

  try {
    assert.deepEqual(
      check(
        await reopened
          .from('units')
          .select('code')
          .order('code')
      ).map(unit => unit.code),

      ['1209A']
    );

  } finally {
    await reopened.auth.signOut();
  }

  // Cadastro público continua bloqueado.
  const signup =
    await anonymous.auth.signUp({
      email:
        'public-signup@example.test',

      password:
        crypto.randomUUID()
    });

  assert.ok(signup.error);

} finally {
  await Promise.all([
    clientA.auth.signOut(),
    clientB.auth.signOut()
  ]);
}

console.log(
  'PASS: OTP, isolamento entre clientes, bloqueio anônimo, proteção dos vínculos, RPC em unidade alheia, escrita direta negada, RLS de propostas e cadastro público bloqueado.'
);