import { existsSync, readFileSync, writeFileSync, copyFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { createRequire } from 'node:module';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { authEmailEnvironment, smtpEnvPath } from './auth-email-env.mjs';
const args=new Set(process.argv.slice(2));
if(args.has('--init')) {
  if(!existsSync(smtpEnvPath))copyFileSync(new URL('../supabase/.env.auth-smtp.example',import.meta.url),smtpEnvPath);
  console.log('Arquivo privado preparado: '+fileURLToPath(smtpEnvPath));
  process.exit(0);
}
const useSmtp=args.has('--smtp');const useLocal=args.has('--local');
if(useSmtp&&useLocal)throw Error('Escolha apenas --smtp ou --local.');
const vars=authEmailEnvironment();
function validate(){
 for(const name of ['HOST','PORT','USER','PASS','FROM','SENDER_NAME']) {
  const value=vars['CITYPARK_AUTH_SMTP_'+name];
  if(!value||/[\r\n]/.test(value))throw Error('Preencha CITYPARK_AUTH_SMTP_'+name+' no arquivo privado.');
 }
 const port=Number(vars.CITYPARK_AUTH_SMTP_PORT);
 if(!Number.isInteger(port)||port<1||port>65535)throw Error('Porta SMTP inválida.');
 if(!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(vars.CITYPARK_AUTH_SMTP_FROM))throw Error('Remetente SMTP inválido.');
}
if(!useLocal)validate();
if(!useSmtp&&!useLocal){console.log('Campos SMTP preenchidos. Nenhum segredo foi exibido; use --smtp --restart para ativar.');process.exit(0);}
const configPath=new URL('../supabase/config.toml',import.meta.url);
let config=readFileSync(configPath,'utf8');
const begin='# BEGIN CITYPARK_AUTH_SMTP';const end='# END CITYPARK_AUTH_SMTP';
let block=begin+'\n';
if(useSmtp)block+=`[auth.email.smtp]\nenabled = true\nhost = "env(CITYPARK_AUTH_SMTP_HOST)"\nport = ${Number(vars.CITYPARK_AUTH_SMTP_PORT)}\nuser = "env(CITYPARK_AUTH_SMTP_USER)"\npass = "env(CITYPARK_AUTH_SMTP_PASS)"\nadmin_email = "env(CITYPARK_AUTH_SMTP_FROM)"\nsender_name = "env(CITYPARK_AUTH_SMTP_SENDER_NAME)"\n`;
else block+='# Local Auth mail is captured by Mailpit.\n';
block+=end;
if(!config.includes(begin)||!config.includes(end))throw Error('Bloco SMTP não encontrado no config.toml.');
config=config.slice(0,config.indexOf(begin))+block+config.slice(config.indexOf(end)+end.length);
writeFileSync(configPath,config);
const frontendPath=new URL('../.env.local',import.meta.url);
if(existsSync(frontendPath)){
 let frontend=readFileSync(frontendPath,'utf8');const value='VITE_AUTH_EMAIL_DELIVERY='+(useSmtp?'smtp':'local');
 frontend=frontend.match(/^VITE_AUTH_EMAIL_DELIVERY=.*$/m)?frontend.replace(/^VITE_AUTH_EMAIL_DELIVERY=.*$/m,value):frontend.trimEnd()+'\n'+value+'\n';writeFileSync(frontendPath,frontend);
}
console.log(useSmtp?'Configuração de envio real preparada.':'Configuração de caixa local preparada.');
if(args.has('--restart')) {
 const require=createRequire(import.meta.url);const cli=resolve(dirname(require.resolve('supabase/package.json')),'dist','supabase.js');
 for(const cliArgs of [['stop'],['start','--network-id','citypark-exclusive-local']]) {
  const result=spawnSync(process.execPath,[cli,...cliArgs],{encoding:'utf8',env:{...process.env,...vars},timeout:300000,maxBuffer:8*1024*1024});
  if(result.status!==0)throw Error('Falha ao reiniciar os serviços locais. Confira Docker e a configuração SMTP. Nenhuma senha foi exibida.');
 }
 console.log('Supabase local reiniciado com dados preservados.');
}else console.log('Reinicie os serviços para aplicar: npm run db:stop e npm run db:start.');
