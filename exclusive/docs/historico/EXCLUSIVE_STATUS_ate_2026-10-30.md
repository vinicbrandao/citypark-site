# CityPark Exclusive — Checkpoint Técnico

> **Arquivo de continuidade do projeto**
>
> Este documento deve ser utilizado como fonte de contexto ao iniciar um novo Chat, Work, Codex ou outra sessão de IA relacionada ao **CityPark Exclusive**.
>
> **Regra principal para qualquer IA que leia este arquivo:** não assumir que algo foi implementado apenas porque está descrito como arquitetura, proposta ou próximo passo. Sempre distinguir entre:
>
> - **IMPLEMENTADO / TESTADO**
> - **DECIDIDO / DEFINIDO**
> - **PLANEJADO / PENDENTE**

---

## 1. Identificação do checkpoint

- **Projeto:** CityPark Exclusive
- **Checkpoint criado em:** 05/10/2026
- **Última atualização do checkpoint:** 21/10/2026 — layout e imagens de Bancadas na seção 54; expansão da prévia na seção 53; tela estática na seção 52.
- **Responsável técnico principal:** Vini
- **Supervisor:** Allef

Este arquivo deve ser atualizado ao final de blocos relevantes de desenvolvimento, principalmente após:
- criação ou alteração de migrations;
- mudanças de modelo de dados;
- novas políticas RLS;
- novas RPCs;
- mudanças importantes no frontend;
- testes de autenticação;
- testes de integração;
- importações;
- definição de novas regras de negócio;
- correção de bugs relevantes.

---

# 2. Objetivo do CityPark Exclusive

O **CityPark Exclusive** é uma plataforma destinada aos proprietários de unidades do empreendimento CityPark.

O objetivo é permitir que cada proprietário acesse uma área restrita e personalize sua unidade a partir de opções disponibilizadas pela construtora.

A plataforma deverá evoluir para permitir, entre outras funcionalidades:

- autenticação do proprietário;
- vínculo entre cliente e unidade adquirida;
- suporte a proprietário e coproprietário;
- visualização das unidades vinculadas ao usuário;
- visualização da planta correspondente à unidade;
- catálogo de personalizações;
- seleção de opções;
- regras de compatibilidade entre escolhas;
- salvamento das escolhas;
- histórico das alterações;
- resumo/carrinho de personalizações;
- envio da configuração para aprovação;
- controle de estado da configuração da unidade;
- operação administrativa e/ou técnica por usuários autorizados.

---

# 3. Separação entre o CityPark atual e o Exclusive

## DECIDIDO

O **CityPark Exclusive não utilizará o Firebase como backend principal**.

O site CityPark atual continua utilizando Firebase para as funcionalidades existentes, enquanto o Exclusive utiliza um projeto separado baseado em Supabase.

A separação conceitual é:

```text
CITYPARK ATUAL
├── Firebase Auth
├── Firestore
└── Fluxos atuais de unidades, propostas, corretores e administração

CITYPARK EXCLUSIVE
├── Supabase Auth
├── PostgreSQL
├── Row Level Security (RLS)
├── Migrations
├── Funções / RPCs quando necessário
└── Fluxos próprios de proprietários, unidades e customizações
```

Qualquer integração entre os dois ambientes deve ocorrer de forma **controlada**, por importação, sincronização ou processo explicitamente definido.

Não criar acoplamento direto com as coleções Firebase do sistema atual sem uma decisão arquitetural específica.

---

# 4. Arquitetura e stack

## DECIDIDO

### Frontend

- Vite
- JavaScript
- HTML
- CSS

O frontend do Exclusive está sendo desenvolvido separadamente e é destinado a ser disponibilizado dentro do site CityPark, no caminho:

```text
/exclusive/
```

O site principal do CityPark é hospedado via GitHub Pages.

### Backend

- Supabase
- PostgreSQL
- Supabase Auth
- Row Level Security
- Migrations SQL
- RPCs / funções PostgreSQL quando necessárias

### Desenvolvimento local

O ambiente local utiliza:

- Supabase CLI
- Docker
- serviços locais do Supabase
- Mailpit nos testes de e-mail/autenticação

---

# 5. Responsabilidades

## Vini

Responsável principalmente por:

- arquitetura técnica;
- implementação do frontend;
- Supabase;
- modelagem relacional;
- migrations;
- políticas RLS;
- funções e RPCs;
- integração frontend ↔ banco;
- autenticação;
- validações;
- testes;
- scripts auxiliares;
- importação/sincronização de dados;
- validação do banco;
- segurança de acesso;
- integração final do Exclusive ao site CityPark.

## Allef

Responsável principalmente por:

- definição/modelagem das opções de personalização;
- Revit;
- renders;
- quantitativos;
- combinações possíveis;
- regras técnicas das customizações;
- conteúdo técnico das opções oferecidas ao proprietário.

---

# 6. Estado do ambiente local

## IMPLEMENTADO / TESTADO

O Supabase local foi iniciado e utilizado com sucesso através do Docker.

Últimas versões registradas durante o desenvolvimento:

```text
Supabase CLI:          2.118.0
PostgreSQL:            17.6.1.171
PostgREST:             v16.3
GoTrue/Auth:           v2.197
Realtime:              v2.135.3
Storage API:           v1.77
Supabase Studio:       2026.09.14
```

Essas versões representam o último ambiente registrado e não devem ser tratadas como requisito permanente do projeto.

---

# 7. Correção do ambiente Supabase / PostgREST

## IMPLEMENTADO / TESTADO

Durante os testes locais ocorreu um problema relacionado ao token JWT, apresentando comportamento compatível com:

```text
JWT issued at future
```

Foi realizada atualização/correção do ambiente local, incluindo o PostgREST para:

```text
v16.3
```

Após a alteração:

- o login voltou a funcionar;
- o erro não voltou a aparecer no teste realizado;
- a unidade de teste `1209A` foi carregada corretamente.

---

# 8. Autenticação

## IMPLEMENTADO / TESTADO

O projeto já possui fluxo de autenticação utilizando Supabase Auth.

Foram trabalhados/testados fluxos de:

- login com e-mail e senha;
- primeiro acesso;
- redefinição/recuperação de senha;
- troca de senha;
- logout;
- acesso ao ambiente após autenticação.

### Teste de troca de senha

Foi validado manualmente que:

1. a senha incorreta é rejeitada;
2. a senha antiga deixa de funcionar após a alteração;
3. a nova senha é aceita;
4. o usuário consegue realizar novo login utilizando a senha atualizada.

Esse fluxo foi considerado aprovado no último teste manual registrado.

---

# 9. Tela “Defina sua senha”

## IMPLEMENTADO / CORRIGIDO

Foi identificado um problema de experiência de uso:

> Ao digitar uma senha na tela **“Defina sua senha”** e trocar temporariamente de aba do navegador, os campos eram apagados quando o usuário retornava.

Esse comportamento foi corrigido.

Após a alteração, os dados digitados nos campos da etapa de definição de senha passaram a permanecer durante a troca de aba, dentro do comportamento esperado para o fluxo atual.

Esta correção deve ser preservada em futuras refatorações da autenticação.

---

# 10. Base já existente antes da fase atual

## IMPLEMENTADO / TESTADO

O projeto já possuía uma base funcional contendo:

- aplicação Vite/JavaScript;
- Supabase local;
- migrations;
- autenticação;
- vínculos entre cliente e unidade;
- estrutura de rascunhos;
- histórico/revisão de salvamentos;
- políticas de acesso;
- seeds fictícios;
- scripts de validação;
- testes automatizados.

Em uma revisão anterior foram registrados:

```text
13 testes automatizados aprovados
build aprovado
```

Também existem scripts locais utilizados durante validações, incluindo:

```bash
npm run db:start
node scripts/seed-local.mjs
node scripts/seed-staff-local.mjs
npm test
npm run build
node scripts/test-access-local.mjs
node scripts/test-staff-local.mjs
```

Os nomes acima representam scripts existentes no estado anteriormente revisado do projeto. Antes de usá-los em uma sessão futura, confirmar que continuam presentes no repositório atual.

---

# 11. Isolamento entre clientes

## IMPLEMENTADO / TESTADO

Foram utilizados usuários/clientes fictícios para verificar isolamento de acesso.

Referências principais do ambiente de teste:

```text
Cliente A → unidade 1209A
Cliente B → unidade 1210A
```

O objetivo desses testes é garantir que um cliente não tenha acesso às unidades pertencentes a outro cliente.

Os testes locais já abordaram aspectos de:

- isolamento entre clientes;
- perfis;
- auditoria;
- revogação de acesso.

A política final de autorização deve continuar sendo protegida pelo banco através de RLS, e não apenas pelo frontend.

---

# 12. Importação fictícia e cadastros

## IMPLEMENTADO / TESTADO NO AMBIENTE DE DESENVOLVIMENTO

Foi executado um fluxo de importação fictícia para validar o processo de entrada de clientes, unidades e vínculos.

Lote de teste registrado:

```text
4bd2c7dc-a993-4b9a-87c6-a95f397cf2b9
```

No preview do lote foram registrados:

```text
6 linhas recebidas
5 linhas aceitas
1 linha repetida
0 linhas pendentes
```

Após aplicação:

```text
5 clientes
4 unidades
5 vínculos cliente ↔ unidade
```

O cenário incluiu:

- uso de `external_ref`;
- unidade compartilhada;
- relacionamento com proprietário e coproprietário;
- múltiplos vínculos;
- validação de reaplicação do mesmo lote.

A segunda aplicação do lote retornou comportamento idempotente, com registro equivalente a:

```text
already_applied: true
```

Portanto, o processo testado não deveria duplicar os dados quando o mesmo lote fosse reaplicado.

### Atenção

Esses dados são **fictícios e de desenvolvimento**.

Não confundir esse teste com a importação dos compradores reais do CityPark.

---

# 13. Proprietário e coproprietário

## IMPLEMENTADO EM PARTE / REGRA FINAL PENDENTE

customer_units aceita owner e co_owner. Ambos podem salvar a configuração da unidade e conceder/revogar autorização à arquiteta pelos RPCs atuais. A revisão otimista impede sobrescrita silenciosa.

Em 06/10/2026, Vini decidiu que owner e co_owner poderão enviar e editar a mesma proposta da unidade. O envio e o versionamento já existem no banco local; faltam a interface e a regra de confirmação/aprovação final após o parecer técnico.

---

# 14. Relação entre personalização e unidade

## DECIDIDO

As personalizações não devem existir isoladamente apenas no cliente.

Elas devem estar relacionadas ao vínculo/registro da unidade do cliente, conceitualmente associado a:

```text
customer_units
```

Isso é importante porque:

- um cliente pode possuir mais de uma unidade;
- uma unidade pode possuir mais de um proprietário;
- cada unidade possui sua própria configuração;
- histórico e estado da personalização pertencem à unidade;
- diferentes unidades podem utilizar a mesma planta.

---

# 15. Modelo de plantas

## PROTÓTIPO IMPLEMENTADO / MODELO DEFINITIVO DECIDIDO EM PARTE

No protótipo, plans contém combinações de escolhas social e suíte; unit_plans oferece várias combinações por unidade e plan_features guarda as duas partes da escolha. **DECIDIDO por Vini:** essas combinações são opções sobre uma planta base reutilizável. No modelo definitivo, a equipe CityPark atribuirá explicitamente uma planta base a cada unidade e social/suíte serão escolhas da configuração, não linhas distintas de plantas. A planta pode variar conforme a terminação.

As migrations correspondentes foram restauradas nesta pasta a partir do histórico do banco local. Consultar docs/catalogo-personalizacao-modelo.md.

---

# 16. Catálogo de personalização

## PROTÓTIPO NO BANCO LOCAL / MODELO DEFINITIVO PENDENTE

Allef modificou esta pasta antes da entrada de Vini e usou o Supabase local para explorar o Exclusive. As tabelas e dados de outubro são referências de teste para Vini modelar o banco definitivo. O Supabase local já possui customization_groups, customization_options e option_compatibilities. Também possui unit_configuration_state, customer_customizations, customization_history e customization_windows. O banco local contém 12 combinações de escolhas social/suíte tratadas como plantas no protótipo e 8 opções de materiais da interface atual, além de 2 plantas e 2 opções de teste. Não foi encontrado seed do catálogo nesta pasta; esses registros são dados de teste, não um catálogo aprovado.

Os RPCs novos validam disponibilidade da planta, opções ativas, uma escolha por grupo, janela de personalização e revisão. option_compatibilities é uma lista de opções permitidas por planta; não representa dependências ou exclusões entre pares de opções.

Área social e Suíte Master pertencem ao módulo Planta. Esse módulo terá um prazo próprio por unidade; vencido o prazo, o cliente poderá consultar as escolhas, mas não alterá-las. O prazo de Planta não bloqueia outros módulos. No protótipo, customization_windows vale para a unidade inteira, então o modelo e os RPCs precisarão ser ajustados.

A interface ainda usa unit_drafts e save_unit_draft. Não tratar o schema de teste como modelo definitivo nem o catálogo como integrado ao frontend.

---

# 17. Estrutura funcional planejada para o proprietário

## IMPLEMENTADO NO BANCO LOCAL / INTERFACE PENDENTE

A experiência do proprietário deverá evoluir para algo equivalente a:

```text
Login
  ↓
Meus apartamentos
  ↓
Selecionar unidade
  ↓
Detalhes da unidade
  ↓
Planta
  ↓
Grupos de personalização
  ↓
Escolhas
  ↓
Resumo / carrinho
  ↓
Revisão
  ↓
Envio para aprovação
```

Também deverá existir histórico das alterações.

---

# 18. “Meus apartamentos”

## PLANEJADO

O proprietário deverá conseguir visualizar todas as unidades às quais possui acesso.

Isso precisa suportar:

- um usuário com uma unidade;
- um usuário com várias unidades;
- uma unidade com proprietário e coproprietário.

O acesso deve ser garantido pelo banco através de RLS.

---

# 19. Detalhes da unidade

## PLANEJADO

A tela de detalhes deverá reunir progressivamente informações como:

- identificação da unidade;
- planta;
- proprietário(s);
- estado da personalização;
- progresso das escolhas;
- grupos disponíveis;
- opções selecionadas;
- histórico;
- prazos quando aplicáveis.

---

# 20. Histórico de customizações

## IMPLEMENTADO NO BANCO / INTERFACE PENDENTE

customization_history armazena um instantâneo por revisão da configuração nova, tanto para rascunhos parciais quanto para escolhas normalizadas. O histórico legado draft_history continua existindo para unit_drafts. A interface atual ainda usa o fluxo legado.

---

# 21. Carrinho / resumo

## PLANEJADO

Antes do envio final, o proprietário deverá visualizar um resumo das escolhas feitas.

Esse resumo deverá funcionar como uma etapa de conferência da configuração da unidade.

O termo “carrinho” é conceitual; a implementação final pode utilizar outro nome na interface.

---

# 22. Envio para aprovação

## PLANEJADO

Owner ou co_owner podem enviar pelo RPC `submit_unit_proposal` depois de concluir as escolhas. Alterações posteriores permanecem na mesma proposta; a arquiteta consulta a revisão mais recente, com histórico preservado. O banco local implementa essa regra; botão, mensagem de confirmação e fila da equipe ainda não estão na interface.

O sistema precisará controlar estados da configuração, por exemplo:

```text
rascunho
em preenchimento
enviado
em análise
aprovado
requer alteração
```

Os nomes e estados definitivos ainda precisam ser formalizados.

Não criar enum ou regra final baseada apenas nessa lista sem revisar as regras de negócio.

---

# 23. Usuários administrativos / técnicos

## IMPLEMENTADO EM PARTE

staff_users distingue admin e architect. staff_unit_assignments limita o escopo da arquiteta por unidade. O acesso efetivo da arquiteta também exige autorização vigente de proprietário ativo, registrada em architect_authorizations e seu histórico de eventos. Admin acessa unidades ativas.

Há RPC para a equipe salvar configuração e RPC para a arquiteta registrar revisão técnica por revisão salva. A revisão técnica não equivale à aprovação final nem altera o status da configuração.

---

# 24. Segurança

## REGRA ARQUITETURAL

A segurança do Exclusive deve ser garantida principalmente no banco.

Princípios:

- nunca confiar apenas em bloqueios do frontend;
- proteger dados através de RLS;
- validar usuário autenticado;
- restringir acesso às unidades vinculadas ao usuário;
- restringir operações administrativas;
- validar alterações sensíveis no servidor/banco;
- manter histórico quando necessário;
- evitar operações de atualização genéricas sem validação;
- usar migrations para alterações estruturais.

---

# 25. Dados reais

## NÃO IMPLEMENTADO

Até o checkpoint atual:

- os compradores reais não devem ser considerados oficialmente importados;
- os dados utilizados nos testes são fictícios;
- o catálogo definitivo de customizações ainda depende das definições de Allef;
- imagens/renders finais ainda não devem ser assumidos como disponíveis;
- preços e dados comerciais definitivos não devem ser inventados.

Toda IA que continuar o projeto deve respeitar isso.

---

# 26. Supabase online / homologação

## PENDENTE

O desenvolvimento e os testes principais registrados ocorreram utilizando o ambiente local.

A configuração definitiva de um ambiente online de homologação/produção deve ser tratada separadamente.

Antes de publicação:

- revisar migrations;
- revisar variáveis de ambiente;
- revisar Auth;
- revisar URLs de redirect;
- revisar RLS;
- revisar e-mail/SMTP;
- revisar dados de seed;
- garantir que dados fictícios não sejam enviados para produção;
- executar testes de acesso.

---

# 27. E-mail

## DESENVOLVIMENTO LOCAL

Durante o desenvolvimento local, o fluxo de e-mail pode utilizar Mailpit.

Referências anteriores do ambiente local:

```text
Supabase Studio → porta 54323
Mailpit         → porta 54324
```

SMTP e envio real deverão ser tratados na etapa de homologação/produção.

---

# 28. Pontos que NÃO devem ser assumidos

Uma IA retomando este projeto **não deve assumir** que:

- toda modelagem proposta já virou migration;
- todas as tabelas conceituais já existem;
- o catálogo de customização está pronto;
- compradores reais foram importados;
- SMTP real está configurado;
- o sistema já está publicado para clientes;
- owner/co_owner já possuem regras finais de edição;
- todas as regras administrativas estão finalizadas;
- imagens/renders definitivos estão disponíveis;
- os nomes conceituais das futuras tabelas são definitivos.

Sempre verificar o repositório antes de alterar o banco.

---

# 29. Próximo passo recomendado

## PONTO DE RETOMADA

Plano detalhado para o fluxo solicitado em 06/10/2026: `docs/plano-fluxo-propostas.md`. Ele ordena catálogo/prazos, salvamento por módulo, fechamento dos caminhos legados, pedido de ajuda, envio versionado, edição após envio, revisão/avisos e testes.

1. Receber da equipe CityPark a lista das plantas base reais, a atribuição por unidade e os prazos do módulo Planta. As tabelas estruturais já existem no banco local, mas permanecem sem esses dados.
2. Validar com Allef os grupos Área social/Suíte Master, opções reais, disponibilidade por planta, renders, quantitativos e eventuais regras de compatibilidade. Os registros atuais do protótipo não são catálogo oficial.
3. Integrar `save_unit_module_choices` à interface após obter planta, opções e prazos reais. Migrar a configuração corrente somente com mapeamento confiável; preservar o histórico legado e revogar/substituir os RPCs antigos que contornam a regra de prazo.
4. Ampliar os testes pela API real, inclusive mudanças concorrentes. Integrar à interface o pedido de ajuda, o envio da proposta, a visualização da versão mais recente e a revisão da arquiteta. Definir confirmação final, avisos externos e preços oficiais em etapas próprias.

---

# 30. Último ponto de parada

### Concluído em 06/10/2026

- migration 20261005000100_unit_base_plans_and_modules.sql aplicada ao Supabase local;
- agora as 13 versões locais e aplicadas coincidem;
- as nove unidades fictícias receberam tower_code e termination_code coerentes com o código e andar já cadastrados;
- criadas base_plans, unit_base_plan_assignments, customization_modules e unit_module_windows, com RLS. Planta é o único módulo cadastrado; ainda não há plantas base, atribuições ou prazos reais;
- teste RLS em transação revertida: proprietário da unidade viu planta atribuída, prazo e módulo; usuário de outra unidade não viu nenhum desses registros. Nenhum dado de teste permaneceu;
- authenticated não possui INSERT nas novas tabelas. Nenhuma RPC ou tela foi alterada neste dia.

### Estado atual

O schema estrutural para planta base e prazo por módulo está ativo apenas no Supabase local. O bloqueio de edição de Planta ainda não está funcional: os RPCs e a interface continuam no fluxo legado, e as plantas e datas reais não foram cadastradas.

Atualização posterior em 06/10/2026: o novo RPC `save_unit_module_choices` já valida prazo e revisão no banco local, mas a interface ainda chama `save_unit_draft`; portanto o bloqueio de Planta ainda não é efetivo na jornada do cliente. Detalhes e testes na seção 37.

Outra continuação no mesmo dia criou pedidos de ajuda à arquiteta no banco local, com estados e histórico; a interface ainda não usa esse fluxo. Detalhes na seção 38.

A continuação seguinte criou a proposta única por unidade, versões após edições e parecer técnico da arquiteta no banco local. A interface ainda não usa esse fluxo. Detalhes na seção 39.

Em 06/10/2026, o fluxo de proposta foi comparado com o código e registrado em `docs/plano-fluxo-propostas.md`. Login e unidades estão operacionais no ambiente de desenvolvimento; pedido de ajuda na interface, envio formal, mensagem de recebimento, edição versionada após envio e bloqueio por módulo seguem pendentes. A existência do valor `submitted` em um check de tabela não representa um fluxo de envio implementado.

Decisão de Vini no mesmo dia: owner e co_owner podem enviar e editar; alterações depois do envio atualizam a mesma proposta, e a arquiteta consulta a revisão mais recente. Preservar revisões anteriores no histórico e impedir parecer técnico sobre revisão ultrapassada. Esta é uma regra decidida, ainda não implementada.

---

# 31. Procedimento para retomar o projeto em uma nova conversa

Ao iniciar um novo Chat, Work ou Codex, utilizar uma instrução semelhante a:

```text
Leia primeiro o arquivo EXCLUSIVE_STATUS.md.

Ele é o checkpoint técnico do CityPark Exclusive e deve ser utilizado como
fonte de contexto do desenvolvimento.

Antes de alterar qualquer código ou banco:
1. identifique o que está marcado como IMPLEMENTADO/TESTADO;
2. identifique o que está apenas DECIDIDO;
3. identifique o que ainda está PLANEJADO/PENDENTE;
4. analise o estado atual do repositório;
5. compare o repositório com o checkpoint;
6. informe qualquer divergência encontrada;
7. continue a partir da seção "Último ponto de parada".

Não trate propostas de modelagem como estruturas já implementadas.
```

---

# 32. Procedimento de atualização deste checkpoint

Ao terminar uma sessão relevante de desenvolvimento, atualizar:

```text
Data do checkpoint
Concluído
Alterações realizadas
Migrations adicionadas
Tabelas alteradas
RPCs adicionadas/alteradas
RLS alteradas
Arquivos principais alterados
Testes executados
Bugs corrigidos
Decisões tomadas
Pendências
Próximo passo
Último ponto de parada
```

Quando possível, incluir também:

```text
commit
branch
migration
resultado dos testes
```

Isso permite que Chat, Work e Codex retomem o projeto com o mínimo de perda de contexto.

---

# 33. Regra de fonte da verdade

A ordem de confiança deve ser:

```text
1. Estado atual do repositório / banco
2. EXCLUSIVE_STATUS.md atualizado
3. Documentação técnica versionada
4. Conversas anteriores do Project
5. Memória da IA
```

Se existir divergência entre este documento e o código atual, o repositório e o banco devem ser inspecionados antes de qualquer decisão.

Depois da inspeção, este checkpoint deve ser atualizado.

---

# 34. Resumo executivo para IA

```text
Projeto:
CityPark Exclusive.

Objetivo:
Área restrita para proprietários personalizarem unidades compradas no CityPark.

Frontend:
Vite + JavaScript, destinado a /exclusive/ no site CityPark.

Backend:
Supabase separado do Firebase atual.

Banco:
PostgreSQL + RLS + migrations + RPCs quando necessário.

Responsáveis:
Vini = modelagem do banco, implementação, arquitetura técnica, Supabase, integrações e testes.
Allef = modelagem técnica das customizações, Revit, renders e regras.

Estado:
Ambiente local funcionando.
Autenticação validada.
Troca de senha validada.
Problema dos campos de senha ao alternar abas corrigido.
Dezesseis migrations aplicadas localmente; a estrutura de plantas base, prazos, escolhas por módulo, pedidos de ajuda e proposta versionada já está no banco.
Isolamento de clientes trabalhado.
Importação fictícia e idempotência testadas.
Owner/co_owner fazem parte do modelo.
Planta base será atribuída pela equipe a cada unidade; Área social e Suíte Master são escolhas do módulo Planta, com prazo próprio. Catálogo e RPCs de teste existem no banco local.
Configuração pertence à unidade e registra o vínculo customer_units de cada edição.

Ainda não assumir:
que o protótipo de Allef seja o catálogo ou schema definitivo, nem que os
preços, quantitativos ou dados locais sejam oficiais.

Próximo passo:
Obter plantas base, atribuições e prazos da equipe; validar opções com Allef;
depois cadastrar o catálogo aprovado, integrar a interface ao novo salvamento e retirar os caminhos legados de gravação.
```

---

# 35. Registro do dia — 05/10/2026

## Concluído

- Revisado o schema do repositório e do Supabase local. O banco tinha seis migrations de outubro aplicadas cujos arquivos não estavam nesta pasta; os seis SQL foram restaurados a partir do histórico do próprio banco. Antes da nova migration, as 12 versões locais e aplicadas coincidiam.
- Confirmado que o catálogo local veio de testes anteriores de Allef. As 12 combinações de Área social × Suíte Master e as opções de materiais são referência para modelagem, não dados oficiais.
- Documentados o [estado do protótipo](catalogo-personalizacao-modelo.md) e o [modelo alvo do banco](modelo-alvo-banco.md).
- Preparada a migration 20261005000100_unit_base_plans_and_modules.sql. Ela adiciona campos separados para torre/terminação, plantas base e sua atribuição por unidade, o módulo Planta e janelas por unidade/módulo. Mantém as estruturas antigas para a transição.

## Decisões de modelagem

- 1208A significa andar 12, terminação 08, torre A. O protótipo ainda guarda valores como termination = 09A e tower = Torre Liberty; não associar esse rótulo de teste à torre A automaticamente.
- Cada unidade receberá uma planta base pré-selecionada pela equipe CityPark. A mesma planta pode atender várias unidades; a terminação pode influenciar a escolha, mas o banco não deve atribuir a planta sozinho pelo código.
- Área social e Suíte Master são grupos de opções do módulo Planta, não novas plantas. As escolhas alteram estrutura e/ou mobiliário.
- O módulo Planta terá prazo próprio por unidade. Após o vencimento, as escolhas ficam visíveis para o cliente, porém sem edição. Outros módulos permanecem independentes.
- A configuração é compartilhada por owner e co_owner; o histórico registra o autor de cada revisão. Regras de envio final ainda não foram definidas.

## Estado técnico e validação

- **Migration nova:** arquivo preparado, não aplicado. A tentativa de aplicação no Supabase local foi rejeitada pela revisão automática por alterar o banco de forma persistente e instalar políticas de leitura consideradas amplas. A política de leitura dos módulos foi então restringida no arquivo; não houve nova tentativa de aplicação.
- **Tabelas e RLS novos:** existem somente no SQL pendente; não estão ativos no banco. Nenhuma RPC foi criada ou alterada hoje.
- **Testes:** os 13 testes existentes passaram e o build foi concluído antes da preparação dessa migration. O novo SQL ainda não foi executado nem validado no banco.
- **Git:** branch main; nenhum commit criado nesta sessão. Há alterações locais anteriores e os arquivos deste checkpoint ainda não foram commitados.

## Pendências e próximo passo

1. Revisar a migration preparada e obter autorização explícita para aplicá-la ao Supabase local; depois validar schema, RLS e preenchimento dos campos de unidade.
2. Receber da equipe CityPark as plantas base reais, a atribuição por unidade e os prazos do módulo Planta. Não preencher esses dados por inferência do código.
3. Validar com Allef opções, disponibilidade por planta, renders, quantitativos e regras de compatibilidade.
4. Criar migrations e RPCs para escolhas por módulo, bloqueio de Planta no servidor, configuração compartilhada e histórico. Revogar ou substituir caminhos antigos de gravação que possam contornar o prazo.
5. Definir fluxo de envio/aprovação, permissões finais de owner/co_owner e preços oficiais em etapas próprias.

---

# 36. Registro do dia — 06/10/2026

## Concluído

- Lido o checkpoint e revisada a migration estrutural preparada no dia anterior.
- Supabase local iniciado e migration 20261005000100_unit_base_plans_and_modules.sql aplicada. Nenhuma migration anterior foi modificada.
- Conferidas as 13 versões de migration: arquivos locais e banco local coincidem.
- Conferido o preenchimento de torre e terminação nas nove unidades fictícias; nenhuma planta base nem prazo real foi atribuído por inferência.
- RLS validada com registros temporários em transação revertida: proprietário com acesso à unidade viu os novos registros; outro cliente não viu. Não restaram registros do teste, e authenticated não tem permissão de INSERT nessas tabelas.

## Arquivos, banco e testes

- Tabelas adicionadas no banco local: base_plans, unit_base_plan_assignments, customization_modules e unit_module_windows; customization_groups recebeu module_code; units recebeu tower_code e termination_code.
- Políticas RLS das quatro novas tabelas estão ativas. A leitura depende do acesso à unidade; o módulo só aparece quando há janela de uma unidade acessível.
- Nenhuma RPC, frontend ou dado oficial de catálogo foi alterado. Os testes de interface/build de 05/10 não foram repetidos, pois este trabalho foi exclusivamente de banco; a validação desta migration foi feita no Supabase local.
- Branch main, sem commit criado nesta sessão. As alterações locais anteriores permanecem.

## Pendente

- A equipe CityPark ainda preparará plantas base reais, associação unidade → planta e prazo do módulo Planta.
- Allef ainda validará opções e regras técnicas. Falta implementar escolhas e salvamento por módulo, bloquear Planta após o prazo no servidor e encerrar caminhos legados de escrita.
- Permanecem abertas a aprovação final, o limite da edição após envio e os preços oficiais; owner e co_owner já foram definidos como aptos a enviar e editar a mesma proposta.

## Continuação do planejamento em 06/10/2026

- Criado `docs/plano-fluxo-propostas.md`, com ordem das mudanças de banco, interface e testes para pedido de ajuda, envio, revisão e edição posterior.
- Vini decidiu que owner e co_owner enviam/editam a mesma proposta; a arquiteta vê a revisão mais recente. Esta decisão ainda não foi implementada no banco nem na interface.
- Permanecem pendentes a regra de aprovação final, o ponto em que a proposta deixa de ser editável e o canal de aviso à equipe. Nenhuma migration adicional foi aplicada nesta continuação.

---

---

# 37. Continuação técnica — 06/10/2026

## Concluído

- Aplicada ao Supabase local a migration `20261006000100_module_choices.sql`; as 14 versões locais e aplicadas coincidem.
- Criadas disponibilidade de opções por planta base, exclusões entre pares de opções, estado/revisão por unidade e módulo, escolhas correntes e histórico por módulo.
- Criado `save_unit_module_choices`: valida vínculo owner/co_owner ou acesso da equipe, planta atribuída, módulo/grupo/opção ativos, disponibilidade e incompatibilidades, revisão esperada e janela do módulo pelo horário do servidor. Altera somente o módulo solicitado. Escrita direta das tabelas novas não foi concedida a `authenticated`.
- Teste transacional em `scripts/test-module-choices-local.sql`: owner, co_owner, arquiteta autorizada e revogada, usuário de outra unidade, revisão desatualizada, incompatibilidade entre módulos, prazo de Planta vencido e edição de outro módulo ainda aberta. Todas as fixtures foram revertidas; nenhuma planta, opção ou prazo oficial foi cadastrado.

## Limite atual e próximo passo

- O frontend ainda usa `save_unit_draft`. Os RPCs antigos continuam disponíveis, então o prazo de Planta **ainda pode ser contornado no fluxo atual**. Não apresentar esse bloqueio como pronto para clientes.
- Validar catálogo, atribuições e prazos reais; mapear as escolhas correntes; integrar a interface ao novo RPC e retirar os caminhos antigos de escrita na mesma entrega. Testar a API real e depois implementar ajuda e proposta enviada com revisão mais recente.
- Nenhuma regra de envio, comunicação ou aprovação final foi implementada nesta migration. Branch `main`, sem commit criado.

---

# 38. Pedidos de ajuda à arquiteta — 06/10/2026

## Concluído no banco local

- Confirmadas nove unidades fictícias em `units`: 1209A, 1210A, 1301A, 1302A, 1401A, 1501A, 1502A, 1503A e 1505A. Nenhuma planta base oficial está cadastrada.
- Aplicada `20261006000200_architect_assistance_requests.sql`; as 15 migrations locais e aplicadas coincidem.
- Criadas `architect_assistance_requests` e `architect_assistance_events`, com RLS, um pedido aberto por unidade e histórico de abertura, aceite, cancelamento e conclusão.
- RPCs: `request_architect_assistance`, `accept_architect_assistance`, `cancel_architect_assistance` e `resolve_architect_assistance`. O pedido exige vínculo owner/co_owner, arquiteta designada e autorização vigente. Aceite e conclusão ficam com a arquiteta escolhida; owner/co_owner podem cancelar.
- Teste transacional `scripts/test-architect-assistance-local.sql` passou para pedido repetido, RLS de outra unidade, aceite, cancelamento pelo coproprietário, revogação de autorização e conclusão com eventos. O teste terminou com ROLLBACK; pedidos/eventos de teste = 0, plantas base = 0 e unidades = 9.

## Limite e próximo passo

- O cliente ainda não possui botão para solicitar ajuda; a equipe ainda não possui fila/tela de atendimento. O pedido no banco não envia mensagem externa. A autorização à arquiteta continua sendo uma ação separada e explícita; cancelar um pedido não revoga automaticamente essa autorização.
- Prosseguir com o fluxo de proposta enviada e suas revisões, depois integrar a interface. Dados oficiais serão cadastrados posteriormente, sem inferir planta ou opção pelo código da unidade.
- Branch `main`; nenhuma alteração desta sessão foi commitada.

---

# 39. Proposta enviada e versões — 06/10/2026

## Concluído no banco local

- Aplicada `20261006000300_unit_proposals.sql`; as 16 migrations locais e aplicadas coincidem.
- Criadas `unit_proposals` (uma por unidade), `unit_proposal_versions` (instantâneos imutáveis das escolhas e revisões por módulo) e `unit_proposal_reviews` (parecer técnico para uma versão específica), com RLS e leitura restrita à unidade acessível.
- `submit_unit_proposal` exige owner/co_owner, planta base ativa, ao menos uma escolha, grupos obrigatórios preenchidos, opções disponíveis/compatíveis e revisões por módulo iguais às vistas pelo cliente. O envio repetido da mesma configuração devolve a mesma proposta.
- Cada salvamento por módulo após o envio acrescenta uma versão à mesma proposta. `review_unit_proposal` exige arquiteta com acesso vigente e rejeita parecer sobre versão anterior. Trocar/remover a planta base de uma unidade com proposta enviada foi bloqueado até existir um fluxo administrativo explícito para isso.
- `scripts/test-unit-proposals-local.sql` passou: envio, grupo obrigatório, revisão desatualizada, proposta única, edição por co_owner após envio, parecer sobre versão corrente, rejeição de parecer antigo ou de arquiteta revogada, RLS e proteção da planta base. O teste anterior de módulos também passou novamente. As fixtures foram revertidas; propostas/revisões/plantas de teste = 0.
- Para repetir os três testes SQL locais com um comando, usar `npm run test:db-local` na raiz do projeto, com Docker Desktop e Supabase local iniciados. O comando foi executado e mostrou OK para escolhas por módulo, pedido de ajuda e proposta/revisões; ele não testa a interface.

## Limite e próximo passo

- O frontend ainda grava no rascunho legado e não mostra botão de enviar nem fila para arquiteta. Nenhuma mensagem externa ou confirmação final foi implementada; `unit_proposal_reviews` é parecer técnico, não aprovação comercial/final.
- Precisam ser definidos o carregamento administrativo dos dados oficiais, versionamento de catálogo e preços, integração dos RPCs novos à interface, retirada dos caminhos legados e testes pela API real. Até essa troca, o prazo de Planta não protege o fluxo atual do cliente.
- As nove unidades fictícias continuam no Supabase local; nenhuma planta base, opção ou prazo oficial foi cadastrado. Branch `main`, sem commit criado.

---

# 40. Interface local de personalização — 06/10/2026

> Estado histórico: o layout desta etapa foi substituído pela interface aprovada descrita na seção 41; as funções de banco foram mantidas.

## Entregue

- A interface autenticada agora lê as unidades, plantas base atribuídas, opções permitidas por planta, módulos, prazos, escolhas e proposta diretamente do Supabase. O cliente escolhe e salva cada módulo; o servidor valida prazo, vínculo e revisão.
- Proprietário e coproprietário compartilham a mesma proposta. O primeiro envio cria a versão 1; cada salvamento posterior acrescenta uma versão à **mesma** proposta. O cliente abre a edição com “Alterar proposta”. A arquiteta vê a versão mais recente e pode registrar um parecer técnico específico daquela versão. Um novo salvamento deixa o novo parecer pendente.
- O cliente pode pedir ajuda à arquiteta designada, acompanhar o pedido e cancelá-lo. A arquiteta pode aceitar e concluir o atendimento. Autorização de acesso e pedido de ajuda continuam ações separadas.
- Criada `20261006000400_readable_module_catalog.sql` para leitura do catálogo novo pelas unidades acessíveis e `20261006000500_close_legacy_configuration_writes.sql` para revogar de `authenticated` os quatro RPCs legados de gravação. São **18 migrations locais aplicadas**. O caminho ativo de salvamento da interface é `save_unit_module_choices`.
- Criado `npm run db:demo-local`: cadastra três plantas `DEMO-*`, opções e prazos fictícios nas nove unidades de teste e configura senha local para quatro contas de teste. Não há plantas, preços ou catálogo oficiais.
- Os três testes SQL agora criam unidade temporária e revertem tudo no fim; continuam passando mesmo após existir proposta de demonstração. `npm run build`, `npm test` (13 testes antigos) e `npm run test:db-local` passaram. O fluxo novo foi testado manualmente no navegador com login real, salvamento, envio, edição por coproprietário, parecer da arquiteta e pedido de ajuda.

## Como testar agora

1. Com Docker Desktop e Supabase local ativos, na raiz do projeto rode `npm run dev` e abra o endereço informado pelo Vite, com `/exclusive/` ao final. Nesta sessão o endereço é `http://127.0.0.1:5174/exclusive/`.
2. Para testar **primeiro envio**, use `cliente.a@example.test` na unidade 1209A. Para testar uma proposta já enviada, use `cliente.d@example.test` ou `cliente.e@example.test` na unidade 1401A. Use `architect.1@example.test` para o parecer e o atendimento. A senha local das quatro contas é `CityparkTeste2026!`.
3. Na unidade 1401A existe uma proposta de **teste** na versão 3, com parecer antigo na versão 2 e atendimento já concluído. Isso permite verificar que a versão mais recente está pendente de análise. `npm run db:demo-local` pode renovar prazos fictícios, mas não apaga propostas ou escolhas.

## Limites e próximo passo

- Ainda não há aviso externo à equipe, aprovação final, preços oficiais, renders oficiais nem catálogo real. O parecer mostrado é apenas técnico. A mensagem de envio aparece dentro da interface; a arquiteta consulta sua unidade no portal.
- Substituir o catálogo e as plantas `DEMO-*` por dados aprovados da equipe, estabelecer prazos reais por unidade e decidir o canal de aviso. Antes de uso real, definir quando a proposta deixa de aceitar edições e o fluxo de aprovação final.
- Os 13 testes JavaScript existentes cobrem o protótipo anterior; a interface nova foi verificada manualmente com o Supabase local e pelos testes de banco, mas ainda carece de testes automatizados de navegação.

**Fim do checkpoint.**

---

# 41. Restauração da interface aprovada — 06/10/2026

- A pedido do Vini, a interface principal aprovada foi restaurada: navegação lateral escura, prévias de ambientes, cartões de escolhas, resumo lateral e tela original de seleção da unidade. `src/main.js` voltou a montar `app.js`; o painel novo foi removido.
- `src/legacy-adapter.js` liga essa interface ao modelo novo do Supabase. “Salvar progresso” grava pelos módulos com `save_unit_module_choices`, respeitando planta base, disponibilidade por unidade, prazo e revisão. As opções do protótipo são mapeadas explicitamente para o catálogo `DEMO-*` local.
- Rascunhos legados continuam legíveis como ponto de partida quando um módulo ainda não tem escolhas no modelo novo. Uma gravação pelo botão antigo passa a persistir essas escolhas no modelo por módulos; dados já salvos no modelo novo prevalecem.
- O modal existente “Revisar escolhas” concentra envio da proposta, edição posterior e parecer da arquiteta. “Precisa de ajuda?” abre o atendimento sem alterar a estrutura da tela principal. O layout antigo continua mostrando valores fictícios identificados como tal.
- Rodamão e Serviço foram adicionados ao seed fictício de Bancadas para que todas as opções da interface anterior sejam graváveis no modelo novo. A unidade 1210A foi usada para validar o primeiro envio e está na versão 1; 1209A continua sem proposta enviada. A 1401A está na versão 5 da mesma proposta, com parecer técnico fictício registrado pela interface restaurada.
- Verificados no navegador: visual original, opção indisponível por planta, salvamento, versão posterior da mesma proposta, primeiro envio, pedido de ajuda, bloqueio inicial da edição após envio e parecer da arquiteta. `npm run build`, `npm test` (13 testes) e `npm run test:db-local` passaram.
- A conta fictícia `cliente.b@example.test` foi incluída no seed para testar 1210A. As contas de teste usam a senha local `CityparkTeste2026!`. Nesta sessão, o Vite está em `http://127.0.0.1:5175/exclusive/`; em outra inicialização, use a porta mostrada por `npm run dev`.
- As plantas, prazos, opções e preços usados nesse teste são fictícios. O catálogo visual aprovado está mapeado aos códigos de demonstração; quando chegarem os dados oficiais, será preciso conferir as correspondências de cada opção e seus renders sem redesenhar a interface.

**Fim do checkpoint.**


---

# 42. Ciclos de proposta e limite de alterações — 07/10/2026

> Registro histórico. A validação no banco e no navegador foi concluída em 19/10/2026; consultar a seção 44.

## REGRA DECIDIDA E IMPLEMENTAÇÃO PREPARADA

- Regra definida por Vini: cada ciclo de proposta permite **1 envio inicial + até 3 alterações reenviadas**, totalizando no máximo **4 versões submetidas**.
- O botão **Salvar progresso** não consome uma alteração. As escolhas salvas depois de um envio ficam como rascunho até o cliente reenviar explicitamente a proposta.
- Ao chegar à versão submetida 4/4, o ciclo fica congelado para cliente e arquiteta até o parecer; admin permanece como exceção operacional explícita. Isso evita alterações não reenviáveis depois do limite. O bloqueio foi colocado também no banco, não apenas na interface.
- A arquiteta só pode registrar parecer sobre a versão submetida mais recente. Se o cliente salvou mudanças e ainda não as reenviou, o parecer é bloqueado para evitar análise de uma proposta desatualizada.
- O parecer técnico encerra o ciclo atual. Depois disso, owner/co_owner podem iniciar uma **nova proposta**, que começa novamente em 1/4 e recebe o mesmo limite de três alterações.
- Ciclos e versões anteriores permanecem armazenados para histórico e auditoria.

## Alterações preparadas no repositório

- Nova migration `20261007000100_proposal_cycles_and_edit_limit.sql`: adiciona `cycle_number`, estado do ciclo e data do parecer em `unit_proposals`; permite vários ciclos históricos por unidade, mantendo somente um aberto; remove o trigger que criava versões a cada salvamento; redefine `submit_unit_proposal` e `review_unit_proposal`; adiciona proteção do limite no banco.
- `src/legacy-adapter.js`: passa a carregar o ciclo atual, detectar alterações ainda não reenviadas, exibir limite restante e tratar os novos erros do banco.
- `app.js`: mostra `Proposta N · envio X/4`, oferece reenvio explícito, informa o limite atingido e libera “nova proposta” depois do parecer.
- `scripts/test-unit-proposals-local.sql`: atualizado para validar que salvar não consome versão, owner/co_owner podem reenviar, o quarto envio bloqueia novas alterações, parecer encerra o ciclo e o envio seguinte cria ciclo 2.
- `docs/plano-fluxo-propostas.md` e `docs/modelo-alvo-banco.md` atualizados com a nova regra.

## Validação desta alteração

- `npm test` passou com os 13 testes JavaScript existentes.
- `node --check app.js` e `node --check src/legacy-adapter.js` passaram.
- Nesta execução isolada não foi possível iniciar o Supabase/Docker local nem concluir o build do Vite porque os binários nativos incluídos no `node_modules` do arquivo recebido são do ambiente original. Portanto, a migration nova e o teste SQL ainda precisam ser aplicados/executados no ambiente local do projeto antes de considerar esta etapa **TESTADA NO BANCO**.

## Próximo passo imediato

No computador de desenvolvimento com Docker Desktop e Supabase local ativos: aplicar a migration nova, executar `npm run test:db-local`, abrir a interface e testar manualmente o ciclo completo 1/4 → 2/4 → 3/4 → 4/4 → parecer → nova proposta 1/4. Somente depois atualizar este checkpoint para **IMPLEMENTADO E TESTADO NO BANCO LOCAL**.

**Fim do checkpoint.**

---

# 43. Próximos passos e orientação de retomada — 19/10/2026

## Estado conferido nesta sessão

- Login, vínculos cliente/unidade, escolhas por módulo, prazos, autorização e atendimento da arquiteta, envio e parecer técnico possuem implementação local. As telas principais aprovadas devem ser preservadas; conectar funções aos controles existentes sem redesenhar o configurador.
- O ponto de entrada atual é `src/main.js`, que monta `app.js` e utiliza `src/configurator-adapter.js`. O antigo `src/legacy-adapter.js` está removido na árvore de trabalho atual. O adaptador atual usa o modelo por módulos e ainda mapeia opções aos códigos `DEMO-*`.
- Existem arquivos das migrations `20261007000100_proposal_cycles_and_edit_limit.sql` e `20261007194940_fix_proposal_version_constraint.sql`. A presença dos arquivos não comprova sua aplicação no banco. A última confirmação documental da aplicação local é anterior a essas duas migrations.
- Em 19/10/2026, `npm test` passou com **17 testes JavaScript** e `npm run build` concluiu. Isso atualiza a limitação de build descrita na seção 42. Não foram executados testes SQL nem navegação nesta sessão; o ciclo completo ainda precisa de confirmação no banco local.
- Há alterações locais não commitadas, incluindo troca do adaptador, ajustes em `app.js` e teste de proposta. `scripts/seed-staff-local.mjs` aparece removido, embora guias antigos ainda o indiquem. Conferir essas diferenças antes de usar instruções antigas; preservar o trabalho existente.
- Os registros anteriores sobre portas, versões de propostas e dados das unidades representam o instante de cada teste. Consultar o estado atual ao retomar. Dados oficiais, implantação compartilhada e aprovação final continuam pendentes.

## Próximo passo: validar os ciclos de proposta no ambiente local

**Executar somente na próxima sessão de trabalho. Nesta atualização, Vini solicitou apenas registrar a continuidade e encerrar.**

1. Ler esta seção, a seção 42 e as alterações atuais em `app.js`, `src/main.js`, `src/configurator-adapter.js` e `tests/proposal-workflow.test.cjs`. Conferir `git status` e eventuais instruções do repositório.
2. Conferir Docker/Supabase local e comparar o histórico aplicado com os arquivos de migrations. Se as duas migrations de 07/10 estiverem pendentes, revisá-las e aplicar somente as pendentes com `npx supabase migration up --local`. Não reaplicar versões já registradas nem executar reset para contornar diferenças.
3. Executar `npm run test:db-local`. Corrigir falhas concretas, preservando os dados existentes. Testar salvamento sem consumir envio, reenvio por owner/co_owner, concorrência, bloqueio no quarto envio, prazo por módulo, isolamento de unidades e parecer sobre a versão corrente.
4. Abrir a interface com `npm run dev`, usando a porta informada pelo Vite. Com dados fictícios, demonstrar `1/4 → salvar rascunho sem aumentar a contagem → reenviar 2/4 → 3/4 → 4/4 → bloqueio → parecer → novo ciclo 1/4`. Conferir também que o parecer falha quando há alterações salvas ainda não reenviadas e que os ciclos anteriores permanecem no histórico.
5. Confirmar o funcionamento da interface com o adaptador atual e preservar o layout aprovado. Registrar migrations realmente aplicadas, testes executados e limitações. Só então marcar os ciclos como **IMPLEMENTADOS E TESTADOS NO BANCO LOCAL**.

## Ordem das entregas seguintes

1. **Consolidar a base atual:** concluir a validação acima, revisar as alterações locais e atualizar instruções, scripts e documentação que ainda descrevem estados antigos.
2. **Administração e calendário:** implementar a operação administrativa de clientes/unidades, atribuição de plantas e arquitetas, catálogo e prazos. Evoluir janelas existentes para planejamento, publicação e histórico de alterações por módulo/unidade ou lote.
3. **Catálogo oficial:** receber da equipe CityPark/Allef as plantas base, atribuições por unidade, opções e compatibilidades, renders e quantitativos. Conferir a diferença de descrição da opção com ilha antes de oficializar nomes. Substituir o mapeamento `DEMO-*` por correspondências aprovadas sem alterar a interface principal.
4. **Orçamento e fechamento:** definir preços e vigências, calcular no servidor, preservar o orçamento apresentado e implementar confirmação do cliente/aprovação final após o parecer técnico. Os valores atuais do frontend são fictícios.
5. **Comunicação:** definir destinatários e canais e implementar avisos de envio, reenvio, pedido de ajuda e parecer. Atualmente há mensagens e registros dentro do sistema; envio externo ainda não está concluído.
6. **Homologação e ativação:** preparar Supabase exclusivo compartilhado, hospedagem, configuração de Auth e SMTP real; validar com contas controladas, importar compradores reais após revisão e realizar a jornada completa antes da liberação.
7. **Evolução visual e operacional:** completar renders, módulos ainda indisponíveis e consulta do histórico conforme os dados aprovados. Ampliar testes de navegação e operação sem redesenhar as telas já aprovadas.

## Instrução para a próxima sessão

> Retome pela seção 43 do EXCLUSIVE_STATUS.md. Comece conferindo o estado das migrations e validando os ciclos de proposta no Supabase local. Preserve a interface aprovada, as alterações existentes e o uso de dados fictícios. Não trate o código preparado como validado no banco sem evidência. Conclua essa validação antes de iniciar as entregas seguintes.

**Fim do checkpoint — próxima execução adiada a pedido de Vini.**

---

# 44. Ciclos validados no banco e na interface — 19/10/2026

## IMPLEMENTADO E TESTADO NO BANCO LOCAL E NO NAVEGADOR

- Vini retomou o trabalho com Docker Desktop e Supabase local iniciados. Conferido o histórico: **20 migrations aplicadas**, incluindo `20261007000100_proposal_cycles_and_edit_limit.sql` e `20261007194940_fix_proposal_version_constraint.sql`. Nenhuma migration precisou ser aplicada ou reaplicada nesta retomada.
- `npm run test:db-local` passou para escolhas por módulo, pedidos de ajuda e ciclos de proposta. As fixtures SQL foram revertidas. Os testes cobrem também vínculos, isolamento de unidades, revisão desatualizada, compatibilidade, prazo de Planta e independência dos módulos.
- Criado `scripts/test-proposal-ui-local.mjs`, executável por `npm run test:proposal-ui-local`: teste de navegação real em Edge headless contra a aplicação e o Supabase locais, com verificação adicional dos registros no PostgreSQL.
- Jornada completa aprovada: salvar antes de enviar não cria proposta; envio inicial 1/4; salvar alterações mantém 1/4; tentativa de parecer com rascunho ainda não reenviado é rejeitada; reenvio 2/4; coproprietário reenvia a mesma proposta em 3/4; quarto envio bloqueia edição de cliente e arquiteta; parecer encerra o ciclo; cliente inicia ciclo 2 em 1/4. Os dois ciclos e as cinco versões estavam preservados antes da limpeza das fixtures.
- O teste usa os clientes fictícios da 1401A, uma unidade temporária com catálogo `DEMO-*` e uma conta temporária de arquiteta. A senha atual da arquiteta fictícia existente difere da senha histórica do seed; ela não foi alterada. A conta temporária permite testar sem depender dessa senha.
- Após os testes, confirmado: **9 unidades originais, 0 unidades E2E e 0 contas temporárias de arquiteta**. Somente registros criados pelo próprio teste foram removidos.
- Corrigidas no adaptador as mensagens de erro de alterações ainda não reenviadas, reenvio sem mudanças e limite atingido. O parecer agora apresenta essas mensagens em português. As telas principais e o CSS aprovado não foram alterados.
- Verificação final: **17 testes JavaScript passaram**, build de produção concluído e `git diff --check` sem erros de whitespace. Captura do layout aprovado em `outputs/qa/proposal-cycle-local.png` (artefato local ignorado pelo Git).

## Repetir a validação quando houver alteração no fluxo

1. Manter Docker/Supabase local e a aplicação Vite iniciados. Os testes não executam seed nem reset do banco.
2. Executar `npm run test:db-local`.
3. Para a jornada de navegador, disponibilizar o pacote Playwright no ambiente ou informar seu diretório absoluto em `CITYPARK_PLAYWRIGHT_PATH`, e executar `npm run test:proposal-ui-local`. O teste usa Edge instalado; `CITYPARK_BROWSER_CHANNEL` permite escolher outro canal compatível. `CITYPARK_UI_URL` permite informar a porta local mostrada pelo Vite. URLs remotas são rejeitadas.
4. As contas fictícias `cliente.d@example.test` e `cliente.e@example.test` precisam estar disponíveis com a senha local de demonstração, ou informar a senha dessas contas em `CITYPARK_DEMO_PASSWORD`. O teste cria e remove sua própria arquiteta e unidade; preserva as unidades de demonstração existentes.

## Próximo passo de desenvolvimento

**A validação dos ciclos está concluída. Retomar pela consolidação da base antes do painel administrativo.**

1. Revisar as diferenças locais existentes e atualizar README/guias para o adaptador atual e os comandos que realmente existem. Conferir especialmente a remoção prévia de `scripts/seed-staff-local.mjs` e as referências antigas a esse comando. Não restaurar ou apagar trabalho anterior por suposição.
2. Documentar o procedimento atual de instalação, criação dos dados fictícios e testes. Conferir que os scripts de acesso e equipe usam as regras atuais por módulo e autorização, pois alguns foram escritos para RPCs legados já revogados.
3. Depois dessa consolidação, iniciar administração e calendário conforme a ordem da seção 43: atribuições de plantas e arquitetas, prazos por módulo/unidade, publicação e histórico. Preservar o layout aprovado; definir os controles administrativos necessários conforme o fluxo real.
4. Dados oficiais, orçamento no servidor, confirmação final, notificações externas e homologação permanecem nas etapas posteriores. Não apresentar o parecer técnico como aprovação final nem os valores fictícios como orçamento oficial.

**Fim do checkpoint — ciclos concluídos; próxima entrega: consolidar scripts e documentação.**

---

# 45. Seleção de apartamentos do cliente — 20/10/2026

## Orientação vigente do Vini

- O foco passou a ser a experiência visual e interativa, começando pelo cliente. Os wireframes `escolher-apartamento-1.png` e `escolher-apartamento-2.png` são a base oficial da composição da seleção de unidades, preservando a identidade visual do Exclusive em cores e fontes.
- A autorização desta etapa abrange essa tela e a regra do prazo final. A edição do prazo pelo painel administrativo foi explicitamente adiada. Não iniciar esse painel nesta entrega.

## Implementado

- Título e cartões centralizados. Uma unidade ocupa um cartão central; várias unidades ficam em duas colunas no desktop, seguindo para as linhas seguintes. No celular, ficam em uma coluna sem rolagem horizontal.
- Destaque do código da unidade, com separação visual da torre (ex.: `1209 A`); abaixo, torre, andar, tipologia e área em m² em texto mais discreto. Imagem de localização preservada, sem distorção.
- O cartão é um `article`; imagem, texto e bordas não abrem a unidade. Somente o botão “Acessar unidade” faz isso, inclusive pelo teclado. O atalho “Continuar unidade” foi retirado da seleção do cliente para respeitar essa regra. A seleção da equipe mantém seu fluxo anterior.
- Prazo final no canto inferior direito do cartão, com data/hora em America/Sao_Paulo. Unidade vencida continua acessível para consulta e é identificada como tal. “Voltar ao login” encerra a sessão.
- Migration `20261020000100_unit_area_and_final_deadline.sql` aplicada ao Supabase local: **21 migrations aplicadas**. Adiciona `units.area_m2` (positiva ou nula) e `units.customization_closes_at` (limite exclusivo). Clientes não têm permissão de alterar esses campos.
- O prazo final bloqueia escolhas de todos os módulos e envio/reenvio de proposta no servidor, usando `clock_timestamp()` e rollback integral do RPC. Aplica-se também à arquiteta que edita pela unidade. O parecer sobre uma proposta já enviada continua permitido depois do vencimento.
- O prazo geral convive com as janelas por módulo: vale o limite que encerrar primeiro. Campo geral nulo não apaga nem contorna os prazos de módulos existentes. O navegador bloqueia os controles automaticamente quando o prazo final vence com a sessão aberta.
- Áreas e prazos não foram inferidos do wireframe nem dos códigos das unidades. Campos não cadastrados aparecem como “Área a confirmar” e “A definir”. O seed local foi preparado para oferecer metadados explicitamente fictícios (área de demonstração da 1209A e prazo geral de 30 dias), mas não foi reexecutado nesta entrega para evitar sobrescrever senhas e prazos anteriores.

## Verificação concluída

- `npm test`: **17 testes passaram**. `npm run build` concluído.
- `npm run test:db-local`: **quatro grupos passaram**, incluindo o novo `scripts/test-unit-deadline-local.sql`. Verificadas rejeição de alterações em dois módulos, bloqueio de envio inicial e reenvio vencidos, leitura após vencimento, rejeição de mudança de prazo pelo cliente, atuação da arquiteta, área inválida e ausência de gravação parcial após falhas. Fixtures revertidas.
- `npm run test:apartments-ui-local`: jornada real de navegador aprovada com uma, quatro e cinco unidades; clique fora do botão; acesso pelo teclado; dados ausentes; alinhamento do cabeçalho e uma coluna no celular; unidade vencida em consulta; bloqueio de Planta/Bancadas/salvamento/envio; vencimento durante sessão; logout. O script cria e remove seu próprio cliente e cinco unidades temporárias.
- `npm run test:proposal-ui-local`: ciclo completo 1/4 até 4/4, parecer e novo ciclo 1/4 passou novamente com a nova tela e migration.
- Capturas conferidas em `outputs/qa/apartment-selection-single.png`, `apartment-selection-grid.png` e `apartment-selection-mobile.png`. Artefatos locais ignorados pelo Git.
- Para os testes de navegador, usar os requisitos/variáveis da seção 44 (`CITYPARK_PLAYWRIGHT_PATH`, `CITYPARK_UI_URL` etc.). Nesta execução, o servidor foi aberto em `http://127.0.0.1:5174/exclusive/`; em outras inicializações, usar a porta informada pelo Vite.

## Continuidade

- Continuar os ajustes da experiência do cliente conforme os próximos wireframes/orientações do Vini. A tela principal de customização permanece com o layout anterior nesta etapa, recebendo apenas os bloqueios necessários do prazo final.
- Cadastrar área e prazo final reais quando a equipe os fornecer. Criar posteriormente o fluxo administrativo para edição do prazo, com autorização e histórico; a interface administrativa ainda não foi implementada.
- Os trabalhos anteriores de consolidação de scripts/documentação, calendário, catálogo oficial, orçamento, comunicação e homologação permanecem no roteiro, respeitando a prioridade atual da experiência do cliente.

**Fim do checkpoint — seleção de apartamentos e prazo final implementados e testados localmente.**

---

# 46. Seleção de unidades compartilhada — 20/10/2026

## Implementado e testado

- Por orientação do Vini, o formato da seção 45 passa a ser o padrão para **Cliente, Arquiteta e Admin**. A descrição anterior de que a seleção da equipe manteria o formato antigo foi superada por esta decisão.
- Os três perfis usam a mesma implementação de cartões: unidade única centralizada, duas colunas no desktop, uma no celular, metadados discretos e prazo final no canto inferior direito. Apenas o botão “Acessar unidade” abre o configurador; o antigo atalho de continuar unidade também foi retirado da seleção da equipe.
- Para a equipe, o título é “Selecione a unidade para atendimento”, com identificação de Arquiteta ou Administrador acima. O cabeçalho da seleção usa “Voltar ao login”; dentro da unidade, a identificação de atendimento e os controles próprios da equipe permanecem.
- As permissões existentes foram preservadas: Arquiteta vê somente unidades atribuídas e autorizadas, Admin vê unidades ativas e nenhum deles ganha o envio de proposta reservado ao cliente. O painel administrativo de edição de prazos continua pendente.
- `npm test`: **17 testes passaram**. `npm run build` concluído. `npm run test:apartments-ui-local` passou para os três perfis, incluindo uma e várias unidades, autorização da Arquiteta, alcance do Admin, cliques fora do botão, entrada/saída, desktop e celular. As verificações anteriores do cliente e do prazo final continuam passando.
- Capturas conferidas em `outputs/qa/apartment-selection-architect.png` e `apartment-selection-admin-mobile.png`; também foram geradas as versões de celular da Arquiteta e desktop do Admin. O teste cria e remove suas próprias contas e unidades, preservando os registros existentes.

## Continuidade

- Usar esta seleção compartilhada nas próximas evoluções, preservando as permissões e a identidade visual de cada fluxo. Prosseguir com os ajustes de experiência conforme as próximas orientações/wireframes do Vini.
- As pendências de dados oficiais, painel administrativo, consolidação da documentação e demais entregas das seções 43–45 permanecem no roteiro.

**Fim do checkpoint — padrão de seleção aplicado aos três perfis e validado localmente.**

---

# 47. Ícones oficiais da sidebar — 20/10/2026

- Arquivos enviados pelo Vini movidos de `ícones side bar` para `assets/icons/sidebar`. A pasta de origem foi excluída após ficar vazia; as versões pretas foram preservadas como recursos, sem uso na interface.
- Sidebar compartilhada pelos três perfis usa os PNGs **brancos** de Planta, Piso, Bancadas, Louças e Metais, associados pelos nomes dos arquivos. Tamanho de 24 × 24 px com proporção preservada. Estados ativo e indisponível e comportamento dos módulos permanecem.
- Extras mantém o símbolo `+`, pois não foi fornecido um arquivo para esse item. Ícones decorativos não duplicam o nome acessível dos botões.
- Build concluído com os arquivos incluídos em `dist/assets/icons/sidebar`. Verificação no navegador confirmou os cinco PNGs carregados e navegação Planta/Bancadas; captura em `outputs/qa/sidebar-white-icons.png`. Nenhuma alteração no banco.
- Continuidade: manter a seleção compartilhada da seção 46 e seguir as próximas orientações de experiência visual do Vini.

---

# 48. Visualização proporcional e sidebar recolhível — 21/10/2026

## Orientação e implementação

- Os dois novos wireframes de baixa fidelidade do Vini orientam as proporções da visualização e o recolhimento da sidebar; a identidade visual do Exclusive foi preservada. O foco desta entrega foi a sidebar e o espaço de visualização, compartilhados por Cliente, Arquiteta e Admin.
- Controle no canto superior direito do menu permite recolher/expandir. Recolhida, a sidebar tem 80 px, mostra os ícones brancos e mantém os módulos navegáveis, com nomes acessíveis e dicas ao passar o mouse. A ajuda continua acessível pelo símbolo `?`. Expandida, reapresenta textos e indicadores de disponibilidade.
- Ao entrar em uma unidade, a sidebar começa **expandida**. A preferência permanece ao navegar entre módulos/grupos da mesma unidade; não integra os dados de personalização salvos. Trocar/abrir outra unidade restaura o padrão expandido. O controle funciona pelo teclado e recupera o foco após a atualização da tela.
- A grade redistribui a largura da área central conforme o estado do menu. A prévia reserva pelo menos 260 px de altura, com painéis de escolhas proporcionais à altura disponível. Em espaços baixos, a página/área central permite rolagem para manter os controles alcançáveis.
- Corrigida a prévia da Área social: a imagem composta ocupa uma área delimitada, com `object-fit: contain` em todas as camadas e caixas coincidentes. A combinação antiga de altura pela largura, legendas e rolagem interna cortava a perspectiva. Agora a composição inteira cabe no espaço, com margens quando necessário, sem achatamento e sem rolagem dentro da imagem. A cozinha usa o mesmo princípio de enquadramento proporcional.
- O zoom nativo do navegador é respeitado: o layout se adapta ao espaço disponível. Não há bloqueio de zoom nem escala inversa. Em telas estreitas, o resumo fica abaixo e a sidebar continua disponível, em vez de desaparecer.
- Não houve mudança de banco, catálogo, preços, permissões ou regras de proposta/prazo nesta entrega.

## Verificação concluída

- `npm test`: **17 testes passaram**. `npm run build` concluído. `git diff --check` sem erros de whitespace.
- Novo `npm run test:customizer-layout-local`: usa o configurador e CSS reais com dados em memória, sem gravar no banco. Valida expansão/recolhimento, foco/teclado, navegação por ícones, preservação de escolhas, conteúdo do salvamento sem estado da sidebar, ajuda, revisão, módulos indisponíveis e retorno ao padrão ao abrir outra unidade.
- Imagens e camadas carregadas, proporcionais e inteiras nos dois estados do menu em **1437×678, 1920×1080, 1366×650, 1093×520, 911×433, 683×325 e 390×844**. As dimensões intermediárias simulam o espaço CSS disponível ao aumentar o zoom em uma tela 1366×650; não são uma alteração do zoom nativo via automação. O botão “Continuar para materiais” também foi acionado nessas dimensões. Verificados os três perfis.
- `npm run test:apartments-ui-local` passou novamente: seleção dos três perfis, permissões, celular, consulta de unidade vencida e bloqueio automático no vencimento.
- `npm run test:proposal-ui-local` passou: envio 1/4, salvar sem consumir reenvio, rascunho não reenviado impedindo parecer, coproprietário reenviando a mesma proposta em 3/4, bloqueio em 4/4, parecer e novo ciclo 1/4, preservando cinco versões.
- O teste de propostas inicialmente encontrou credenciais de demonstração diferentes das esperadas. O script foi ajustado para criar e remover **cliente, coproprietário e arquiteta temporários**, eliminando a dependência das senhas de `cliente.d/e`. As credenciais existentes não foram alteradas. As instruções históricas da seção 44 sobre senha de demonstração para esse teste foram superadas por esta atualização; ainda é necessário o catálogo fictício da 1401A como origem da planta.
- Capturas em `outputs/qa/customizer-expanded.png`, `customizer-collapsed.png`, `customizer-materials.png`, `customizer-125.png` e `customizer-mobile.png`. Para repetir, usar as variáveis de Playwright/URL/canal descritas nas seções anteriores. Servidor desta sessão: `http://127.0.0.1:5174/exclusive/`.

## Próximo passo

- Vini pode conferir visualmente a customização com a sidebar expandida e recolhida. Continuar os ajustes conforme suas próximas orientações/wireframes, mantendo os fluxos e as permissões atuais.
- Painel administrativo, dados oficiais e demais entregas das seções anteriores continuam pendentes; não foram iniciados nesta mudança visual.

**Fim do checkpoint — visualização proporcional e sidebar recolhível implementadas e validadas localmente.**

### Ajuste complementar da sidebar — 21/10/2026

- Título atualizado para “Personalize seu apartamento”. Controle de recolher/expandir com o desenho anterior de painel e seta, traços arredondados e sem borda externa no botão. Vini corrigiu a remoção da moldura que faz parte do próprio desenho: essa forma foi restaurada. Mantido o alinhamento ao centro do título na sidebar expandida e à coluna dos demais ícones quando recolhida.
- Build concluído e alinhamentos conferidos no navegador em 1366 px e 390 px, com recolhimento, expansão e navegação preservados. Capturas em `outputs/qa/sidebar-title-expanded.png` e `sidebar-title-collapsed.png`.

---

# 49. Cabeçalho compacto, imagem preenchida e cards de Planta — 21/10/2026

- Removido “Etapa 2”. O cabeçalho da Planta foi compactado; título e prazo ficam alinhados pelo centro horizontalmente, com quebra responsiva quando a largura não comporta ambos.
- A perspectiva social agora ocupa toda a largura do campo, cuja altura segue a proporção real da imagem (5000:1770). Base e sobreposições continuam coincidentes, inteiras e sem distorção; removidas as margens laterais internas provocadas pela altura fixa anterior. As legendas e avisos de prévia parcial foram preservados.
- A altura mínima fixa de 260 px da prévia de Planta descrita na seção 48 foi substituída pelo dimensionamento proporcional à largura. Em telas baixas, a área principal pode rolar para acomodar a perspectiva e as opções; a seção dos cards não possui rolagem vertical própria.
- Removidos “Alterações da Planta”, o rodapé de configuração e o botão “Continuar para materiais”. O título Área social/Suíte Master fica alinhado aos seletores da direita. Bancadas permanece acessível pela sidebar, expandida ou recolhida.
- Cards de Planta têm **176 px de altura e 220 px de largura inicial**. A largura cresce somente se o conteúdo não couber na altura fixa, medido após renderizar e após carregar as fontes. Textos, tags e preços ficam completos; a fileira permite rolagem horizontal quando necessário. No teste com o conteúdo atual, o último card precisou de 226 px de largura. Os cards de materiais não receberam essa regra nova de dimensionamento.
- Validados `npm test` (**17 testes**), `npm run build` e `npm run test:customizer-layout-local` nos três perfis e nas sete dimensões da seção 48. O teste foi atualizado para verificar proporção preenchida, ausência de rolagem vertical nas opções, conteúdo completo e remoção dos controles antigos; a navegação para Bancadas usa a sidebar. Salvamento, ajuda, revisão, preservação das escolhas e expansão/recolhimento continuam passando.
- Conferidos visualmente `outputs/qa/customizer-expanded.png`, `customizer-collapsed.png` e `plant-cards-complete.png`. Nesta execução, o Vite iniciou em `http://127.0.0.1:5176/exclusive/`; usar a porta indicada pelo servidor nas próximas sessões.
- Nenhuma alteração de banco, permissões ou regras de proposta/prazo. Próximo passo: continuar os ajustes visuais conforme as orientações do Vini; demais pendências anteriores mantidas.

---

# 50. Prévias sem textos e sem faixas vazias — 21/10/2026

- Vini corrigiu o resultado da seção 49: a prévia de Planta deve mostrar somente a imagem. Removidos o título/descrição “Área social · Perspectiva...” e o aviso abaixo da perspectiva. A decisão anterior de preservar esses textos foi superada. As pendências reais dos renders continuam existindo; remover o aviso visual não conclui a renderização da ilha ou de outros elementos faltantes.
- Removidos os espaçamentos externos, cantos arredondados e molduras das prévias. A imagem encosta nas quatro extremidades do próprio campo, sem faixas de fundo entre a imagem, o cabeçalho e as opções.
- Cozinha ajustada à proporção nativa de sua base (4000:1894), em vez de um campo de altura fixa que deixava faixas laterais. Planta mantém 5000:1770. Camadas continuam alinhadas e as imagens permanecem completas e proporcionais; não foi usado recorte para preencher. Ferramentas e indicadores sobre a cozinha foram preservados.
- A Suíte Master ainda não tem imagem recebida e mantém o aviso de preparação. As áreas principais acompanham a altura natural das imagens e podem rolar em telas baixas; os controles e as opções continuam acessíveis.
- Passaram os 17 testes JavaScript, build e validação de layout nos três perfis/sete dimensões. O teste agora exige coincidência das quatro bordas da imagem com o campo, proporção correta também na cozinha e ausência dos textos na prévia social. Capturas de Planta e cozinha conferidas em `outputs/qa/customizer-expanded.png` e `customizer-materials.png`.
- Servidor desta execução em `http://127.0.0.1:5177/exclusive/`. Nenhuma alteração de banco ou regras de negócio. Continuidade: seguir as próximas orientações visuais do Vini.

---

# 51. Cards de Planta compactos e independentes — 21/10/2026

- Por nova orientação do Vini, a medida base foi compactada para **220 × 140 px**, substituindo a altura anterior de 176 px. A altura mínima/máxima é fixa; textos não aumentam a altura da fileira nem dos demais cards.
- Cada card cresce somente em largura quando o conteúdo ultrapassa a área interna. O cálculo parte da medida definida no CSS, evitando outra medida base independente no JavaScript. Altura fixa e rolagem somente horizontal da fileira preservadas.
- Adicionado teste de uma descrição artificialmente longa em somente um card: confirmou crescimento horizontal desse card, medidas dos outros três inalteradas, todos com 140 px de altura e conteúdo completo; ao retirar o texto adicional, as medidas originais foram recuperadas.
- Passaram os 17 testes JavaScript, build e teste de layout nos três perfis/sete dimensões. Captura `outputs/qa/customizer-expanded.png` conferida com os cards compactos. Nenhuma alteração nas regras de negócio ou no banco.

---

# 52. Personalização estática, sem rolagem vertical da tela — 21/10/2026

- Vini determinou que a tela de personalização deve ser estática, mantendo o conteúdo acessível. As orientações anteriores de permitir rolagem da página/área principal em telas baixas foram **superadas**.
- Criado contêiner de 100dvh com linhas para o cabeçalho real e o espaço restante. Removidas a altura mínima de 580 px, a altura fixa de 720 px no celular e a rolagem vertical da área principal. A seleção de apartamentos e o login mantêm seu próprio comportamento de rolagem.
- O catálogo reserva sua altura e a imagem se ajusta ao espaço restante **nas duas dimensões**, com sua proporção nativa e sem recortes/distorção. Quando as proporções do espaço e da imagem divergem, a imagem pode não ocupar toda a largura; a decisão desta etapa prioriza a tela fixa e a imagem inteira. Não voltar a forçar altura natural pela largura se isso empurrar opções para fora da tela.
- Cards de Planta mantêm base de 220 × 140 px em altura normal. Em janelas com até 560 px de altura, usam 108 px fixos; o conteúdo longo continua expandindo só o próprio card horizontalmente. Cards de materiais foram dimensionados em 170 px (140 px em janelas baixas), preservando miniatura, texto e preço. A medição individual agora atende ambos os módulos e é atualizada ao redimensionar a tela e ao carregar fontes.
- Em larguras de até 850 px, o resumo deixa de ocupar uma segunda seção abaixo da tela; fica acessível pelo botão **Resumo** do cabeçalho, que abre a revisão existente com seus controles e regras por perfil. No desktop, o painel direito continua disponível com rolagem interna. Modais conservam rolagem própria para textos longos; opções conservam navegação horizontal.
- Sidebar e cabeçalho recebem espaçamento compacto em janelas baixas. No celular, os controles do cabeçalho ficam abaixo da marca, sem esconder botões. Navegação por ícones, ajuda e troca de unidade preservadas.
- Passaram os 17 testes JavaScript, build e `test:customizer-layout-local` nos três perfis e sete dimensões (incluindo 683×325 e 390×844). O teste verifica ausência de overflow vertical em html/body/app/tela/grade/área principal, imagem inteira, preços e botões dentro da altura visível, conteúdo dos cards completo, roda do mouse sem deslocar a área principal e abertura do Resumo compacto.
- `test:proposal-ui-local` passou novamente: envio inicial, reenvio, coproprietário, bloqueio em 4/4, parecer e novo ciclo com histórico preservado. Contas e unidade temporárias removidas pelo script; credenciais existentes preservadas. Sem mudança de banco ou regras de negócio.
- Capturas atualizadas em `outputs/qa/customizer-expanded.png`, `customizer-collapsed.png`, `customizer-materials.png`, `customizer-125.png` e `customizer-mobile.png`. Build e `git diff --check` concluídos. Continuidade: conferir os ajustes visuais com Vini e seguir suas próximas orientações.

---

# 53. Imagem acompanha o recolhimento da sidebar — 21/10/2026

- Corrigida a limitação em que a área central aumentava de largura, mas a imagem continuava limitada pela altura restante. Com o menu recolhido, cabeçalho e espaçamentos das opções ficam mais compactos, liberando altura para ampliar a imagem proporcionalmente.
- Na referência de 1366×650, a perspectiva social cresce mais de 100 px e ocupa a largura disponível após recolher. A cozinha também aumenta de tamanho. Alturas dos cards, conteúdo completo, proporção das imagens e ausência de rolagem vertical da tela foram preservados.
- O teste de layout agora compara o tamanho real das imagens nos dois estados da sidebar, além da largura da área central. Passou nos três perfis e nas sete dimensões anteriores; build e `git diff --check` concluídos. Captura `outputs/qa/customizer-collapsed.png` conferida.
- Em espaços muito baixos, o enquadramento continua respeitando a altura disponível para evitar cortes; não substituir por recorte ou distorção. Nenhuma alteração de banco ou fluxo de negócio.

---

# 54. Bancadas com layout compacto e miniaturas visíveis — 21/10/2026

- Aplicado o cabeçalho compacto às opções de Bancadas: removidos o texto “Bancadas · Cozinha/Serviço” e a frase explicativa abaixo do título; título e seletores Configuração/Granito/Rodamão/Serviço ficam alinhados.
- Identificada a causa das miniaturas quase vazias: os PNGs são camadas da perspectiva completa, com grande área transparente ao redor da peça. Adicionado enquadramento SVG por item, mostrando todos os pixels visíveis e uma margem transparente. Os arquivos originais e seu uso na perspectiva principal não foram modificados.
- Configuração, Granito, Rodamão e Serviço têm imagens nos dois cards. Rodamão padrão e 60 cm agora usam os renders correspondentes disponíveis, substituindo o símbolo genérico.
- Cards visuais têm base de 220 × 190 px, com área de imagem de 64 px. A altura é fixa e descrições maiores ampliam apenas a largura individual. Em janelas baixas, mantêm 140 px e miniatura de 36 px, com espaçamentos de texto compactos. A altura dos cards de Planta permanece a da seção 51/52.
- Passaram os 17 testes JavaScript e build. O teste de layout passou nos três perfis e sete dimensões, agora percorrendo os quatro grupos de Bancadas nos dois estados da sidebar. Também confere que o enquadramento de cada miniatura contém todos os pixels não transparentes da peça, sem ocultar partes, e que o texto dos cards não ultrapassa sua área.
- Capturas conferidas: `outputs/qa/countertops-counter.png`, `countertops-stone.png`, `countertops-rodamao.png` e `countertops-service.png`. Tela estática, imagens proporcionais, seleção, salvamento, ajuda e revisão preservados. Sem alteração de banco ou regras de negócio.


---

# 55. Requisitos de sessão, acesso e gestão — 27/10/2026

- Implementação vigente e instruções: [implementacao-requisitos-2026-10-27.md](implementacao-requisitos-2026-10-27.md). As decisões desta seção substituem as regras antigas de rascunho, coproprietário, autorização por unidade e proposta/parecer.
- Migrations locais aplicadas: 20261027000100 (sessão/acesso/gestão), 20261027000200 (cadastro e lembretes) e 20261027000300 (primeiro acesso e encerramento dos RPCs legados). Cópia recuperável anterior em outputs/backups, ignorada pelo Git. Schema sem dados e lista de migrations atualizados.
- Escolhas só existem durante a sessão e iniciam nos padrões do banco; sair descarta. Arquiteta/Admin consultam todas as unidades numa tabela, inclusive inativas. Cliente acessa apenas unidades ativas da sua conta proprietária. Vínculos de coproprietário ficam inativos e históricos preservados.
- Admin cadastra clientes pela Edge Function admin-customer e gerencia vínculo/prazos. Sem prazo, edição liberada; vencido exige reabertura administrativa. Status ativo/inativo pode ser alterado pela equipe; reativação de concluída exige Admin e volta a Pendente.
- Compatibilidade tem exclusões e dependências entre módulos, validadas no navegador e no banco, sem salvar escolhas. Histórico identifica primeiro acesso, ator, unidade, horário e alterações administrativas.
- Lembretes têm fila e Edge Function com transporte HTTP configurável. Provedor/SMTP ainda indefinido: não há agendamento nem disparo externo ativo. Teste usa receptor local simulado.
- Admin inicial exclusive@planoaengenharia.com.br provisionado apenas no Supabase local, por autorização explícita, sem e-mail enviado.
- Validações: 17 testes JavaScript, build, dois conjuntos SQL com rollback, jornada real de cliente/arquiteta/Admin e cadastro pela função local, sete dimensões de layout e teste do worker com deduplicação passaram. Capturas em outputs/qa/requirements-*.png.
- Contrato/PDF e finalização após geração foram adiados pelo responsável. O configurador não gera nem envia contrato nesta etapa. Dados oficiais de catálogo, preços, quantitativos e dependências continuam pendentes; apenas demonstração foi cadastrada.


---

# 56. Unidades inativas na seleção do cliente — 27/10/2026

- Acesso em preparação permanece para contas sem vínculo ativo de proprietário. Uma unidade inativa com vínculo válido continua na seleção, em tons de cinza. Clicar em qualquer parte do card abre um aviso de inatividade ou personalização concluída; Enter/Espaço também abrem, Escape fecha e restaura o foco.
- Migration 20261027000400 adiciona list_customer_unit_cards, que retorna somente metadados dos cards da própria conta. A RLS de units e os RPCs de personalização continuam negando acesso do cliente a unidades inativas. Não foi ampliada a leitura das configurações.
- O bootstrap diferencia ausência de vínculo de unidade inativa. Testados cliente com unidades mistas, somente inativas, unidade concluída e conta nova sem unidades; fluxo original dessa conta foi preservado.
- 18 testes JavaScript e build passaram; teste SQL com rollback e jornada no navegador validaram o bloqueio do configurador e o popup por mouse/teclado em desktop/celular. Capturas em outputs/qa/inactive-*.png. Schema e lista de migrations locais atualizados.


---

# 57. Primeiro acesso e entrega real de e-mail — 27/10/2026

- Corrigido o caso de conta Auth nova, sem confirmação de e-mail: signInWithOtp retornava signup_disabled com cadastro público desabilitado e o erro era ocultado. Agora usa resetPasswordForEmail e verifyOtp do tipo recovery; cadastro público continua bloqueado.
- Modelo recovery.html em português com código de seis dígitos e validade de dez minutos. Erros de envio não são tratados como sucesso. Aviso de caixa local aparece apenas no desenvolvimento quando esse modo é selecionado.
- SMTP local conectado ao Resend com arquivo privado supabase/.env.auth-smtp.local. Configuração versionada contém apenas referências de ambiente. Comandos de Supabase usam wrapper para carregar as credenciais; nenhum serviço remoto foi alterado.
- Responsável confirmou recebimento no Gmail, definição da própria senha e acesso à unidade vinculada. A senha não foi definida pelo agente.
- O remetente de testes onboarding@resend.dev só permite o e-mail da conta Resend. O responsável adiou a verificação de domínio: por enquanto, testar apenas a própria conta. Envio aos demais clientes depende de verificar domínio e trocar remetente.
- 23 testes JavaScript e build passaram. Teste real em Mailpit cobriu UI de cadastro/vínculo, emissão do código, verificação, definição de senha, login posterior, cooldown e rejeição de código reutilizado. Teste recusa SMTP real para evitar enviar dados fictícios externamente.
- Roteiro atual: [validacao-primeiro-acesso-2026-10-27.md](validacao-primeiro-acesso-2026-10-27.md).

---

# 58. Implantação nas contas oficiais — 28/10/2026

- Responsável confirmou que o Exclusive terá contas novas, sem importação do Firebase. Autorizou continuar com o processo recomendado de Supabase Auth e entrega gerenciada, usando contas oficiais do CityPark em lugar das pessoais.
- Preparado [roteiro de configuração oficial](configuracao-oficial-autenticacao.md), com distinção entre conta administrativa dos provedores, remetente verificado e Admin do aplicativo. Endereço oficial responsável ainda aguarda confirmação.
- Consulta pública identificou DNS no Registro.br e registros de e-mail da Locaweb em cityparkmcz.com.br. Isso não confirma uma contratação ativa. Nenhum registro DNS foi alterado.
- Corrigida a inclusão do modelo supabase/.env.auth-smtp.example no Git; credenciais privadas continuam ignoradas. Configuração local de teste preservada até validar a oficial. Nenhum projeto remoto, equipe Resend ou privilégio remoto foi criado nesta etapa.

## Avanço do cadastro oficial

- Responsável confirmou acesso à caixa exclusive@planoaengenharia.com.br e concluiu cadastro/verificação no Resend. Sessão conferida nessa identidade e na equipe planoaengenharia.
- Cadastrado acesso.cityparkmcz.com.br no Resend oficial em São Paulo; registros reais TXT/CNAME documentados no roteiro. Verificação de DNS ainda pendente, recebimento desabilitado, SMTP local preservado e nenhuma chave oficial criada.
- Painel do Registro.br aberto para o responsável entrar na conta que administra cityparkmcz.com.br. Nenhum registro DNS alterado e nenhum Supabase online configurado até aqui.

## Publicação DNS autorizada

- Responsável solicitou confirmação antes de mudanças importantes e autorizou expressamente as três adições apresentadas. Rascunho comparado com a cópia aprovada antes de salvar.
- Zona reaberta após salvamento: 28 registros persistidos, os 25 anteriores preservados e somente TXT DKIM e dois CNAMEs aprovados adicionados. Cópias anterior/posterior guardadas localmente em outputs/backups, fora do Git.
- Os três novos nomes já resolvem publicamente; acionada verificação do domínio no Resend oficial, inicialmente Pending. Cadastro do Supabase aberto com e-mail oficial para conclusão pelo responsável. Nenhuma chave oficial criada, nenhum SMTP substituído e nenhum projeto Supabase online criado nesta etapa.
- Resend confirmou Domain verified às 15h32 de 28/10 (São Paulo), com os três registros Verified e recebimento desabilitado. TXT público confere integralmente com a chave DKIM emitida. Evidência local em outputs/qa/resend-official-domain-verified-20261028.png. Próxima dependência: concluir acesso oficial ao Supabase; depois criar chave oficial e aplicar a integração com autorização para as mudanças importantes.

## Organização Supabase oficial criada

- Responsável autorizou a organização no plano gratuito. Nome CityPark Exclusive preservado conforme formulário na retomada. Organização confirmada como Free, ID paifzhzwppdrfavbxsbi, na conta oficial exclusive@planoaengenharia.com.br.
- Projeto citypark-exclusive preparado na região São Paulo (sa-east-1). Senha do banco e confirmação de criação pendentes do responsável; nenhum projeto foi criado pelo agente. Exposição automática de tabelas desabilitada: conferir grants explícitos antes da implantação.

## Projeto oficial criado e implantação preparada

- Responsável criou citypark-exclusive, ref grfmiuopojbxxbdymqax, na organização oficial CityPark Exclusive. Painel confirmou Healthy e região São Paulo. Consulta de leitura retornou 0 tabelas públicas e 0 usuários Auth.
- Gerador scripts/prepare-official-deployment.mjs produz pacote transacional e manifesto com hashes das 25 migrations; nenhum seed ou conta incluído. Proteções exigem banco vazio, histórico de versões vazio e RLS em todas as tabelas resultantes.
- scripts/test-official-bootstrap-local.mjs validou o pacote em banco temporário separado no Docker local e removeu-o ao final: 41 tabelas, todas com RLS, zero usuários/clientes/unidades/equipe, privilégios essenciais corretos, escrita legada bloqueada e repetição recusada. Os 23 testes JavaScript e build passaram.
- [Revisão concreta da implantação](implantacao-banco-oficial-2026-10-28.md). Nenhuma migration aplicada no projeto oficial: autorização ainda pendente. Editor não respondeu à carga integral; painel recuperado em nova aba. Não executar rascunho do editor sem conferir integridade com o pacote local revisado.

## Instalação otimizada autorizada e retomada em 29/10/2026

- O responsável autorizou criar a estrutura e pediu evitar tabelas desnecessárias. A instalação foi otimizada para 19 tabelas, retirando 22 estruturas de fluxos antigos. A versão de otimização só executa a limpeza em instalação inicial explicitamente selecionada e recusa dados existentes; o banco local foi preservado.
- Script de 26 versões validado em banco temporário local, com cenários de isolamento de clientes, unidades inativas, permissões de Admin/arquiteta, prazos, cadastro, importação e lembretes. Instalação repetida e limpeza com dados recusadas. Arquivo do editor conferido integralmente antes da execução oficial.
- Painel confirmou instalação concluída. Consulta de leitura em 29/10 confirmou 19 tabelas, zero tabelas sem RLS, 26 versões, zero contas Auth/clientes/unidades/equipe. Evidência em outputs/qa/supabase-official-schema-verified-20261029.png. Não executar novamente a instalação inicial.
- Resend oficial permanece com domínio Verified e sem chaves. Formulário preparado para chave somente de envio e limitada ao subdomínio do Exclusive. Formulário SMTP no Supabase preparado sem senha e sem salvar. Criação/entrada da credencial pendente do responsável; primeiro Admin remoto continua dependendo de autorização específica.

## SMTP oficial salvo pelo responsável

- Responsável concluiu a chave e salvou no Supabase. Nova página confirmou configuração persistida: SMTP habilitado, smtp.resend.com:587, nome City Park Exclusive e credencial armazenada oculta. Nenhum segredo lido ou copiado. Ainda sem teste de entrega oficial.
- Código de seis dígitos/600 segundos e mensagem de recuperação em português preparados sem salvar. Cadastro público ainda habilitado por padrão; seu bloqueio faz parte da autorização solicitada. Prévia em outputs/qa/supabase-official-recovery-preview-20261029.png.
- Solicitada autorização específica para ajustes e primeiro Admin oficial. Script guardado em scripts/provision-official-admin.sql, sem execução. Conta Auth não criada; formulário com e-mail oficial e senha vazia, confirmação automática desmarcada.

## Autenticação oficial concluída e validada — 29/10/2026

- Autorizações recebidas: ajustes de login e Admin oficial; publicação de admin-customer com verificação de sessão na função; cliente Vinícius/Gmail e unidade 1505 A para validação. Configurações remotas salvas: código de seis dígitos por dez minutos, mensagem em português, cadastro público bloqueado. SMTP e domínio oficiais verificados.
- Responsável criou o Admin com a própria senha e informou confirmação automática marcada. Atribuição específica guardada em scripts/provision-official-admin.sql executada após autorização; retorno admin/true. Responsável recebeu e-mail oficial, definiu senha pelo Exclusive e acessou como Admin.
- admin-customer publicado e config.toml alinhado com verify_jwt=false para chaves atuais; o handler valida Auth.getUser e papel Admin. Pedidos reais sem login e com token inválido rejeitados com 403. O Admin autenticado cadastrou Vinícius pelo painel, sem convite nem senha escolhida pelo operador.
- Unidade 1505A criada sem catálogo, área ou prazo inventados e com tipologia A confirmar; vínculo owner realizado pelo painel Admin. Responsável confirmou código no Gmail, definição de senha e acesso à seleção da própria unidade. Planta continua em preparação, sem planta-base atribuída.
- Consulta final: 19 tabelas protegidas, duas contas Auth, um cliente, uma unidade, um Admin e um vínculo ativo owner; e-mail do cliente confirmado. Evidência outputs/qa/exclusive-official-customer-first-access-20261029.png.
- 31 testes passaram e build official concluído. .env.official.local só contém URL/chave pública e permanece ignorado. Servidor de validação em 127.0.0.1:5175/exclusive usa o banco oficial; o ambiente local padrão foi preservado. Nenhuma publicação de frontend no site atual, importação Firebase ou importação de catálogo de demonstração. Próximas etapas: dados oficiais de plantas/opções/unidades e publicação revisada da interface.

## Avisos de prazo — preparação em 29/10/2026

- Responsável priorizou os avisos de prazo. Fila deadline_notifications e funções de reserva/registro existentes serão reutilizadas, sem novas tabelas do aplicativo.
- Worker deadline-reminders atualizado para transporte direto pela API Resend oficial, mantendo webhook para testes locais. Configuração de login não alterada. Chave do provedor e token do agendador ficam somente em segredos do servidor.
- Lote limitado a dez avisos, timeout por pedido, intervalo de 600ms, mesma chave de idempotência nas tentativas, resposta do provedor conferida antes de registrar aceite e erros registrados sem conteúdo de credenciais. Mensagem identifica módulo/unidade e data/hora em São Paulo; singular corrigido no aviso de um dia.
- Nove testes isolados novos passaram; suíte completa com 40 testes passou. Cobertos autenticação, configuração ausente/insegura, quatro marcos, módulo, fuso, falha de transporte/recibo, falha de registro com repetição idêntica, fila vazia e webhook local. Docker local não disponibilizou o daemon nesta retomada; os testes SQL anteriores da fila não foram reexecutados ainda. Nenhum fixture novo foi executado no banco oficial.
- Publicação preparada no editor e fonte comparada integralmente ao repositório. Não publicada ainda. scripts/enable-official-deadline-schedule.sql preparado para verificação a cada dez minutos, com token no Vault e recusa de job duplicado. docs/avisos-de-prazo.md descreve implantação e teste real proposto.
- Solicitadas autorizações para publicação/agendamento e teste temporário de 15 dias na unidade 1505 A, com envio ao Gmail controlado e restauração do prazo nulo. Formulário Secrets preparado com DEADLINE_EMAIL_PROVIDER=resend, remetente oficial e valores de RESEND_API_KEY/DEADLINE_REMINDER_TOKEN vazios. Nenhuma configuração salva, novo segredo gerado ou mensagem de prazo enviada nesta preparação.

## Avisos autorizados e função publicada

- Recebidas autorizações específicas para publicar/agendar a cada dez minutos, durante todo o dia, e testar com prazo temporário de 15 dias na 1505 A/Gmail controlado.
- deadline-reminders publicado após conferência integral da fonte. Gateway legado desativado; segredo exclusivo validado pelo handler. Testes HTTP reais sem autorização e com token errado retornaram 401.
- Responsável salvou os quatro campos privados nas Edge Functions; conferidas somente presença e digests. Solicitado ao responsável colar o mesmo token no Vault, em formulário com nome citypark_deadline_reminder_token preparado. Nenhum segredo lido ou registrado na conversa.
- Extensões pg_cron 1.6.4 e pg_net 0.20.4 habilitadas após autorização. Job ainda não criado, sem alteração de prazo nem envio real de aviso. Pendentes: token Vault, teste autenticado com fila vazia, teste de envio/deduplicação com restauração do prazo e ativação/verificação do job. Essas ações já estão autorizadas, não pedir novamente.

## Avisos de prazo concluídos — 30/10/2026

- Token de 64 caracteres salvo pelo responsável nas Edge Functions e no Vault citypark_deadline_reminder_token_v2; igualdade validada por digest sem expor valores. Segredo antigo sem sufixo permanece sem uso.
- Teste autorizado em 29/10 retornou HTTP 200/sent=1; Resend confirmou entrega ao Gmail. Repetição retornou sent=0, com um único registro enviado e uma tentativa. Prazo da 1505 A restaurado para NULL e histórico preservado.
- Retomada de 30/10 confirmou ausência de job e executou o script já autorizado. Job único citypark-deadline-reminders confirmado ativo com */10 * * * *: verificação a cada dez minutos durante todo o dia, sem novas tabelas.
- Nova chamada autenticada retornou HTTP 200, sent=0/failed=0; unidade 1505 A continua sem prazo, com apenas o aviso de teste anterior. Evidência outputs/qa/deadline-schedule-active-20261030.png. Execução natural futura do cron ainda não observada nesta conferência.
- Suíte completa: 41 testes passaram. Estado operacional e manutenção em docs/avisos-de-prazo.md. Catálogo real, contratos/PDF e publicação da interface continuam pendentes.
