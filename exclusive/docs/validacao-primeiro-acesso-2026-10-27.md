# Validação de cadastro e primeiro acesso — 27/10/2026

## Resultado

Fluxo corrigido e validado: criação administrativa da conta, vínculo à unidade, solicitação do código, recebimento de e-mail, confirmação, definição de senha e login posterior com senha. O responsável confirmou recebimento no Gmail e entrada no ambiente com a própria conta. O banco confirmou e-mail verificado e login realizado; a senha pessoal foi definida pelo próprio responsável.

## Causa e correção

A função administrativa cria contas Auth sem confirmação prévia de e-mail. O fluxo anterior tentava `signInWithOtp` para essas contas enquanto o cadastro público estava bloqueado. O Auth retornava `signup_disabled`, e a tela tratava esse erro como se o pedido de código tivesse sido aceito. Nenhum e-mail era gerado para a conta nova.

O primeiro acesso e a recuperação agora usam `resetPasswordForEmail`, o código é verificado com tipo `recovery` e a senha é definida somente depois da confirmação. O cadastro público continua desabilitado. O endpoint de recuperação mantém resposta genérica para endereços desconhecidos; falhas reais de serviço aparecem na interface, sem alegar envio bem-sucedido.

Foi incluído `supabase/templates/recovery.html`, com código de seis dígitos, instruções de definição de senha e expiração de dez minutos, correspondente a `otp_expiry = 600`. A conta não recebe convite automático no cadastro: o próprio cliente solicita o código em Primeiro acesso.

## Entrega de e-mail configurada

O ambiente local usava Mailpit/Inbucket, que captura e-mails para testes sem entrega externa. Foi configurado SMTP do Resend no Auth local com host `smtp.resend.com`, porta 587 e remetente de testes `onboarding@resend.dev`. O pedido real foi aceito pelo Auth e o responsável confirmou a entrega no Gmail.

A chave fica apenas em `supabase/.env.auth-smtp.local`, ignorado pelo Git. O `config.toml` guarda referências a variáveis de ambiente; não contém a chave. Os comandos locais usam `scripts/supabase-local.mjs` para carregar o arquivo privado. Nenhum projeto remoto foi alterado.

O remetente `resend.dev` permite entrega apenas ao e-mail da conta Resend. O responsável decidiu adiar a verificação do domínio e manter, por enquanto, o teste com a própria conta. Para enviar aos demais clientes depois, será necessário verificar um domínio da empresa e substituir o remetente por um endereço desse domínio. Ver [restrição do remetente de testes](https://resend.com/docs/knowledge-base/403-error-resend-dev-domain) e [configuração SMTP](https://resend.com/docs/send-with-smtp).

## Configuração local

```powershell
# Preparar arquivo privado, sem sobrescrever valores existentes:
node scripts/configure-auth-email.mjs --init
# Preencher a chave diretamente no arquivo privado, depois:
npm run auth:email:check
node scripts/configure-auth-email.mjs --smtp --restart
npm run functions:serve-local
```

O reinício preserva os dados. Com SMTP ativo, use os wrappers abaixo para a CLI carregar as variáveis privadas:

```powershell
npm run db:start
npm run db:stop
node scripts/supabase-local.mjs migration up --local
```

Para voltar deliberadamente à captura local de testes:

```powershell
node scripts/configure-auth-email.mjs --local --restart
```

Nesse modo, a tela de desenvolvimento explica que os códigos chegam em `http://127.0.0.1:54324`, e não à caixa pessoal. Esse aviso não aparece no build de produção. O modo SMTP remove o aviso.

Em um futuro projeto Supabase remoto, configurar o SMTP no ambiente remoto e copiar o modelo Recovery/Reset Password para os templates de Auth; a configuração local não é transferida automaticamente. Manter o cadastro público bloqueado, OTP de seis dígitos e validade de 600 segundos.

## Evidências de teste

- 23 testes JavaScript: recuperação usada no primeiro acesso, verificação do tipo de token, falhas de entrega visíveis, configuração SMTP sem gravar senha em config versionado, além dos fluxos existentes.
- `npm run build` concluído.
- `scripts/test-first-access-local.mjs` criou um cliente pela UI, vinculou uma unidade, leu o código realmente emitido na caixa local, rejeitou código inválido e reenvio imediato, exigiu definição de senha antes de mostrar unidades, verificou o e-mail, entrou com a nova senha e rejeitou reutilização do código. As contas, unidade e mensagens de teste foram removidas.
- Esse teste foi executado antes de habilitar SMTP real e recusa executar com SMTP ativo, para não enviar mensagens fictícias ao provedor.
- A conta pessoal foi usada somente para solicitar o e-mail real e conferir o estado de confirmação/login. A senha foi escolhida pelo usuário na interface.

Capturas locais em `outputs/qa/first-access-*.png`, ignoradas pelo Git. O teste pode ser repetido com Mailpit ativo e as variáveis de Playwright descritas no roteiro de implementação.
