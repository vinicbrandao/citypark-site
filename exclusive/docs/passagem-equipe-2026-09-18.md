> Registro histórico. GitHub já criado e acesso do Vinícius concedido. A ordem de trabalho atual está em [Roteiro vigente](inicio-vinicius.md): login, cadastros e calendários primeiro; autorizações das arquitetas depois.

# City Park Exclusive

## Estado do projeto e plano de trabalho em equipe

Documento de passagem para Allef, o estagiário e a equipe de TI. Consolida o trabalho até 18 de setembro de 2026 e propõe cinco dias de execução paralela. O projeto ainda é um ambiente local de desenvolvimento; não está pronto para uso contratual pelos compradores.

### Decisão recomendada

Usar um repositório Git privado para código, testes e migrations do banco. Cada desenvolvedor executa seu próprio Supabase local com Docker e dados fictícios. Allef concentra os próximos cinco dias na modelagem no Revit e no laboratório de imagens; o estagiário implementa autorizações por unidade, sob revisão técnica. O servidor da empresa é avaliado em paralelo pela TI.

### O que já existe

| Área | Situação verificada no projeto |
| --- | --- |
| Aplicação | Interface Vite e JavaScript; escolhas de planta e materiais por unidade; preços e quantitativos fictícios. |
| Login | E-mail e senha; primeiro acesso e recuperação por código abrem a definição de senha. E-mails capturados no Mailpit local. |
| Banco | Supabase local com PostgreSQL, Auth, políticas de acesso e migrations. Rascunhos com revisão para evitar sobrescrita concorrente. |
| Equipe | Perfis admin e architect; histórico de salvamentos com autor. Contas reais locais cadastradas, sem envio de convites. |
| Imagens | Laboratório genérico com projetos independentes, importação, camadas, exportação JSON e salvamento no navegador. |

### O que ainda não está concluído

Autorização de arquitetas por unidade, validação técnica, confirmação final, prazos, painel completo de cadastro, catálogo e preços oficiais no banco, envio real de e-mails, importação definitiva dos compradores e operação no servidor.

Última rodada registrada: 13 testes automatizados e compilação aprovados. Testes locais anteriores verificaram isolamento entre clientes, perfis, auditoria e revogação. O novo fluxo com senha ainda precisa de um teste completo de usuário; compilação e testes de interface não substituem esse aceite.

## Como dividir código banco e arquivos

### Git guarda a evolução do projeto

Git registra versões. GitHub, GitLab ou o serviço corporativo hospedam o repositório e permitem revisão das mudanças. A pasta C:\dev\citypark-exclusive ainda não é um repositório Git. Criar um repositório privado da empresa e convidar o estagiário com sua conta individual é o próximo passo organizacional; nenhum repositório remoto foi criado nesta entrega.

| Versionar | Manter fora do Git |
| --- | --- |
| Código, package.json e package-lock.json | Senhas, SMTP, service role e arquivos .env com valores reais |
| supabase/migrations, config.toml sem segredos, templates | Volumes Docker, dumps com dados pessoais e logs sensíveis |
| Testes, scripts com dados fictícios e documentação | Relatório de compradores e evidências de autorização |
| Imagens web selecionadas ou referências ao acervo | Arquivos Revit, RAR/ZIP e grandes JSONs do laboratório |

O .gitignore atual cobre dependências, build, .env e temporários do Supabase, mas ainda precisa de uma revisão para acervo recebido, arquivos grandes e documentos com dados reais. Revisar os arquivos antes do primeiro commit; evitar adicionar toda a pasta sem conferência.

### Fluxo diário proposto

- Manter main estável. Criar uma branch por tarefa, por exemplo feat/autorizacao-unidade. Abrir uma solicitação de revisão antes de integrar à main.

- Alterações do banco entram em novas migrations SQL. Não reescrever migrations já compartilhadas. Combinar nomes e horários para evitar conflitos entre arquivos.

- Mudanças feitas pelo Studio durante experimentos precisam virar migration revisável. Copiar o volume Docker não é o mecanismo de colaboração.

- Rodar testes e build antes da revisão. Um responsável aplica alterações aprovadas no ambiente compartilhado; o estagiário trabalha primeiro no ambiente local.

### Imagens e modelos

Allef mantém Revit e renders em uma pasta corporativa com versões e backup. Exporta do laboratório um JSON por projeto com as combinações aprovadas. O estagiário recebe um manifesto com nomes, unidade, tipologia, camadas e ordem. O laboratório salva no navegador de cada pessoa; Git não sincroniza esse armazenamento. A troca é feita por exportar e abrir projeto.

Os arquivos recebidos em 18/09 foram extraídos em recebidos/2026-09-18: 28 imagens de sala e 14 de cozinha. Há projetos de revisão JSON; as novas imagens ainda não substituíram o catálogo do cliente. A suíte master continua sem perspectiva recebida.

## Instalação no computador do estagiário

O Docker instalado no computador de Allef não impede o trabalho em equipe. O estagiário instala seu próprio Docker Desktop com contêineres Linux e recria os serviços a partir do mesmo código. Cada banco é independente: dados salvos em um computador não aparecem automaticamente no outro. [1]

### Preparação e primeira execução

Instalar Git, Node.js compatível com o projeto (22.12 ou superior compatível com Vite 8) e Docker. A TI deve conferir os requisitos e a política de instalação da empresa. Clonar o repositório privado e abrir um terminal na raiz do projeto.

npm ci

docker network create -o com.docker.network.bridge.host_binding_ipv4=127.0.0.1 citypark-exclusive-local

npm run db:start

node scripts/seed-local.mjs

node scripts/seed-staff-local.mjs

npm run dev

Criar a rede apenas uma vez. O seed gera .env.local com endereço e chave pública locais; não copiar o .env de outra pessoa. As contas reais cadastradas na máquina de Allef não fazem parte desse seed. Os scripts fornecem somente clientes e equipe fictícios.

### Endereços locais

Aplicação: http://127.0.0.1:5173/exclusive/
Laboratório: http://127.0.0.1:5173/exclusive/laboratorio-imagens.html
Mailpit: http://127.0.0.1:54324/
Supabase Studio: http://127.0.0.1:54323/

### Atualizações e verificação

Após receber mudanças da equipe, instalar dependências quando o lockfile mudar e executar npx supabase migration up --local para aplicar novas migrations. Rodar npm test, npm run build e, com os seeds carregados, node scripts/test-access-local.mjs e node scripts/test-staff-local.mjs. Os testes de integração modificam apenas os rascunhos fictícios.

A suíte de testes de equipe atual assume acesso amplo para perfis ativos. Ela deve ser atualizada junto com a nova autorização por unidade, para exigir consentimento da unidade atendida.

Não executar reset em banco com trabalho que precise ser preservado. Uma recriação destrutiva só serve ao ambiente descartável do próprio desenvolvedor. Não publicar a pilha da CLI nem o Studio local na internet. [1]

## Plano dos próximos cinco dias

Usar Dia 1 a Dia 5 como dias de trabalho, sem pressupor expediente no fim de semana. As tarefas abaixo são metas propostas; integrar apenas o que cumprir os critérios de aceite.

| Dia | Allef | Estagiário |
| --- | --- | --- |
| 1 | Organizar opções Revit por unidade e tipologia. Definir nomes das camadas. | Clonar e reproduzir ambiente. Executar testes. Mapear tabelas, RPCs e políticas atuais. |
| 2 | Modelar opções prioritárias e extrair quantitativos. | Propor modelo de autorização e cenários de teste; abrir revisão da migration antes de ampliar acessos. |
| 3 | Gerar renders com câmera e quadro consistentes. | Implementar concessão e revogação no banco, incluindo bloqueio por unidade. Testar acessos indevidos. |
| 4 | Montar e anotar combinações no laboratório. | Adicionar tela mínima de autorização e validação técnica por revisão, se a base de permissões passar nos testes. |
| 5 | Exportar projetos revisados e registrar imagens faltantes. | Demonstrar fluxo completo, entregar PR, instruções e limitações. Testar instalação em ambiente limpo. |

### Responsabilidades de revisão

Allef valida as regras de negócio, nomes das opções, combinações e quantitativos. Um desenvolvedor responsável revisa migrations, funções com privilégios elevados e testes de segurança. A TI avalia hospedagem, backups, acesso ao servidor e configuração de e-mail. Se não houver revisor técnico disponível, o estagiário entrega uma proposta testada localmente, sem ativação para clientes.

### Entrega esperada do estagiário

- Uma solicitação de revisão com código, novas migrations, dados fictícios, testes positivos e negativos e instruções de instalação.

- Demonstração: cliente autoriza arquiteta, arquiteta salva escolhas, valida tecnicamente a revisão, cliente revoga e a arquiteta perde o acesso de atendimento.

- Nenhum preço oficial, confirmação contratual ou importação real ativada como efeito colateral dessa tarefa.

### Trabalho posterior

Depois das permissões: painel de clientes e unidades, conferência da planilha, catálogo com preços e quantidades oficiais no banco, confirmação final e prazos, e homologação online. O envio SMTP pode ser configurado quando a conta exclusive@planoaengenharia.com.br e a autorização da TI estiverem disponíveis.

## Especificação para autorizações e validação

### Situação atual que deve ser corrigida

As políticas staff_units, staff_drafts e a função save_unit_draft ainda dão acesso amplo a qualquer architect ativo. Kamilla e Alina estão cadastradas localmente com o perfil inativo por esse motivo. Os três administradores locais são Allef, Camilla e Vinicius. Não ativar as arquitetas reais antes da restrição por unidade.

### Modelo proposto para revisão

Criar autorizações vinculando unidade, arquiteta, concedente, origem da autorização, data e revogação. Concessões feitas pelo cliente exigem vínculo ativo com a unidade. Concessões registradas por administrador exigem referência à evidência obtida fora do sistema. Evidências devem ficar em armazenamento privado, com política própria; não em URL pública ou dentro do Git.

Aplicar a autorização no banco tanto na leitura quanto no salvamento. Interface escondida não é controle de acesso. Revogação deve impedir novas operações imediatamente, inclusive em sessões já abertas. A arquiteta não pode conceder acesso a si mesma nem alterar seu próprio perfil.

### Validação técnica e confirmação

Registrar a validação técnica com unidade, revisão exata do rascunho, profissional, data e observação. Se as escolhas mudarem, a validação anterior permanece no histórico, mas não valida a nova revisão. A confirmação final é uma ação distinta do cliente; atendimento assistido não autoriza assumir custos por ele.

Decisão ainda necessária: quem pode validar tecnicamente cada unidade. Recomendação inicial é a arquiteta explicitamente autorizada; uma fila de revisão para outras profissionais exigirá atribuição formal e permissão separada.

### Critérios de aceite mínimos

- Cliente A não concede autorização para a unidade de B. Cliente não acessa histórico interno de outras unidades.

- Arquiteta sem autorização não lê nem altera o atendimento. Após concessão consegue operar apenas naquela unidade; após revogação volta a ser bloqueada.

- Arquiteta não modifica preços, vínculos de clientes, perfil administrativo nem confirmação final. Testar pela API além da interface.

- Duas sessões com revisão antiga não sobrescrevem escolhas silenciosamente. Validar revisão desatualizada deve falhar.

- Histórico registra autor e ação. Revogar acesso não apaga o histórico; alteração de rascunho exige nova validação técnica.

Arquivos iniciais para estudo: src/main.js, app.js, supabase/migrations, scripts/test-access-local.mjs e scripts/test-staff-local.mjs. O formulário de senha está em src/main.js. Não reescrever o login sem uma necessidade identificada; priorizar o teste completo desse fluxo e o controle de autorização.

## Servidor da empresa e próximos marcos

### Escolha de hospedagem

Recomendação condicionada à avaliação da TI: se o objetivo é operar internamente, usar uma implantação própria do Supabase no servidor, com o conjunto de serviços necessário ao aplicativo. A CLI de desenvolvimento não é a implantação de produção. O guia oficial usa Docker Compose e atribui à equipe a configuração e operação do ambiente. [2]

Alternativa: manter o backend em Supabase gerenciado e hospedar apenas o frontend no servidor da empresa. Isso reduz a operação local, mas deixa o banco fora do servidor corporativo. Usar apenas PostgreSQL no servidor exige redesenhar ou hospedar separadamente Auth e a API, pois o aplicativo depende de auth.users, auth.uid(), RPCs, RLS e do cliente Supabase.

### Informações que a TI precisa fornecer

Sistema operacional, possibilidade de VM Linux, recursos disponíveis, armazenamento e backup, domínio e HTTPS, acesso externo ou VPN, política de firewall e responsável pela manutenção. Confirmar se os clientes acessarão de fora da empresa. Nenhuma capacidade do servidor foi verificada até o momento.

### Roteiro de transferência

- Criar um ambiente de homologação separado de produção; fixar versões, configurar segredos, SMTP e URLs de autenticação para cada ambiente.

- Aplicar e testar migrations em uma instalação limpa. Para iniciar produção, preferir estrutura limpa e importar somente os cadastros revisados, sem carregar contas ou rascunhos fictícios.

- Se houver dados reais a preservar, planejar exportação e restauração de dados, usuários Auth e relacionamentos, políticas, funções e eventuais arquivos de Storage. Senhas e sessões não devem ser presumidas portáveis sem teste; configurar novamente serviços e URLs. [3]

- Ensaiar restauração, conferir contagens e vínculos, testar login, recuperação, permissões, revisão concorrente e aprovação. Definir janela de corte, suspensão de escritas e retorno ao ambiente anterior.

- Estabelecer backups fora do servidor, teste periódico de restauração, monitoramento e atualização de segurança antes de liberar clientes.

### Cadastro e correio

O relatório de 17/09 contém, na conferência inicial, 124 linhas com unidade e nome, 120 unidades distintas e 8 linhas sem e-mail. Os compradores ainda não foram importados. Conciliar coproprietários e unidades repetidas, completar tipologias e evitar trazer dados pessoais desnecessários. A nova conta de envio foi solicitada; ter a caixa criada não configura automaticamente o SMTP.

### Fontes e base de verificação

Inspeção do código e documentação local em 18/09/2026; histórico das validações realizadas nesta implementação. Estado das contas reais conforme provisionamento local anterior. As orientações de colaboração e implantação foram conferidas na documentação oficial:

[1] Supabase — Local development workflow
https://supabase.com/docs/guides/local-development/cli-workflows
[2] Supabase — Self Hosting with Docker
https://supabase.com/docs/guides/self-hosting/docker
[3] Supabase — Restore to Self Hosted
https://supabase.com/docs/guides/self-hosting/restore-from-platform
