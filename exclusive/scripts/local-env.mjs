import { authEmailEnvironment } from './auth-email-env.mjs';
import { execFileSync } from 'node:child_process';
import { createRequire } from 'node:module';
import { dirname, resolve } from 'node:path';
const require = createRequire(import.meta.url);
export function localEnvironment() {
  const packageDir = dirname(require.resolve('supabase/package.json'));
  const cli = resolve(packageDir, 'dist', 'supabase.js');
  const raw = execFileSync(process.execPath, [cli, 'status', '-o', 'json'], { encoding: 'utf8', env: { ...process.env, ...authEmailEnvironment() }, stdio: ['ignore', 'pipe', 'pipe'], timeout: 30000 });
  const status = JSON.parse(raw);
  const apiUrl = status.API_URL;
  if (!apiUrl || !['127.0.0.1', 'localhost'].includes(new URL(apiUrl).hostname)) throw new Error('Local Supabase only.');
  return { apiUrl, publicKey: status.PUBLISHABLE_KEY || status.ANON_KEY, secretKey: status.SECRET_KEY || status.SERVICE_ROLE_KEY };
}
