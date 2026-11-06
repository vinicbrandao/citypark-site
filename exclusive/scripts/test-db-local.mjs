import { readFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';

const cases = [
  ['Sessões, acesso e prazos', 'test-session-requirements-local.sql'],
  ['Cadastro e lembretes', 'test-customer-reminders-local.sql'],
];

for (const [label, filename] of cases) {
  const sql = readFileSync(new URL(filename, import.meta.url), 'utf8');
  const result = spawnSync('docker', [
    'exec', '-i', 'supabase_db_citypark-exclusive',
    'psql', '-U', 'postgres', '-d', 'postgres',
    '-qAt', '-v', 'ON_ERROR_STOP=1',
  ], { input: sql, encoding: 'utf8', maxBuffer: 2 * 1024 * 1024 });

  if (result.error || result.status !== 0) {
    console.error(`FALHOU: ${label}`);
    const details = (result.stderr || result.stdout || result.error?.message || '')
      .trim().split(/\r?\n/).slice(-12).join('\n');
    if (details) console.error(details);
    console.error('Confira se o Docker Desktop e o Supabase local estão iniciados.');
    process.exit(1);
  }
  const pass = result.stdout.match(/^PASS:.*$/m)?.[0];
  if (!pass) {
    console.error(`FALHOU: ${label} não retornou a confirmação esperada.`);
    process.exit(1);
  }
  console.log(`OK: ${label}`);
}

console.log('Todos os testes do banco local passaram. Os dados temporários foram revertidos.');
