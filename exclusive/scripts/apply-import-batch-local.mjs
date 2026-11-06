import { createClient } from '@supabase/supabase-js';
import { localEnvironment } from './local-env.mjs';

const batchId = process.argv[2];

if (!batchId) {
  throw new Error(
    'Informe o Batch ID. Exemplo: node scripts/apply-import-batch-local.mjs UUID',
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
  'apply_import_batch',
  {
    p_batch_id: batchId,
  },
);

if (error) {
  throw error;
}

console.log('');
console.log('Resultado da aplicação:');
console.log(JSON.stringify(data, null, 2));