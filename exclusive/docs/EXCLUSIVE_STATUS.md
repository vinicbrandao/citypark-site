# CityPark Exclusive — checkpoint atual

Atualizado em **30/10/2026**. Responsável: Vinícius; supervisor: Allef.
Leia este arquivo primeiro. Ele resume o último estado verificado; não presume serviços locais em execução. Detalhes e histórico só precisam ser consultados quando a tarefa exigir.

## Ponto de retomada

**Atualização de permissões preparada e testada, ainda não aplicada ao oficial.** [Pacote, validações e ordem de implantação](implantacao-permissoes-2026-10-30.md). Próximo passo: autorização para aplicar a versão 27 e publicar/atualizar as funções, com cópia de segurança prévia. O oficial continua com 26 versões. Não repetir instalação inicial nem criar contas/unidades fictícias nele. Contrato/PDF continua adiado.

## Ordem de preparação para produção

1. Auditar permissões e integridade: RLS, funções, perfis, vínculos e prevenção de inconsistências, conforme as respostas sobre permissões.
2. Configurar backups, retenção e responsável; testar restauração em ambiente separado.
3. Conferir desempenho e índices pelas consultas reais, sem estruturas desnecessárias.
4. Monitorar falhas de funções, e-mails e banco; observar uma execução automática do cron e sua resposta HTTP (até aqui, job ativo e chamadas manuais verificados).
5. Preparar entrada em produção: separar testes/dados reais, carregar catálogo oficial e revisar endereços de autenticação ao publicar o frontend.

## Arquitetura e ambientes

- Frontend: JavaScript, HTML/CSS e Vite, destinado a `/exclusive/`. Interface com seleção de unidades, configurador e gestão da equipe; protótipos visuais não representam catálogo oficial.
- Backend: Supabase Auth, PostgreSQL com RLS/RPCs e Edge Functions. Nenhuma chave administrativa no navegador.
- Projeto oficial: `citypark-exclusive`, ref `grfmiuopojbxxbdymqax`, organização **CityPark Exclusive**, região São Paulo. Conta responsável: `exclusive@planoaengenharia.com.br`.
- Interface no computador conectada ao banco oficial: `npm run dev:official`, endereço `http://127.0.0.1:5175/exclusive/`. `.env.official.local` contém apenas URL/chave pública, fora do Git; inicialização recusa URL diferente do projeto oficial/chave ausente. Operações nessa tela afetam o banco oficial.
- Interface com banco Docker separado: `npm run dev:local`, endereço `http://127.0.0.1:5173/exclusive/`; `npm run dev` mantém esse padrão. Não há sincronização automática. Em 30/10 foi identificado o servidor 5173 usando Docker e iniciado o 5175 apontando ao oficial; navegador mostrou a unidade 1505 A. Proteção contra URL local no modo oficial validada; `npm run build:official` passou. Evidência: `outputs/qa/official-environment-20261030.png`. Não copiar dados nem resetar bancos para trocar de ambiente.
- Desenvolvimento padrão usa Supabase local/Docker e dados fictícios separados. Não executar seeds, reset ou instalação inicial no projeto oficial.
- Site atual: `cityparkmcz.com.br`, GitHub Pages, DNS Registro.br; mantém Firebase. Exclusive usa contas novas, sem migração de usuários Firebase. A interface Exclusive **ainda não foi publicada** no domínio público.

## Banco oficial — implantado

**19 tabelas públicas, todas com RLS; 26 versões registradas.** Instalação otimizada concluída em 29/10. As 22 estruturas obsoletas foram removidas apenas da instalação oficial inicialmente vazia; o banco local preserva legado. Não repetir o pacote inicial.

| Área | Tabelas |
| --- | --- |
| Contas e vínculos | `customers`, `customer_users`, `staff_users`, `units`, `customer_units` |
| Plantas e catálogo | `base_plans`, `unit_base_plan_assignments`, `customization_modules`, `unit_module_windows`, `customization_groups`, `customization_options` |
| Compatibilidade e padrões | `base_plan_option_availability`, `base_plan_option_exclusions`, `base_plan_option_defaults`, `base_plan_option_requirements` |
| Importação, auditoria e avisos | `import_batches`, `import_rows`, `unit_activity_events`, `deadline_notifications` |

Últimos dados conferidos: duas contas Auth, um Admin oficial, um cliente Vinícius (`vinicius.brandaolis@gmail.com`), **389 unidades (209 A + 180 B)** e um vínculo ativo de proprietário. A **1505 A** foi preservada, ativa/Pendente e sem prazo; as outras 388 foram cadastradas inativas/Pendentes. Todas sem área/planta-base e com tipologia “A confirmar”. Um aviso de teste permanece no histórico. [Carga e preenchimento pendente](inventario-unidades-2026-10-30.md). Sem catálogo fictício importado.

## Implementado e validado

- Admin cadastra cliente por nome/e-mail e gerencia vínculos. `admin-customer` publicada valida sessão com `auth.getUser` e perfil Admin antes de criar conta sem convite ou senha escolhida pelo operador. Pedidos não autorizados retornam 403.
- Primeiro acesso utiliza recuperação (`resetPasswordForEmail` + `verifyOtp` tipo `recovery`): código de seis dígitos, válido por dez minutos, mensagem em português e definição da senha pelo usuário. Cadastro público bloqueado. Admin e cliente confirmaram recebimento e acesso reais.
- Cliente vê apenas seus cards; unidade inativa permanece cinza e abre aviso, sem acesso ao configurador. Conta sem vínculo mantém “Acesso em preparação”. Equipe consulta todas as unidades, inclusive inativas.
- Escolhas começam nos padrões da planta-base e existem apenas na sessão: sair/trocar unidade/recarregar descarta. Sem salvamento de rascunho, proposta ou parecer técnico. Dependências/exclusões são validadas na interface e no servidor.
- Histórico registra ator, unidade e horário de acessos e mudanças administrativas. Gestão de status e prazos aplica as permissões abaixo.

## Regras vigentes e decisões

- Especificação: [permissões de 30/10](permissoes-producao-2026-10-30.md). Telefone, conta ativa/inativa, contatos só pelo Admin, gestão de equipe, proteção do principal, histórico imutável e nova tentativa administrativa estão preparados na migration `20261030000100`/código, sem publicação oficial. Clientes verão histórico de contratos com data/hora/PDF na etapa adiada.
- Inventário fixo de 389 unidades carregado, com identificação completa; dados técnicos ainda pendentes. Identificação e planta-base ficam fora das permissões do Admin; Admin altera valores/quantitativos e controles operacionais (status, prazo, proprietário). Troca de proprietário retira o acesso anterior. Resumo em PDF permitido, sem rascunho; implementação adiada com os documentos.
- Uma conta proprietária por unidade; o mesmo cliente pode ter várias unidades. Coproprietário removido do fluxo; cônjuge usa a mesma conta/e-mail. Vínculos legados foram inativados e preservados localmente.
- Arquiteta e Admin podem acessar unidades inativas e alterar ativo/inativo. Somente Admin gerencia contas/vínculos/prazos e reativa unidade concluída; essa reativação volta a Pendente.
- Prazo geral ou de módulo ausente libera edição sem limite. Prazo vencido bloqueia mudanças para todos os perfis; **somente Admin pode reabrir**.
- **Decidido, ainda não implementado:** geração e registro do PDF concluem e inativam a unidade. Envio é manual fora do sistema; cliente/equipe podem baixar e enviar. Não haverá aceite/assinatura digital nesta etapa. Contratos anteriores permanecem no histórico e acessíveis ao cliente mesmo com a unidade inativa. Novo contrato exige reativação e prazos abertos.

## E-mails e avisos de prazo — ativos

- Resend oficial, equipe `planoaengenharia`; domínio `acesso.cityparkmcz.com.br` verificado. Remetente: `City Park Exclusive <nao-responda@acesso.cityparkmcz.com.br>`. Três registros DNS adicionados, preservando os anteriores.
- Login usa SMTP oficial `smtp.resend.com:587`. Avisos usam a API Resend pela função `deadline-reminders`, com a fila existente; não dependem do navegador nem alteram o SMTP de autenticação.
- Job único `citypark-deadline-reminders`, ativo desde 30/10, expressão `*/10 * * * *`: verifica a cada dez minutos, todo o dia. Extensões `pg_cron` e `pg_net` instaladas.
- Avisos aos 15, 10, 5 e 1 dias, por data de São Paulo. Sem prazo ou unidade inativa/concluída não há novo aviso elegível. Reserva, tentativas limitadas e idempotência evitam duplicação.
- `deadline-reminders` exige token exclusivo de pelo menos 32 caracteres antes de acessar a fila. Segredo atual de 64 caracteres em Edge Secrets `DEADLINE_REMINDER_TOKEN` e Vault `citypark_deadline_reminder_token_v2`. Segredo antigo sem sufixo permanece sem uso. Não imprimir valores.
- Ambas as funções publicadas usam `verify_jwt=false` no gateway, com autenticação própria obrigatória no handler: sessão/perfil em `admin-customer`, token exclusivo nos avisos. Não remover essas validações.
- Teste autorizado em 29/10: um aviso entregue ao Gmail; repetição não duplicou. Prazo temporário da 1505 A removido, registro mantido. Em 30/10: job ativo e nova chamada HTTP 200, `sent=0/failed=0`, unidade sem prazo. Execução natural do cron ainda não observada.

## Validação e limites atuais

- Última suíte: **56 testes passaram** em 30/10; build oficial passou. Atualização de permissões validada em bancos temporários: instalação de 27 versões/19 tabelas, proteção dos perfis, upgrade 26 → 27 com dados preservados, repetição recusada e Auth real isolado (login e troca administrativa de e-mail). Nada aplicado ao banco local existente ou ao oficial.
- Novas telas revisadas em prévia fictícia no navegador. Jornada completa pelas Edge Functions reais novas ainda depende da implantação autorizada. Roteiros legados que excluem fixtures recusam o esquema novo; não afrouxar imutabilidade para executá-los.
- Evidências locais, fora do Git: `outputs/qa/deadline-schedule-active-20261030.png`, `deadline-delivered-gmail-20261029.png` e `deadline-test-restored-20261029.png` no mesmo diretório.
- Pendentes: catálogo, plantas, imagens, preços, quantitativos e regras técnicas oficiais; completar dados técnicos das 389 unidades, demais clientes/vínculos e arquitetas oficiais; contrato/PDF e armazenamento/download; publicação revisada do frontend. A unidade de teste não possui planta para personalização real.

## Cuidados para continuar

- Pedir autorização para mudanças importantes nas contas oficiais. Autorizações já executadas: estrutura otimizada, DNS, SMTP/Auth/Admin, publicação das duas funções, cliente/unidade de teste e avisos/agendamento/teste. Não confundir autorização desses itens com permissão para novas importações, exclusões ou privilégios.
- Senhas, códigos e chaves são inseridos pelo responsável; nunca documentar valores no Git, conversa ou frontend. Arquivos privados `.env*.local`, backups e evidências permanecem ignorados.
- Atualizar este checkpoint substituindo o estado anterior; evitar acrescentar diários. Registrar apenas o que mudou, evidências relevantes, limites e próximo passo. Consultar detalhes sob demanda; decisões atuais prevalecem sobre propostas antigas.

## Referências sob demanda

- [Avisos: configuração, regras e manutenção](avisos-de-prazo.md).
- [Autenticação e contas oficiais](configuracao-oficial-autenticacao.md).
- [Implantação do banco oficial](implantacao-banco-oficial-2026-10-28.md).
- [Requisitos e esclarecimentos de 27/10](levantamento-requisitos-2026-10-27.md) e [implementação daquela etapa](implementacao-requisitos-2026-10-27.md). Esses registros datados podem descrever pendências já concluídas aqui.
- [Histórico integral até 30/10 — consultar apenas se necessário](historico/EXCLUSIVE_STATUS_ate_2026-10-30.md). Contém decisões substituídas; links relativos antigos partem originalmente de `docs/`.
