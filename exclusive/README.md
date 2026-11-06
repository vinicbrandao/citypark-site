# City Park Exclusive

## Comece por aqui

Estado atual e próximo passo: [checkpoint do projeto](docs/EXCLUSIVE_STATUS.md). Leia primeiro; os roteiros datados abaixo podem conter etapas já concluídas.

Plano vigente: [Roteiro para Vinícius e Allef](docs/inicio-vinicius.md). Instalação, login, cadastros, calendários preliminares e homologação. Substitui a ordem de prioridades da passagem inicial.

## Requisitos atualizados em 27/10/2026

Implementação vigente: [mudanças de sessão, acesso e gestão](docs/implementacao-requisitos-2026-10-27.md). O contrato/PDF será feito depois.

Permissões de produção de 30/10: [atualização preparada e testada](docs/implantacao-permissoes-2026-10-30.md), ainda não aplicada ao Supabase oficial. Validação do novo modelo: `node scripts/test-official-bootstrap-local.mjs` e `node scripts/test-permissions-upgrade-local.mjs`, ambos em bancos temporários locais. Os roteiros antigos que excluem fixtures recusam o novo esquema para preservar histórico.

- A personalização fica apenas na sessão atual. Toda abertura inicia nos padrões da planta-base; sair descarta as escolhas. Não há Salvar progresso nem proposta/parecer técnico.
- Cada unidade tem uma única conta de cliente. Arquiteta e Admin consultam todas as unidades em uma tabela, inclusive inativas; cliente vê os cards vinculados à sua conta, com cinza e aviso nas inativas, e entra no configurador apenas das ativas.
- Sem prazo cadastrado, unidade e módulo ficam liberados. Só Admin define/remove/reabre prazos e vincula clientes. A equipe pode ativar/inativar unidades; reabrir uma concluída exige Admin.
- Login por e-mail e senha; Primeiro acesso solicita um código de recuperação para confirmar o e-mail e definir a senha. Cadastro público desabilitado. O cadastro de clientes ocorre pela função administrativa do servidor.
- Rascunhos, propostas e pareceres antigos continuam preservados no banco como histórico legado.

## Executar localmente

Requisitos: Node.js 22.12+ e Docker Desktop com contêineres Linux em execução.

```powershell
npm ci
docker network create -o com.docker.network.bridge.host_binding_ipv4=127.0.0.1 citypark-exclusive-local
npm run db:start
node scripts/seed-local.mjs
node scripts/seed-staff-local.mjs
npm run dev
```

Crie a rede apenas uma vez. O vínculo com 127.0.0.1 mantém os serviços locais fora da rede externa.

- Aplicação: http://127.0.0.1:5173/exclusive/
- Caixa de e-mails de teste: http://127.0.0.1:54324
- Supabase Studio: http://127.0.0.1:54323
- Contas fictícias: `cliente.a@example.test` (1209A) e `cliente.b@example.test` (1210A).

O script de carga aceita apenas o Supabase local, cria as contas sem senha e grava somente URL e chave pública em `.env.local`. Os códigos ficam na caixa local; não são enviados a pessoas reais. Não executar o ambiente da CLI como servidor público de produção.

As tabelas são criadas pelas migrations em `supabase/migrations`. O seed SQL automático é vazio; os dados fictícios entram somente pelo script explícito.

## Trabalho em equipe

Cada pessoa mantém seu próprio Docker e banco local com dados fictícios. Compartilhamos código e migrations pelo Git; bancos e senhas não são sincronizados. Após receber novas migrations, execute `node scripts/supabase-local.mjs migration up --local`.

- Guia de passagem e plano de cinco dias: [docs/passagem-equipe-2026-09-18.md](docs/passagem-equipe-2026-09-18.md).
- Laboratório genérico: `/exclusive/laboratorio-imagens.html`; projetos são compartilhados por exportação e importação JSON.
- Contas de equipe fictícias: `admin.1@example.test` a `admin.3@example.test`, `architect.1@example.test` e `architect.2@example.test`.
- Arquiteta e Admin acessam todas as unidades por requisito vigente, inclusive inativas. Apenas Admin gerencia contas, vínculos e prazos.
- Não incluir no Git `.env.local`, credenciais, compradores, backups ou arquivos brutos de Revit/renders. Os arquivos em `assets/` são os recursos necessários para executar o protótipo.
- Usar branches por tarefa e revisão antes de integrar alterações na `main`. Não alterar migrations já compartilhadas.

## E-mail e primeiro acesso

Implantação com contas da empresa: [configuração oficial do CityPark](docs/configuracao-oficial-autenticacao.md). A configuração pessoal validada localmente é apenas um teste; a implantação oficial está em andamento na conta exclusive@planoaengenharia.com.br.

Projeto oficial com 19 tabelas protegidas e 26 versões registradas. SMTP oficial, primeiro Admin, cadastro de cliente pela função publicada e primeiro acesso por e-mail validados em 29/10/2026. Dados autorizados de validação: um cliente e a unidade 1505 A. [Registro da implantação](docs/implantacao-banco-oficial-2026-10-28.md).

Inventário real cadastrado em 30/10: **389 unidades (209 A + 180 B)**, com identificação por torre/andar/terminação. As 388 novas estão inativas e sem dados técnicos; 1505 A e seu proprietário foram preservados. [Inventário e próximo preenchimento](docs/inventario-unidades-2026-10-30.md).

Validação conectada ao Supabase oficial: `.env.official.local` contém somente URL e chave pública, fora do Git. Execute `npm run dev:official` e acesse `http://127.0.0.1:5175/exclusive/`. Esse modo acessa o banco oficial; alterações administrativas nessa tela afetam os dados oficiais. Não executar scripts de demonstração nele. A inicialização recusa uma URL diferente do projeto oficial ou chave pública ausente.

Para testar com o banco Docker separado, use `npm run dev:local` e `http://127.0.0.1:5173/exclusive/`. `npm run dev` também continua usando a configuração local padrão. Os bancos não sincronizam automaticamente: código/migrations são versionados; dados e contas permanecem em cada ambiente. O frontend ainda não foi publicado no domínio público.

Para gerar os arquivos conectados ao banco oficial, use `npm run build:official`. Gerar o build não publica o site.

Fluxo validado e configuração SMTP: [validação do primeiro acesso](docs/validacao-primeiro-acesso-2026-10-27.md). O SMTP local está conectado ao Resend. O remetente de testes só entrega ao e-mail da conta Resend; verificar domínio antes de liberar entrega aos demais clientes. Credenciais ficam em `supabase/.env.auth-smtp.local`, fora do Git.

## Futuro ambiente de produção

Aplicar as migrations em um projeto dedicado do Exclusive. Configurar o domínio `/exclusive/`, o modelo de e-mail com código, o SMTP e desabilitar cadastro público também no ambiente remoto. Configurações locais não se transferem automaticamente para um projeto na nuvem.

Provisionamento inicial pela equipe: criar o usuário pelo serviço administrativo de Auth; cadastrar cliente e unidade; relacioná-los em `customer_users` e `customer_units`. Nunca colocar chave administrativa no frontend. A interface administrativa de cadastro utiliza a função `admin-customer`; mantenha as Edge Functions ativas.

O build (`npm run build`) gera `dist/`, incluindo imagens, para publicação em `/exclusive/`. A hospedagem deve encaminhar as rotas dessa aplicação ao seu `index.html`.

### Verificação

Execute `npm test`, `npm run build` e `npm run test:db-local`. Os testes atuais cobrem descarte da sessão, padrões, dependências entre módulos, isolamento por conta, equipe em unidade inativa, prazos e cadastro administrativo. Com Vite e Edge Functions locais ativos, `npm run test:requirements-ui-local` valida a jornada dos três perfis com dados temporários; `npm run test:customizer-layout-local` verifica o layout em sete dimensões. Veja configuração de Playwright e lembretes em [implementação dos requisitos](docs/implementacao-requisitos-2026-10-27.md).

## Principal mudança desta versão

A precificação de **Bancadas** deixou de usar valores fixos independentes e passou a usar:

- quantidade de bancada em **m²**;
- comprimento do rodamão em **m**;
- altura do rodamão em **m**;
- quantidade da bancada de serviço em **m²**;
- preço unitário do granito em **R$/m²**.

Os quantitativos desta versão são **fictícios**, apenas para validar a lógica. Devem ser substituídos pelos quantitativos do Revit.

### Fórmula usada

```text
Área de bancada = área bancada principal + área bancada de serviço
Área de rodamão = (comprimento principal + comprimento de serviço) × altura escolhida
Área total de granito = área de bancada + área de rodamão

Custo da configuração escolhida = área total de granito × preço/m² do granito escolhido
Custo padrão = área padrão × preço/m² do São Marco

Valor adicional bancadas = custo escolhido - custo padrão
```

Assim, aumentar a bancada ou o rodamão aumenta automaticamente a quantidade de granito. Ao trocar São Marco por Bellagio, o preço unitário escolhido passa a valer sobre toda a área resultante.

## Dados fictícios atuais

- São Marco: R$ 900/m²
- Bellagio: R$ 1.450/m²
- bancada padrão: 1,20 m²; comprimento de rodamão 2,40 m
- bancada estendida: 1,90 m²; comprimento de rodamão 3,80 m
- rodamão padrão: 10 cm
- rodamão ampliado: 60 cm
- bancada adicional de serviço: 0,55 m²; comprimento de rodamão 1,10 m

## Novo asset

Foi incluída a imagem:

`assets/cozinha/bancada-padrao-sao-marco-rodamao-60.png`

para representar corretamente a combinação bancada padrão + São Marco + rodamão de 60 cm.

## Observação visual

A prévia passou a usar `object-fit: contain` para privilegiar a visualização completa do ambiente, inclusive piso e forro.

