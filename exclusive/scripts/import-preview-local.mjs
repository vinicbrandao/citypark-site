import { createClient } from '@supabase/supabase-js';
import {
  mkdirSync,
  readFileSync,
  writeFileSync,
} from 'node:fs';
import {
  dirname,
  resolve,
} from 'node:path';
import { fileURLToPath } from 'node:url';

import { localEnvironment } from './local-env.mjs';

const { apiUrl, secretKey } = localEnvironment();

const supabase = createClient(apiUrl, secretKey, {
  auth: {
    persistSession: false,
    autoRefreshToken: false,
  },
});

const scriptDirectory = dirname(fileURLToPath(import.meta.url));
const projectDirectory = resolve(scriptDirectory, '..');

const inputPath = process.argv[2]
  ? resolve(projectDirectory, process.argv[2])
  : resolve(
      scriptDirectory,
      'fixtures',
      'importacao-clientes-exemplo.csv',
    );

const outputDirectory = resolve(
  scriptDirectory,
  'output',
);

const outputPath = resolve(
  outputDirectory,
  'import-preview.json',
);

function normalize(value) {
  return String(value ?? '').trim();
}

function normalizeEmail(value) {
  return normalize(value).toLowerCase();
}

function isValidEmail(email) {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email);
}

function isValidDate(value) {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) {
    return false;
  }

  const date = new Date(`${value}T00:00:00Z`);

  return !Number.isNaN(date.getTime())
    && date.toISOString().slice(0, 10) === value;
}

function parseCsv(content) {
  const lines = content
    .replace(/^\uFEFF/, '')
    .split(/\r?\n/)
    .filter((line) => line.trim());

  if (lines.length < 2) {
    throw new Error(
      'O CSV precisa conter cabeçalho e pelo menos uma linha de dados.',
    );
  }

  const headers = lines[0]
    .split(';')
    .map((header) => normalize(header));

  return lines.slice(1).map((line, index) => {
    const values = line.split(';');

    const data = Object.fromEntries(
      headers.map((header, position) => [
        header,
        normalize(values[position]),
      ]),
    );

    return {
      lineNumber: index + 2,
      data,
    };
  });
}

function validateRow(row) {
  const errors = [];
  const data = row.data;

  const required = [
    ['customer_external_ref', 'external_ref do cliente'],
    ['customer_name', 'nome do cliente'],
    ['customer_email', 'e-mail do cliente'],
    ['unit_external_ref', 'external_ref da unidade'],
    ['unit_code', 'código da unidade'],
    ['tower', 'torre'],
    ['floor_number', 'pavimento'],
    ['termination', 'terminação'],
    ['typology', 'tipologia'],
    ['ownership_role', 'tipo de propriedade'],
    ['purchase_date', 'data da compra'],
    ['link_external_ref', 'external_ref do vínculo'],
  ];

  for (const [field, label] of required) {
    if (!data[field]) {
      errors.push(`${label} ausente`);
    }
  }

  data.customer_email = normalizeEmail(
    data.customer_email,
  );

  if (
    data.customer_email
    && !isValidEmail(data.customer_email)
  ) {
    errors.push('e-mail inválido');
  }

  if (
    data.floor_number
    && (
      !Number.isInteger(Number(data.floor_number))
      || Number(data.floor_number) < 0
    )
  ) {
    errors.push('pavimento inválido');
  }

  if (
    data.ownership_role
    && !['owner'].includes(
      data.ownership_role,
    )
  ) {
    errors.push(
      'ownership_role deve ser owner; coproprietário não possui conta separada',
    );
  }

  if (
    data.purchase_date
    && !isValidDate(data.purchase_date)
  ) {
    errors.push('data da compra inválida');
  }

  return errors;
}

async function findByExternalRef(
  table,
  externalRef,
  fields = '*',
) {
  const { data, error } = await supabase
    .from(table)
    .select(fields)
    .eq('external_ref', externalRef)
    .maybeSingle();

  if (error) {
    throw error;
  }

  return data;
}

function sameCustomer(existing, incoming) {
  return (
    normalize(existing.name) ===
      normalize(incoming.customer_name)
    && normalizeEmail(existing.email) ===
      normalizeEmail(incoming.customer_email)
  );
}

function sameUnit(existing, incoming) {
  return (
    normalize(existing.code) ===
      normalize(incoming.unit_code)
    && normalize(existing.tower) ===
      normalize(incoming.tower)
    && Number(existing.floor_number) ===
      Number(incoming.floor_number)
    && normalize(existing.termination) ===
      normalize(incoming.termination)
    && normalize(existing.typology) ===
      normalize(incoming.typology)
  );
}

async function classifyRow(row, seenLinks) {
  const validationErrors = validateRow(row);

  if (validationErrors.length) {
    return {
      line: row.lineNumber,
      status: 'pendente',
      reason: validationErrors.join('; '),
      data: row.data,
    };
  }

  const linkRef = row.data.link_external_ref;

  if (seenLinks.has(linkRef)) {
    return {
      line: row.lineNumber,
      status: 'repetido',
      reason:
        'external_ref do vínculo repetido dentro do próprio arquivo',
      data: row.data,
    };
  }

  seenLinks.add(linkRef);

  const [
    customer,
    unit,
    link,
  ] = await Promise.all([
    findByExternalRef(
      'customers',
      row.data.customer_external_ref,
      'id,name,email,external_ref',
    ),

    findByExternalRef(
      'units',
      row.data.unit_external_ref,
      'id,code,tower,floor_number,termination,typology,external_ref',
    ),

    findByExternalRef(
      'customer_units',
      row.data.link_external_ref,
      'customer_id,unit_id,ownership_role,purchase_date,external_ref',
    ),
  ]);

  if (
    customer
    && !sameCustomer(customer, row.data)
  ) {
    return {
      line: row.lineNumber,
      status: 'pendente',
      reason:
        'customer_external_ref já existe com dados diferentes',
      data: row.data,
    };
  }

  if (
    unit
    && !sameUnit(unit, row.data)
  ) {
    return {
      line: row.lineNumber,
      status: 'pendente',
      reason:
        'unit_external_ref já existe com dados diferentes',
      data: row.data,
    };
  }

  if (link) {
    return {
      line: row.lineNumber,
      status: 'repetido',
      reason:
        'vínculo já existe no banco',
      data: row.data,
    };
  }

  return {
    line: row.lineNumber,
    status: 'aceito',
    reason:
      customer || unit
        ? 'registro válido; reutilizará entidades existentes quando aplicável'
        : 'novo registro válido',
    data: row.data,
  };
}

const content = readFileSync(
  inputPath,
  'utf8',
);

const rows = parseCsv(content);

const results = [];
const seenLinks = new Set();

for (const row of rows) {
  results.push(
    await classifyRow(row, seenLinks),
  );
}

const summary = {
  total: results.length,
  accepted: results.filter(
    (item) => item.status === 'aceito',
  ).length,
  repeated: results.filter(
    (item) => item.status === 'repetido',
  ).length,
  pending: results.filter(
    (item) => item.status === 'pendente',
  ).length,
};

console.table(
  results.map((item) => ({
    linha: item.line,
    cliente:
      item.data.customer_external_ref,
    unidade:
      item.data.unit_code,
    vinculo:
      item.data.link_external_ref,
    status: item.status,
    motivo: item.reason,
  })),
);

console.log('');
console.log('Resumo da prévia:');
console.log(`Total: ${summary.total}`);
console.log(`Aceitos: ${summary.accepted}`);
console.log(`Repetidos: ${summary.repeated}`);
console.log(`Pendentes: ${summary.pending}`);

mkdirSync(outputDirectory, {
  recursive: true,
});

writeFileSync(
  outputPath,
  JSON.stringify(
    {
      generatedAt: new Date().toISOString(),
      input: inputPath,
      summary,
      results,
    },
    null,
    2,
  ),
  'utf8',
);

console.log('');
console.log(
  `Relatório criado em: ${outputPath}`,
);

console.log('');
console.log(
  'PREVIEW SOMENTE LEITURA: nenhuma alteração foi feita no banco.',
);