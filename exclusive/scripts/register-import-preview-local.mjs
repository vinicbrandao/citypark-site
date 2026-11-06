import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import {
  readFileSync,
} from 'node:fs';
import {
  basename,
  dirname,
  resolve,
} from 'node:path';
import { fileURLToPath } from 'node:url';

import { createClient } from '@supabase/supabase-js';
import { localEnvironment } from './local-env.mjs';

const { apiUrl, secretKey } = localEnvironment();

const supabase = createClient(apiUrl, secretKey, {
  auth: {
    persistSession: false,
    autoRefreshToken: false,
  },
});

const scriptDirectory = dirname(
  fileURLToPath(import.meta.url),
);

const projectDirectory = resolve(
  scriptDirectory,
  '..',
);

const previewPath = process.argv[2]
  ? resolve(projectDirectory, process.argv[2])
  : resolve(
      scriptDirectory,
      'output',
      'import-preview.json',
    );

function check(result) {
  if (result.error) {
    throw result.error;
  }

  return result.data;
}

const preview = JSON.parse(
  readFileSync(previewPath, 'utf8'),
);

if (
  !preview.summary
  || !Array.isArray(preview.results)
  || !preview.input
) {
  throw new Error(
    'O arquivo de prévia não possui a estrutura esperada.',
  );
}

// ------------------------------------------------------------
// Hash do arquivo de origem.
//
// O mesmo CSV sempre produz o mesmo hash.
// Isso permite reconhecer que o arquivo já foi processado.
// ------------------------------------------------------------

const sourceContent = readFileSync(
  preview.input,
);

const sourceHash = createHash('sha256')
  .update(sourceContent)
  .digest('hex');

const sourceName = basename(preview.input);

// ------------------------------------------------------------
// Procura um lote já registrado para o mesmo arquivo.
// ------------------------------------------------------------

const existingBatch = check(
  await supabase
    .from('import_batches')
    .select('*')
    .eq('source_hash', sourceHash)
    .maybeSingle(),
);

let batch;

if (existingBatch) {
  if (existingBatch.status === 'applied') {
    throw new Error(
      'Este arquivo já pertence a um lote aplicado e não pode ter sua prévia sobrescrita.',
    );
  }

  batch = check(
    await supabase
      .from('import_batches')
      .update({
        source_name: sourceName,

        total_rows:
          preview.summary.total,

        accepted_rows:
          preview.summary.accepted,

        repeated_rows:
          preview.summary.repeated,

        pending_rows:
          preview.summary.pending,

        metadata: {
          preview_generated_at:
            preview.generatedAt ?? null,
        },
      })
      .eq('id', existingBatch.id)
      .select()
      .single(),
  );

  // Permite registrar novamente a mesma prévia
  // sem duplicar linhas.
  check(
    await supabase
      .from('import_rows')
      .delete()
      .eq('batch_id', batch.id),
  );
} else {
  batch = check(
    await supabase
      .from('import_batches')
      .insert({
        source_name: sourceName,
        source_hash: sourceHash,
        status: 'previewed',

        total_rows:
          preview.summary.total,

        accepted_rows:
          preview.summary.accepted,

        repeated_rows:
          preview.summary.repeated,

        pending_rows:
          preview.summary.pending,

        metadata: {
          preview_generated_at:
            preview.generatedAt ?? null,
        },
      })
      .select()
      .single(),
  );
}

// ------------------------------------------------------------
// Registra individualmente cada linha analisada.
// ------------------------------------------------------------

const rows = preview.results.map(
  (item) => ({
    batch_id: batch.id,

    line_number: item.line,

    status: item.status,
    reason: item.reason ?? null,

    customer_external_ref:
      item.data.customer_external_ref || null,

    unit_external_ref:
      item.data.unit_external_ref || null,

    link_external_ref:
      item.data.link_external_ref || null,

    raw_payload: item.data,

    normalized_payload: item.data,
  }),
);

if (rows.length > 0) {
  check(
    await supabase
      .from('import_rows')
      .insert(rows),
  );
}

// ------------------------------------------------------------
// Validação do que realmente foi persistido.
// ------------------------------------------------------------

const storedRows = check(
  await supabase
    .from('import_rows')
    .select('status')
    .eq('batch_id', batch.id),
);

assert.equal(
  storedRows.length,
  preview.summary.total,
  'Quantidade de linhas armazenadas é diferente da prévia.',
);

const accepted = storedRows.filter(
  (row) => row.status === 'aceito',
).length;

const repeated = storedRows.filter(
  (row) => row.status === 'repetido',
).length;

const pending = storedRows.filter(
  (row) => row.status === 'pendente',
).length;

assert.equal(
  accepted,
  preview.summary.accepted,
);

assert.equal(
  repeated,
  preview.summary.repeated,
);

assert.equal(
  pending,
  preview.summary.pending,
);

console.log('');
console.log('Lote de importação registrado.');
console.log(`Batch ID: ${batch.id}`);
console.log(`Arquivo: ${sourceName}`);
console.log(`Hash: ${sourceHash}`);
console.log('');

console.log(`Total: ${storedRows.length}`);
console.log(`Aceitos: ${accepted}`);
console.log(`Repetidos: ${repeated}`);
console.log(`Pendentes: ${pending}`);

console.log('');
console.log(
  'PASS: prévia registrada sem alterar clientes, unidades ou vínculos.',
);