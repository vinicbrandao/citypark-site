# Implementação dos requisitos de 27/10/2026

A entrega altera o banco e a aplicação para os requisitos revisados e os esclarecimentos desta conversa. Contrato/PDF ficou para uma etapa posterior: o configurador permite experimentar e revisar escolhas, mas não oferece envio nem conclusão da unidade.

## Comportamento entregue

- Cada abertura de unidade inicia nos padrões cadastrados para sua planta-base. Sair, trocar de unidade, atualizar a página ou encerrar o login descarta escolhas. Nenhum rascunho é salvo; o fluxo de proposta, quatro envios, parecer e autorização da arquiteta saiu da interface e seus RPCs de gravação foram revogados para usuários autenticados.
- Cliente usa uma conta de proprietário por unidade. Um cliente pode ter várias unidades. Vínculos antigos de coproprietário foram inativados, mantendo os registros e o histórico. A migration interrompe se encontrar proprietários ambíguos, para não escolher uma conta automaticamente.
- Arquiteta e Admin veem a tabela geral de unidades, inclusive inativas, seus clientes, planta-base, situação e prazos. Ambos alteram ativo/inativo; reativar uma unidade concluída exige Admin e a devolve a Pendente. Unidades inativas continuam na seleção do cliente com card cinza; clicar no card abre um aviso sobre inatividade ou personalização concluída. O configurador permanece bloqueado ao cliente e acessível à equipe. Contas sem qualquer vínculo mantêm Acesso em preparação.
- Prazo geral nulo e ausência de janela de módulo liberam edição sem limite. Datas vencidas bloqueiam alteração para todos os perfis. Apenas Admin define, remove ou reabre prazos. Cadastro do cliente vinculado e prazos da unidade/módulos são gravados juntos em uma transação.
- Exclusões e dependências entre opções funcionam na interface e na validação completa do servidor. Não foram inventadas regras técnicas oficiais. Os padrões de demonstração existentes foram explicitamente cadastrados; plantas reais precisam de padrões próprios.
- A equipe consulta histórico geral ou por unidade, com primeiro acesso, demais acessos, status, vínculos, prazos e cadastro de cliente, identificando ator e horário.
- Admin cadastra cliente por nome/e-mail. A função de servidor cria a conta Auth sem enviar convite; o cliente usa Primeiro acesso para confirmar e-mail e definir senha. Informar um e-mail existente atualiza o nome do mesmo cadastro. Chaves administrativas ficam no servidor.

## Banco local

Aplicadas e testadas as migrations `20261027000100`, `20261027000200` e `20261027000300`; o ajuste dos cards utiliza `20261027000400`. Os dados de rascunhos/propostas anteriores permanecem no banco como legado. A cópia anterior às mudanças está em `outputs/backups/citypark-before-requirements-20261027.dump`, ignorada pelo Git.

O Admin inicial `exclusive@planoaengenharia.com.br` foi provisionado **somente no ambiente local**, com autorização explícita do responsável. Nenhum e-mail foi enviado. A senha é definida por Primeiro acesso; o código fica no Inbucket local. Não houve alteração de ambiente remoto.

## Executar e verificar

```powershell
npm run db:start
node scripts/supabase-local.mjs migration up --local
npm run db:seed-local
node scripts/seed-staff-local.mjs
npm run db:demo-local
npm run functions:serve-local
# Em outro terminal:
npm run dev
```

`functions:serve-local` usa a mesma rede Docker `citypark-exclusive-local` do restante do Supabase. O serviço precisa estar ativo para o botão Cadastrar cliente. Os seeds são locais e fictícios; o seed de demonstração deixa prazos sem data e configura os padrões da planta-base.

Verificações atuais:

```powershell
npm test
npm run build
npm run test:db-local
npm run test:requirements-ui-local
npm run test:customizer-layout-local
node scripts/test-reminder-worker-local.mjs
```

Os testes de navegador precisam de Playwright e Edge. Se necessário, configure `CITYPARK_PLAYWRIGHT_PATH`, `CITYPARK_BROWSER_CHANNEL` e `CITYPARK_UI_URL`. Os testes usam contas/unidades temporárias e as removem. O teste do worker exige as funções locais ativas e recusa sobrescrever um `supabase/functions/.env` existente; usa transporte HTTP simulado e não envia e-mail real.

Os scripts históricos de teste de propostas, autorização, rascunhos e coproprietário representam o fluxo anterior e não são mais a validação vigente. Os comandos antigos de proposta e seleção foram substituídos pelo teste de requisitos.

## Integração configurável de e-mail

A fila e a função `deadline-reminders` estão prontas. O provedor ainda não foi definido; **não há disparo externo nem agendamento ativo**.

1. Configure no ambiente das Edge Functions `DEADLINE_REMINDER_TOKEN`, `DEADLINE_EMAIL_WEBHOOK_URL` e `DEADLINE_EMAIL_WEBHOOK_TOKEN`, conforme `supabase/functions/.env.example`. O endpoint do transporte deve usar HTTPS em produção e encaminhar o e-mail pelo provedor/SMTP escolhido.
2. O transporte recebe POST autenticado, com `Idempotency-Key` e JSON `{id,to,subject,text,unitCode,module,deadline,daysBefore}`. Deve tratar a mesma chave como a mesma mensagem e responder 2xx apenas quando aceitar o envio.
3. Agende uma chamada POST à função `deadline-reminders` com `Authorization: Bearer <DEADLINE_REMINDER_TOKEN>`. Uma execução por hora permite recuperar falhas durante o mesmo dia sem repetir entregas confirmadas. O endpoint valida esse segredo próprio, por isso sua verificação JWT do gateway fica desativada.
4. Os marcos são calculados por data civil em `America/Sao_Paulo`, aos 15, 10, 5 e 1 dias. Datas nulas não geram avisos. Unidade inativa/concluída não recebe novos avisos. Alterar a data cria uma referência nova; filas de prazo removido ou alterado não são reclamadas para envio.
5. Há registro de tentativas/resultado, reserva temporária para impedir trabalho concorrente e limite de cinco tentativas por aviso no mesmo dia. Um erro do transporte não marca entrega como enviada.

Para provisionar o Admin inicial em outro ambiente, executar explicitamente `node scripts/provision-initial-admin.mjs` com `SUPABASE_URL` e `SUPABASE_SERVICE_ROLE_KEY` no ambiente de servidor, após autorização para aquele destino. O script não envia convite e não imprime a chave. `--local` força o ambiente local.

## Limites e próxima etapa

Contrato/PDF, conclusão após geração, arquivo privado e download continuam pendentes por decisão do responsável. A coluna de situação já está preparada, mas esta entrega não cria contratos nem marca uma unidade como Concluída. Catálogo, preços e quantitativos do protótipo seguem demonstrativos. Não existem dados oficiais de dependências/padrões cadastrados automaticamente.


## Atualização do primeiro acesso

Em 27/10/2026 o fluxo foi corrigido para recuperação com código (`resetPasswordForEmail`/`recovery`), compatível com contas recém-provisionadas e cadastro público bloqueado. SMTP real de autenticação conectado ao Resend, com entrega e definição de senha confirmadas pelo responsável. Ver [validação e configuração do primeiro acesso](validacao-primeiro-acesso-2026-10-27.md). Isso não ativa automaticamente o transporte HTTP dos lembretes de prazo, que permanece um fluxo independente.
