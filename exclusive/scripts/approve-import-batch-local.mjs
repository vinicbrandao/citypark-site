import { createClient } from '@supabase/supabase-js';
import { localEnvironment } from './local-env.mjs';

const batchId = process.argv[2];

if (!batchId) {
  throw new Error(
    'Informe o Batch ID. Exemplo: node scripts/approve-import-batch-local.mjs UUID',
  );
}

const { apiUrl, secretKey } = localEnvironment();

const supabase = createClient(
  apiUrl,
  secretKey,
  {
    auth: {
      persistSession: false,
      autoRefreshToken: false,
    },
  },
);

const { data, error } = await supabase.rpc(
  'approve_import_batch',
  {
    p_batch_id: batchId,
  },
);

if (error) {
  throw error;
}

console.log('');
console.log('Lote aprovado.');
console.log(`Batch ID: ${data.id}`);
console.log(`Status: ${data.status}`);
console.log(`Aceitos: ${data.accepted_rows}`);
console.log(`Repetidos: ${data.repeated_rows}`);
console.log(`Pendentes: ${data.pending_rows}`);