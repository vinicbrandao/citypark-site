import { existsSync, readFileSync } from 'node:fs';
import { parseEnv } from 'node:util';
export const smtpEnvPath = new URL('../supabase/.env.auth-smtp.local', import.meta.url);
const names = ['HOST','PORT','USER','PASS','FROM','SENDER_NAME'].map(name => `CITYPARK_AUTH_SMTP_${name}`);
export function authEmailEnvironment() {
  const saved = existsSync(smtpEnvPath) ? parseEnv(readFileSync(smtpEnvPath,'utf8')) : {};
  return Object.fromEntries(names.filter(name => process.env[name] !== undefined || saved[name] !== undefined)
    .map(name => [name, process.env[name] ?? saved[name]]));
}
