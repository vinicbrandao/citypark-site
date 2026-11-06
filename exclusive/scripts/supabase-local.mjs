import { spawn } from 'node:child_process';
import { createRequire } from 'node:module';
import { dirname, resolve } from 'node:path';
import { authEmailEnvironment } from './auth-email-env.mjs';
const require=createRequire(import.meta.url);
const cli=resolve(dirname(require.resolve('supabase/package.json')),'dist','supabase.js');
const child=spawn(process.execPath,[cli,...process.argv.slice(2)],{stdio:'inherit',env:{...process.env,...authEmailEnvironment()}});
child.on('exit',code=>process.exit(code??1));
child.on('error',()=>{console.error('Não foi possível executar a CLI local.');process.exit(1);});
