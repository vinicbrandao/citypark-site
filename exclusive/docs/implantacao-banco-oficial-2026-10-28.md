# Banco oficial — instalação concluída e conferida

Atualizado em 29/10/2026. O responsável autorizou a criação e pediu evitar tabelas desnecessárias. As seções anteriores abaixo foram mantidas como registro da proposta inicial; o resultado atual é o descrito nesta abertura.

## Resultado atual

- Projeto oficial grfmiuopojbxxbdymqax: 26 versões instaladas, **19 tabelas públicas, todas protegidas por RLS**.
- Consulta inicial em 29/10, antes da configuração de acesso: zero contas Auth, clientes, unidades e perfis de equipe. Não houve importação de dados locais nem usuários Firebase.
- Retiradas 22 tabelas de fluxos antigos (propostas, pareceres, autorizações e rascunhos persistidos) e funções correspondentes, sem exclusão em cascata. Mantidas as duas tabelas de importação usadas pela revisão e rastreabilidade dos lotes.
- Índice do histórico de unidades ajustado à consulta por unidade e ordem dos eventos.
- Limpeza exige opção explícita de instalação inicial e recusa contas ou dados de negócio. Atualizações normais locais preservam o histórico antigo.
- Script validado em banco temporário local: permissões e isolamento entre clientes, equipe, unidades inativas, reabertura de prazo por Admin, cadastro, importação e lembretes. Cenários revertidos e banco temporário removido. Instalação repetida e limpeza com dados recusadas.
- Texto completo do editor comparado ao arquivo local antes da execução remota, normalizando finais de linha. Painel retornou `CityPark initial schema installed`, com 26 versões.
- Manifesto atual: `outputs/deployment/grfmiuopojbxxbdymqax/manifest.json`. SHA-256 do script instalado: `4e41ac9677b5777eff8f8388fc8b1d30dfa0c97ab57cb8c10914c868da628b3f`.
- Evidência: `outputs/qa/supabase-official-schema-verified-20261029.png`.

As 19 tabelas são: customers, customer_users, staff_users, units, customer_units, import_batches, import_rows, base_plans, unit_base_plan_assignments, customization_modules, unit_module_windows, customization_groups, customization_options, base_plan_option_availability, base_plan_option_exclusions, base_plan_option_defaults, base_plan_option_requirements, unit_activity_events e deadline_notifications.

**Não executar novamente a instalação inicial no projeto já instalado.** Alterações futuras devem ser incrementais.

## Autenticação oficial validada em 29/10/2026

Depois da consulta inicial, o responsável autorizou os ajustes de login, o Admin oficial, a publicação da função de cadastro e os dados de validação de Vinícius/1505 A. SMTP oficial salvo pelo próprio responsável; código com seis dígitos/600 segundos, mensagem em português e cadastro público bloqueado aplicados. Admin exclusive@planoaengenharia.com.br criado pelo responsável e perfil atribuído pelo script específico, sem definir ou ler sua senha.

Função admin-customer publicada com validação de identidade pelo Auth e de perfil Admin pelo banco. A validação antiga de assinatura do gateway foi desativada conforme autorização, para compatibilidade com as chaves do projeto novo. Testes reais rejeitaram pedidos anônimos e com token inválido (403), e o Admin autenticado conseguiu cadastrar o cliente pelo aplicativo.

O vínculo de proprietário foi feito pelo painel Admin. O cliente confirmou recebimento no Gmail, definição da própria senha e seleção da unidade 1505 A. Consulta final confirmou **19 tabelas protegidas, duas contas Auth, um cliente, uma unidade, um Admin e um vínculo ativo de proprietário**, com e-mail do cliente confirmado.

Sem área, prazo ou planta-base inventados. A tipologia está explicitamente A confirmar e o catálogo oficial continua pendente. A instalação e o teste não publicaram o frontend no GitHub Pages; a interface local em modo official usa o Supabase online.

Validações: 31 testes JavaScript e build em modo official passaram. Evidências em outputs/qa/exclusive-official-customer-first-access-20261029.png e outputs/qa/supabase-official-final-counts-20261029.png. Continuação detalhada em configuracao-oficial-autenticacao.md.

---

## Registro histórico: proposta anterior, substituída pela instalação otimizada acima

## Destino confirmado

- Organização: CityPark Exclusive, plano Free, conta exclusive@planoaengenharia.com.br.
- Projeto: citypark-exclusive, referência grfmiuopojbxxbdymqax.
- URL: https://supabase.com/dashboard/project/grfmiuopojbxxbdymqax
- Região observada no painel: São Paulo (sa-east-1). Status Healthy.
- Consulta de leitura realizada no projeto: 0 tabelas públicas, 0 usuários Auth e 0 políticas públicas.

## Alteração proposta para autorização

Aplicar as 25 migrations existentes do repositório, na ordem dos arquivos, com seu histórico de versões. O pacote foi gerado a partir dos próprios arquivos SQL; não usa o dump do banco local nem scripts de seed. A estrutura resultante contém 41 tabelas públicas, todas com RLS habilitada, e as funções/regras já implementadas para clientes, equipe, unidades, personalização por sessão, acesso, prazos e histórico. Estruturas legadas permanecem conforme migrations; seus antigos fluxos de escrita estão revogados.

Inclui somente os registros de referência previstos nas migrations, como o módulo Planta. Não cria contas Auth ou Admin, não importa clientes, unidades, escolhas, dados pessoais ou o catálogo fictício dos testes. A autorização de Admin oficial, publicação das Edge Functions e conexão SMTP serão revisadas nas respectivas etapas.

O script verifica que o esquema público e os usuários Auth estão vazios antes de começar, recusa um histórico de migrations já preenchido, valida RLS nas tabelas e usa uma única transação. Se houver erro, a transação deve ser revertida integralmente. A referência do projeto está identificada no cabeçalho e no manifesto; conferir também o destino no painel antes da execução.

## Arquivos concretos de revisão

- Pacote: `outputs/deployment/grfmiuopojbxxbdymqax/initial-schema.sql`.
- Manifesto com lista das 25 migrations e hashes SHA-256: `outputs/deployment/grfmiuopojbxxbdymqax/manifest.json`.
- Gerador reproduzível: `node scripts/prepare-official-deployment.mjs` (não conecta a nenhum servidor).
- Teste de instalação inicial: `node scripts/test-official-bootstrap-local.mjs` (usa apenas Docker local e um banco temporário com nome exclusivo).

## Validação executada

O teste criou um banco temporário separado no contêiner local existente, copiou somente a estrutura gerenciada do Auth, sem registros nem ACLs globais, e executou o pacote inteiro. Não recebeu URL nem credenciais remotas. O banco temporário foi removido ao final; o banco local de trabalho foi preservado.

Resultado: 25 migrations, 41 tabelas, nenhuma tabela sem RLS, nenhum usuário Auth/cliente/unidade/perfil de equipe criado. Conferidos acesso autenticado às tabelas necessárias e à listagem de unidades, bloqueio anônimo de clientes e revogação da escrita legada. Uma segunda execução foi recusada pela proteção de banco vazio. Os 23 testes JavaScript existentes e o build também passaram.

## Estado da execução remota

**Ainda não autorizado nem executado.** No projeto oficial foi executada somente a consulta de leitura descrita acima. A tentativa de carregar o pacote completo no editor SQL pelo navegador ficou sem responder; nenhum comando Run foi acionado para esse pacote. Painel recuperado em uma nova aba e confirmado sem migrations aplicadas. O arquivo local é a fonte da revisão; não presumir que qualquer rascunho do editor contenha o pacote completo. Depois da autorização, escolher a forma de envio e conferir a integridade antes de executar.

Captura do projeto antes da instalação: `outputs/qa/supabase-official-project-before-schema-20261028.png`. A conta oficial do Resend e seu domínio acesso.cityparkmcz.com.br já estão verificados, mas o envio oficial ainda não foi conectado ao aplicativo.
