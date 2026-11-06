import { createClient } from '@supabase/supabase-js';
import { writeFileSync } from 'node:fs';
import { localEnvironment } from './local-env.mjs';

const { apiUrl, publicKey, secretKey } = localEnvironment();

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

const customers = [
  {
    email: 'cliente.a@example.test',
    customerId: '00000000-0000-4000-8000-000000000001',
    name: 'Cliente A',
    externalRef: 'CLI-TESTE-001',
  },
  {
    email: 'cliente.b@example.test',
    customerId: '00000000-0000-4000-8000-000000000002',
    name: 'Cliente B',
    externalRef: 'CLI-TESTE-002',
  },
  {
    email: 'cliente.c@example.test',
    customerId: '00000000-0000-4000-8000-000000000003',
    name: 'Cliente C',
    externalRef: 'CLI-TESTE-003',
  },
  {
    email: 'cliente.d@example.test',
    customerId: '00000000-0000-4000-8000-000000000004',
    name: 'Cliente D',
    externalRef: 'CLI-TESTE-004',
  },
  {
    email: 'cliente.e@example.test',
    customerId: '00000000-0000-4000-8000-000000000005',
    name: 'Cliente E',
    externalRef: 'CLI-TESTE-005',
  },
];

const units = [
  {
    id: '10000000-0000-4000-8000-000000000001',
    code: '1209A',
    tower: 'Torre Liberty',
    floorLabel: '12º andar',
    floorNumber: 12,
    termination: '09A',
    typology: '3 Quartos',
    externalRef: 'UNI-TESTE-1209A',
  },
  {
    id: '10000000-0000-4000-8000-000000000002',
    code: '1210A',
    tower: 'Torre Liberty',
    floorLabel: '12º andar',
    floorNumber: 12,
    termination: '10A',
    typology: '3 Quartos',
    externalRef: 'UNI-TESTE-1210A',
  },
  {
    id: '10000000-0000-4000-8000-000000000003',
    code: '1301A',
    tower: 'Torre Liberty',
    floorLabel: '13º andar',
    floorNumber: 13,
    termination: '01A',
    typology: '3 Quartos',
    externalRef: 'UNI-TESTE-1301A',
  },
  {
    id: '10000000-0000-4000-8000-000000000004',
    code: '1302A',
    tower: 'Torre Liberty',
    floorLabel: '13º andar',
    floorNumber: 13,
    termination: '02A',
    typology: '3 Quartos',
    externalRef: 'UNI-TESTE-1302A',
  },
  {
    id: '10000000-0000-4000-8000-000000000005',
    code: '1401A',
    tower: 'Torre Liberty',
    floorLabel: '14º andar',
    floorNumber: 14,
    termination: '01A',
    typology: '3 Quartos',
    externalRef: 'UNI-TESTE-1401A',
  },
];

const ownerships = [
  {
    customerId: customers[0].customerId,
    unitId: units[0].id,
    role: 'owner',
    purchaseDate: '2026-01-10',
    externalRef: 'VINC-TESTE-001',
  },
  {
    customerId: customers[1].customerId,
    unitId: units[1].id,
    role: 'owner',
    purchaseDate: '2026-02-15',
    externalRef: 'VINC-TESTE-002',
  },

  // Cliente C possui duas unidades.
  {
    customerId: customers[2].customerId,
    unitId: units[2].id,
    role: 'owner',
    purchaseDate: '2026-03-20',
    externalRef: 'VINC-TESTE-003',
  },
  {
    customerId: customers[2].customerId,
    unitId: units[3].id,
    role: 'owner',
    purchaseDate: '2026-06-05',
    externalRef: 'VINC-TESTE-004',
  },

  // Unidade 1401A possui uma única conta proprietária.
  {
    customerId: customers[3].customerId,
    unitId: units[4].id,
    role: 'owner',
    purchaseDate: '2026-07-12',
    externalRef: 'VINC-TESTE-005',
  },

];

const existingUsers = check(
  await admin.auth.admin.listUsers({ perPage: 1000 }),
).users;

for (const customer of customers) {
  let user = existingUsers.find(
    (existingUser) => existingUser.email === customer.email,
  );

  if (!user) {
    user = check(
      await admin.auth.admin.createUser({
        email: customer.email,
        email_confirm: true,
      }),
    ).user;
  }

  check(
    await admin.from('customers').upsert({
      id: customer.customerId,
      name: customer.name,
      email: customer.email,
      external_ref: customer.externalRef,
    }),
  );

  check(
    await admin.from('customer_users').upsert({
      customer_id: customer.customerId,
      user_id: user.id,
      active: true,
    }),
  );
}

for (const unit of units) {
  check(
    await admin.from('units').upsert({
      id: unit.id,
      code: unit.code,
      tower: unit.tower,
      floor_label: unit.floorLabel,
      floor_number: unit.floorNumber,
      termination: unit.termination,
      typology: unit.typology,
      external_ref: unit.externalRef,
      active: true,
    }),
  );
}

for (const ownership of ownerships) {
  check(
    await admin.from('customer_units').upsert({
      customer_id: ownership.customerId,
      unit_id: ownership.unitId,
      ownership_role: ownership.role,
      purchase_date: ownership.purchaseDate,
      external_ref: ownership.externalRef,
      active: true,
    }),
  );
}

writeFileSync(
  '.env.local',
  `VITE_SUPABASE_URL=${apiUrl}\nVITE_SUPABASE_PUBLISHABLE_KEY=${publicKey}\n`,
);

console.log('Dados locais de clientes e unidades atualizados.');
console.log('cliente.a@example.test -> 1209A');
console.log('cliente.b@example.test -> 1210A');
console.log('cliente.c@example.test -> 1301A e 1302A');
console.log('cliente.d@example.test -> 1401A (owner)');
console.log('cliente.e@example.test permanece sem unidade vinculada.');
console.log('Nenhum e-mail real foi enviado.');