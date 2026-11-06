# Autenticação e e-mail nas contas oficiais do CityPark

Atualizado em 29/10/2026. Responsável solicitou continuar com Supabase Auth e entrega gerenciada por Resend, usando contas oficiais da empresa. Não haverá importação de usuários do Firebase. O Exclusive terá contas próprias. As anotações datadas abaixo registram o avanço histórico; a tabela de situação representa o estado atual.

## Situação efetivamente verificada

| Item | Situação |
| --- | --- |
| Primeiro acesso e recuperação no código | Implementados e validados com Supabase oficial; Admin e cliente receberam o código e definiram suas próprias senhas |
| Entrega real | Validada com SMTP da conta oficial; Resend registrou entrega ao e-mail da equipe, e responsável confirmou recebimento tanto na caixa oficial como no Gmail do cliente autorizado |
| Supabase online oficial | Projeto citypark-exclusive, referência grfmiuopojbxxbdymqax, organização CityPark Exclusive no plano Free, São Paulo; 19 tabelas públicas protegidas e 26 versões. Totais finais de 29/10: duas contas, um cliente, uma unidade e um Admin |
| Conta/equipe oficial do Resend | Cadastro e e-mail verificados pelo responsável; sessão conferida como exclusive@planoaengenharia.com.br na equipe planoaengenharia |
| E-mail oficial para administrar os serviços | exclusive@planoaengenharia.com.br; responsável confirmou em 28/10 que a equipe acessa a caixa de entrada |
| Domínio | cityparkmcz.com.br, registrado no Registro.br; site atual hospedado no GitHub Pages |
| DNS consultado em 28/10 | Servidores a.sec.dns.br e c.sec.dns.br; MX e SPF existentes referenciam Locaweb; isso não comprova contratação ativa |
| Domínio cadastrado no Resend oficial | acesso.cityparkmcz.com.br, região São Paulo (sa-east-1); Verified no Resend, com TXT DKIM e os dois CNAMEs validados |
| SMTP oficial no Supabase | Responsável criou a chave e salvou a conexão; habilitado, smtp.resend.com:587 e credencial oculta. Entrega real oficial validada em 29/10 |
| Alterações remotas de DNS e hospedagem | Somente as três adições DNS explicitamente autorizadas; hospedagem do site preservada |

## Identidades distintas

- **Conta responsável pelos serviços:** `exclusive@planoaengenharia.com.br`; responsável confirmou que a equipe acessa a caixa de entrada. Usar essa identidade nos serviços oficiais e confirmar o recebimento das mensagens de cadastro.
- **Remetente das mensagens aos clientes:** proposta `nao-responda@acesso.cityparkmcz.com.br`; domínio já verificado no Resend, conexão SMTP oficial ainda pendente. Não é uma caixa de entrada criada automaticamente.
- **Admin do aplicativo:** papel em `staff_users`, separado da administração das plataformas. `exclusive@planoaengenharia.com.br` agora também possui esse papel no projeto oficial, mediante autorização específica de 29/10. A equipe criou a conta, definiu a própria senha e validou o acesso.

## Ordem de execução

1. Caixa oficial identificada e acesso confirmado: `exclusive@planoaengenharia.com.br`. Isso ainda não confirma cadastro no Resend ou no Supabase.
2. Identificar contas oficiais existentes. Se necessário, criar conta/equipe CityPark no Resend e organização CityPark no Supabase sob controle da empresa. O responsável humano faz login, aceita termos e define suas senhas. Confirmar que a equipe consegue recuperar o acesso antes de remover acessos pessoais de teste.
3. Na equipe oficial do Resend, cadastrar o subdomínio proposto `acesso.cityparkmcz.com.br` e obter os registros de verificação. Usar os nomes e valores reais fornecidos pelo painel, nunca valores inventados ou copiados de outra conta.
4. Adicionar no DNS apenas os registros necessários ao novo subdomínio. Preservar os apontamentos do site e os MX/SPF existentes do domínio principal. O caso exige envio; recebimento de e-mails no Resend não faz parte desta implantação.
5. Aguardar a verificação do domínio. Criar uma chave de envio na equipe oficial, preferencialmente limitada ao domínio verificado. Guardar a chave em configuração privada; não colocar no frontend, em capturas ou na conversa.
6. Criar ou selecionar o projeto Supabase online oficial dedicado ao Exclusive. Aplicar migrations e publicar as Edge Functions necessárias, sem executar seeds fictícios em produção. Provisionar o Admin oficial no projeto correto, com autorização específica para essa concessão; a autorização anterior era restrita ao banco local.
7. Configurar SMTP no Auth remoto: host `smtp.resend.com`, porta `587`, usuário `resend`, senha igual à chave de envio oficial, remetente no subdomínio verificado e nome `City Park Exclusive`. As configurações do Supabase local não são transferidas automaticamente.
8. Configurar no Auth remoto o template de recuperação de `supabase/templates/recovery.html`, código de seis dígitos, validade de 600 segundos e cadastro público desabilitado. Definir a URL pública e as URLs de redirecionamento correspondentes ao ambiente que será publicado.
9. Configurar o build do Exclusive com URL e chave pública do projeto online oficial. Chave administrativa e chave SMTP permanecem no servidor/provedor. Confirmar o ambiente de homologação/publicação antes de substituir o site atual.
10. Validar uma conta de cliente controlada pela equipe: cadastro pelo Admin, vínculo a uma unidade, recebimento do código, definição de senha, login e recuperação posterior. Confirmar remetente, domínio, rejeição de código incorreto/reutilizado e acesso somente às unidades vinculadas. Usar somente destinatários autorizados para o teste.
11. Após a validação oficial, substituir a configuração pessoal também nos ambientes locais que precisarem enviar e-mails e encerrar as credenciais pessoais de teste que deixarem de ser necessárias. Registrar a conclusão e os responsáveis sem registrar segredos.

## Registros efetivamente gerados para o domínio oficial

Em 28/10, cadastrado `acesso.cityparkmcz.com.br` na equipe oficial `planoaengenharia`, em São Paulo. Recebimento desabilitado; envio habilitado no cadastro, ainda sujeito à verificação DNS. Não foi criada chave de envio oficial nem alterado o SMTP local nesta etapa.

Painel: https://resend.com/domains/add/3064c1a3-05a1-41cd-9c11-d81f8dc4c816

Nomes relativos à zona `cityparkmcz.com.br`, conforme exibidos no painel:

| Tipo | Nome | Valor |
| --- | --- | --- |
| TXT | resend._domainkey.acesso | p=MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQDQszVTO1sOK69O5sRkqlkfGn4oRHm0xzIeqHkiRzh4OiGtzyOQec388TjcniHlyTrl/UKKN3bvroD0U25NFaI1TkTSzSbDDWRPKikKcRJO7y6Cdd7XWr+kr/ulqLbu27bOAlRJ6slUkNjpjaBLUyWRfNbEMRSka5z7yQk/l1pnAwIDAQAB |
| CNAME | rsend.acesso | rsend-sae1.forge.rmta.net |
| CNAME | send.acesso | send.forge.rmta.net |

O conteúdo TXT é uma chave pública DKIM, não é a chave privada de envio. TTL no Resend: Auto. Conferir os campos e a regra de nomes do editor do Registro.br antes de salvar; preservar todos os registros existentes. Nenhum MX do domínio principal precisa ser substituído por esses três registros. Depois de publicados, validar a resolução pública e acionar a verificação no Resend.

### Revisão no Registro.br — aguardando autorização

Responsável entrou no painel e pediu confirmação antes de mudanças importantes. Consultados os 25 registros atuais e guardada cópia da tabela em `outputs/backups/citypark-dns-before-official-email-20261028.txt` (arquivo local ignorado pelo Git, sem dados da conta administrativa). As três adições foram preparadas apenas no formulário, totalizando 28 entradas no rascunho. Comparação textual confirmou os 25 registros originais preservados, na mesma ordem e com os mesmos valores. Botão Salvar alterações ainda não acionado; publicação depende de autorização explícita. Revisão local em `outputs/qa/citypark-dns-pending-approval-20261028.png`.

### Publicação autorizada — 28/10/2026

Após apresentar as três adições e pedir autorização para salvá-las, o responsável respondeu “Ok”. Antes do clique em Salvar alterações, o rascunho foi comparado integralmente com a cópia aprovada. Depois do salvamento, a zona foi reaberta: 28 registros persistidos, nenhuma alteração pendente, 25 registros originais preservados e somente os três novos registros aprovados. Cópia posterior em `outputs/backups/citypark-dns-after-official-email-20261028.txt`.

Consultas públicas com Resolve-DnsName já retornaram o TXT DKIM e os dois CNAMEs esperados. Acionada a verificação no Resend, inicialmente em Pending. A criação da conta Supabase oficial foi aberta com exclusive@planoaengenharia.com.br para conclusão pelo responsável; senha e aceite de termos são feitos pelo próprio responsável. Nenhuma chave de envio oficial foi criada e nenhuma configuração SMTP pessoal foi substituída até aqui.

O Resend confirmou DNS verified às 15h31 e Domain verified às 15h32 (horário de São Paulo). Os três registros aparecem como Verified e o recebimento continua desabilitado. A consulta pública também confirmou igualdade integral da chave DKIM com o valor do painel. Evidência: `outputs/qa/resend-official-domain-verified-20261028.png`. Domínio pronto para envio, ainda dependendo de chave oficial e configuração no Supabase para o fluxo funcionar com as contas oficiais.

### Conta Supabase oficial e organização proposta

Responsável concluiu o login na conta oficial. Conferidos no painel o e-mail exclusive@planoaengenharia.com.br e a ausência de organizações acessíveis. Formulário preparado com nome CityPark, categoria N/A (porte empresarial não informado) e plano Free, exibido como US$ 0/mês. Nenhuma criação confirmada; aguardando autorização conforme solicitação do responsável para mudanças importantes. Evidência: `outputs/qa/supabase-official-organization-pending-20261028.png`. O banco local permanece independente, sem vínculo configurado em supabase/.temp/project-ref; o trabalho local será aproveitado na implantação.

### Organização criada após autorização

Responsável autorizou a criação no plano Free. Na retomada, o nome do formulário estava CityPark Exclusive, preservado no cadastro. Organização criada e confirmada no painel, sem projetos, com identificador `paifzhzwppdrfavbxsbi`. Preparado o formulário do primeiro projeto com nome `citypark-exclusive` e região South America (São Paulo), sa-east-1. Data API habilitada; exposição automática de novas tabelas desabilitada; RLS automático do painel mantido no padrão desabilitado (as migrations devem habilitar as políticas explicitamente). Nenhuma conexão GitHub configurada.

A senha do banco não foi preenchida pelo agente e o botão Create new project não foi acionado. A definição da credencial e a confirmação de criação serão realizadas pelo próprio responsável. Evidência: `outputs/qa/supabase-official-project-prepared-20261028.png`. Antes de aplicar migrations no projeto novo, conferir grants explícitos necessários ao frontend, pois a exposição automática de novas tabelas está desabilitada.

### Projeto criado e pacote inicial validado

Responsável criou o projeto `grfmiuopojbxxbdymqax`. Conferidos nome citypark-exclusive, organização CityPark Exclusive, região sa-east-1 e status Healthy. Consulta somente de leitura confirmou banco vazio (0 tabelas públicas, 0 usuários Auth). Preparada a [revisão da implantação inicial](implantacao-banco-oficial-2026-10-28.md): 25 migrations, testadas em banco temporário local separado, resultando em 41 tabelas com RLS e nenhuma conta ou dado de cliente. O pacote recusa banco já preenchido e não inclui seeds. Os 23 testes JavaScript e build passaram.

Nenhuma migration remota foi executada; aguarda autorização explícita. O editor SQL não respondeu à carga do pacote completo, e o painel foi recuperado em nova aba. O arquivo e o manifesto locais são a fonte íntegra para revisão; conferir integridade do envio após autorização. Não presumir que o rascunho do navegador esteja completo.

### Retomada e conferência — 29/10/2026

Confirmada a instalação otimizada autorizada pelo responsável: 19 tabelas protegidas, 26 versões e zero contas, clientes, unidades ou equipe no projeto oficial. A instalação eliminou as estruturas antigas sem importar dados locais. Detalhes e validação em [registro da instalação](implantacao-banco-oficial-2026-10-28.md).

Sessões dos dois provedores disponíveis. O Resend mantém acesso.cityparkmcz.com.br como Verified e não possui chaves. O Supabase ainda estava com SMTP personalizado desabilitado. Preparado no Resend o formulário de chave `CityPark Exclusive - Supabase Auth`, permissão `Sending access`, somente para `acesso.cityparkmcz.com.br`; botão Add não acionado.

Preparado, sem salvar, o formulário SMTP do Supabase com remetente `nao-responda@acesso.cityparkmcz.com.br`, nome `City Park Exclusive`, host `smtp.resend.com`, porta `587` e usuário `resend`. Campo Password vazio. Nenhuma chave foi criada, nenhum envio realizado e nenhum Admin remoto concedido. A criação/entrada da credencial será concluída pelo responsável; não registrar a chave em conversa, capturas ou Git. Evidência sem segredo: `outputs/qa/resend-official-sending-key-prepared-20261029.png`.

Revisão somente de leitura identificou os padrões remotos ainda não ajustados: cadastro público habilitado, confirmação de e-mail habilitada, acesso anônimo desabilitado, provedor de e-mail habilitado, código com oito dígitos e validade de 3.600 segundos. Antes do teste no Exclusive, alinhar código para seis dígitos/600 segundos, aplicar o modelo recovery.html e bloquear cadastro público conforme o fluxo já validado localmente. Nenhuma dessas configurações foi salva nesta conferência. A interface exige senha de pelo menos dez caracteres; revisar a regra correspondente no servidor ao preparar a aprovação.

### SMTP salvo pelo responsável e próxima autorização

Responsável confirmou criação da chave e salvamento no Supabase. A configuração persistida foi conferida em página nova após carregamento: envio habilitado, nome City Park Exclusive, host smtp.resend.com, porta 587 e credencial armazenada oculta, sem necessidade de ler seu valor. A apresentação inicial do formulário antes de terminar o carregamento não deve ser tratada como estado persistido. Evidência: `outputs/qa/supabase-official-smtp-saved-20261029.png`.

Preparados, sem salvar, código de seis dígitos/600 segundos e assunto/corpo de recuperação idênticos ao arquivo recovery.html, com integridade textual conferida e prévia visual em português. Solicitada autorização conjunta para aplicar esses ajustes, bloquear cadastro público e criar o primeiro Admin oficial. Formulário de criação de usuário preenchido somente com exclusive@planoaengenharia.com.br, confirmação automática desmarcada e senha vazia; não enviado. Caso o painel exija senha, a equipe deverá preenchê-la e confirmar diretamente, sem transmitir a credencial pela conversa.

`scripts/provision-official-admin.sql` prepara a atribuição exclusiva do papel ao e-mail oficial, depois de criada a conta pelo Auth. Recusa conta ausente/ambígua, vínculo de cliente ou perfil divergente/inativo, preserva demais usuários e não define senha. Ainda não executado. Não existe autorização remota de Admin até a resposta específica do responsável.

### Configuração aplicada e fluxo oficial validado — 29/10/2026

O responsável autorizou expressamente salvar código de seis dígitos/600 segundos, mensagem de recuperação em português, bloqueio do cadastro público e criação do primeiro Admin oficial. Configurações salvas e conferidas no painel; demais proteções de e-mail/acesso anônimo preservadas. O modelo enviado ao editor foi comparado integralmente ao recovery.html antes de salvar.

O painel de criação exigiu senha. O responsável criou a conta diretamente e informou ter marcado Auto confirm user por engano; não houve leitura da senha nem reversão silenciosa dessa opção. Atribuído exclusivamente a essa conta o perfil Admin por scripts/provision-official-admin.sql, com guardas de identidade e de conflito de papéis. Resultado admin/active=true conferido. O responsável recebeu o código na caixa oficial, definiu a senha pela interface do Exclusive e confirmou o acesso de Admin. Resend listou Delivered; o corpo e o código do e-mail não foram abertos pelo agente.

Em seguida, o responsável autorizou publicar admin-customer e usar a validação de sessão dentro da função, em lugar da verificação antiga do gateway. Fonte no editor comparada integralmente ao arquivo do repositório. Função publicada em https://grfmiuopojbxxbdymqax.supabase.co/functions/v1/admin-customer; Verify JWT with legacy secret desativado e configuração local alinhada. Auth.getUser e current_staff_role='admin' continuam obrigatórios antes de qualquer criação de conta. Não foram criadas ou copiadas chaves administrativas para o frontend. Testes HTTP reais: requisição anônima e token inválido rejeitados com 403, corpo vazio e nenhuma conta criada.

Cadastro do cliente autorizado Vinícius realizado pelo painel Admin usando a função publicada. Conta criada sem senha escolhida pelo operador, convite ou confirmação automática; estado inicial de e-mail não confirmado conferido no banco. A presença de hash interno do Auth não foi tratada como prova de senha escolhida. A senha nunca foi consultada.

Criada somente a unidade 1505A autorizada para validação, torre A/andar 15/terminação 05, com tipologia A confirmar, área e prazo nulos, status pending/ativa. Script de registro em outputs/deployment/grfmiuopojbxxbdymqax/authorized-test-unit.sql recusa unidade existente e exige cliente já cadastrado. Nenhuma planta-base, imagem ou opção fictícia foi importada. Vínculo ativo de proprietário salvo pelo painel Admin, sem prazo geral ou de módulo.

O responsável recebeu o código no Gmail autorizado, definiu a própria senha e confirmou entrada com a unidade 1505 A na seleção. Navegador conferiu o perfil de cliente, somente a unidade vinculada e Planta em preparação. Consulta final: 19 tabelas, zero sem RLS, duas contas Auth, um cliente, uma unidade, um perfil de equipe Admin, um vínculo ativo owner e e-mail do cliente confirmado.

O modo local official foi preparado em .env.official.local (somente URL e chave pública, ignorado pelo Git), preservando o ambiente local padrão e sua configuração de teste. Servidor de validação em http://127.0.0.1:5175/exclusive/. Build official e cópia de assets concluídos. **Não houve publicação do frontend em cityparkmcz.com.br**. Plantas, catálogo e demais unidades reais dependem de dados oficiais e da próxima etapa de implantação. Credenciais pessoais locais anteriores não foram revogadas nem copiadas para o projeto oficial.

Validação automatizada: 31 testes passaram, incluindo oito testes isolados do handler para negar identidades ausentes/inválidas e arquiteta, validar dados, impedir registro após falha no Auth e reutilizar conta existente sem duplicação. Não executados scripts de fixtures no servidor oficial. Referência sobre a verificação de tokens: https://supabase.com/docs/guides/functions/auth e https://supabase.com/docs/guides/auth/signing-keys.

Evidências sem segredos:

- outputs/qa/resend-official-first-email-delivered-20261029.png
- outputs/qa/exclusive-official-admin-login-20261029.png
- outputs/qa/supabase-official-customer-function-published-20261029.png
- outputs/qa/exclusive-official-customer-unit-linked-20261029.png
- outputs/qa/exclusive-official-customer-first-access-20261029.png
- outputs/qa/supabase-official-final-counts-20261029.png

## Critério de conclusão

A etapa de autenticação oficial foi concluída: projeto Supabase, equipe Resend e remetente oficial configurados, cadastro/vínculo do cliente e primeiro acesso confirmados pelo responsável com essas credenciais. A publicação do frontend no domínio e o preenchimento integral do catálogo/unidades continuam como próximas etapas; o teste atual usa a interface local conectada ao banco oficial.

## Referências

- [SMTP no Supabase](https://supabase.com/docs/guides/auth/auth-smtp)
- [Acesso a organizações e projetos Supabase](https://supabase.com/docs/guides/platform/access-control)
- [Equipes no Resend](https://resend.com/docs/dashboard/settings/team)
- [Domínios e subdomínios no Resend](https://resend.com/docs/dashboard/domains/introduction)
- [Validação local já realizada](validacao-primeiro-acesso-2026-10-27.md)
