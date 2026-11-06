# Atualização de permissões — pronta para revisão, não publicada

Destino proposto: Supabase oficial `grfmiuopojbxxbdymqax`. Regras em [permissões aprovadas](permissoes-producao-2026-10-30.md). Aplicação oficial depende de autorização do responsável; nenhum dado remoto foi alterado nesta preparação.

## O que muda

- Migration `20261030000100_production_permissions.sql`: mantém as 19 tabelas; adiciona telefone opcional e ativo/inativo em clientes, proteção da identidade do Admin principal e campos temporários de autorização de troca de e-mail.
- Conta inativa perde acesso nas políticas RLS e RPCs, mesmo com token ainda válido. Auth pode reconhecer a senha, mas a aplicação mostra Conta inativa e o banco recusa os dados. O status da unidade é independente do status da conta.
- Admin cadastra/edita contatos e ativa/desativa clientes. E-mail é alterado pela API administrativa de Auth, após autorização específica e curta no banco; trigger sincroniza o cadastro na mesma transação do Auth. Solicitação direta do cliente é recusada. Nome/telefone são salvos separadamente: eventual falha de e-mail informa que os demais contatos foram salvos, sem simular sucesso total.
- Nova Edge Function `admin-staff`: valida sessão e perfil Admin antes de criar identidade sem senha/convite ou gerir equipe. A RPC valida novamente o perfil, proíbe conversão de cliente em equipe e revogação do próprio Admin. Desativação preserva registros.
- Admin principal fica protegido por identidade Auth: não pode ser rebaixado, desativado, excluído, banido ou ter o endereço alterado pelos caminhos normais. Não se trata de impedir um operador com poder de alterar/remover os próprios triggers por DDL; a proteção cobre as operações do aplicativo e as APIs de contas.
- Histórico interno fica protegido contra UPDATE/DELETE/TRUNCATE, inclusive nas operações de serviço. Clientes, unidades, equipe e itens principais do catálogo só podem ser desativados/arquivados. Contas gerenciadas não podem ser excluídas via Auth.
- Unidades continuam sem cadastro/edição estrutural pelo Admin; limite de 389 registros no banco, para futura carga técnica controlada. Nenhuma unidade nova é criada nesta atualização.
- Admin consulta avisos e solicita nova tentativa de falhas elegíveis. Não repete aceites, não zera limites e não contorna reservas. Fila/worker conferem conta, vínculo, e-mail atual, unidade e prazo; nova conferência ocorre antes da chamada ao provedor. Revogação durante uma chamada externa já em andamento não pode recolher a mensagem.
- Interface reconhece o esquema anterior durante a implantação: funções novas só aparecem depois da nova RPC de estado da conta. Erros de conexão/permissão não são tratados como esquema antigo; compatibilidade limitada ao código de função ausente `PGRST202`.

## Validação concluída

- `npm test`: **56 testes passaram**. `npm run build:official`: passou.
- `node scripts/test-official-bootstrap-local.mjs`: instalação vazia com 27 versões/19 tabelas, todas com RLS, e cenários de cliente/arquiteta/Admin passaram; repetição recusada. Inclui `test-production-permissions-local.sql`: bloqueio com sessão válida, telefone, perda de acesso do antigo proprietário, proteção do principal, histórico imutável, fila e limite de 389 unidades.
- `node scripts/test-permissions-upgrade-local.mjs`: pacote incremental 26 → 27 aplicado a banco temporário preenchido; contas, unidade, vínculos e histórico preservados. Repetição recusada.
- O mesmo roteiro inicia uma cópia temporária do Auth real da imagem local oficial, com tabelas e histórico de migrações próprios. Login, recusa de troca de e-mail pelo cliente e sincronização após alteração administrativa passaram. Sem SMTP externo ou conexão ao projeto remoto. Contêiner/base temporários removidos ao final.
- Prévia no navegador usa apenas memória e dados fictícios: edição de telefone, bloqueio, controles protegidos do principal e recolocação de aviso na fila verificados. Não equivale a uma jornada completa pelas Edge Functions reais publicadas; essa conferência final permanece após a implantação autorizada.
- Evidências em `outputs/qa/permissions-client-preview-20261030.png` e `permissions-principal-preview-20261030.png` (fora do Git).

## Pacote e aplicação após autorização

1. Conferir o projeto e preparar uma cópia de segurança privada antes da alteração; não confundir backup local com backup oficial. A política recorrente de backup/restauração continua sendo a etapa seguinte do plano de produção.
2. Gerar `node scripts/prepare-permissions-deployment.mjs`. Saídas privadas em `outputs/deployment/grfmiuopojbxxbdymqax/permissions-upgrade.sql` e `permissions-manifest.json`, com hashes. Conferir a integridade antes de executar.
3. Script transacional exige exatamente as 26 versões revisadas, 19 tabelas e Admin principal ativo e não banido. Recusa repetição, divergência e falta da identidade principal; não executar o pacote de instalação inicial.
4. Aplicar a atualização incremental e conferir versão 27, RLS e proteção do principal. Nenhuma conta nova é provisionada por essa migration; clientes existentes ficam ativos e sem telefone até preenchimento real.
5. Publicar a nova `admin-staff` e atualizar `admin-customer` e `deadline-reminders`. Gateway legado `verify_jwt=false` usa as validações obrigatórias nos handlers: Auth/perfil nas funções administrativas e segredo exclusivo no worker. Não ativar endpoints sem essas validações nem copiar service key para o frontend.
6. Conferir login/primeiro acesso existentes, consultas dos perfis e respostas não autorizadas. Preservar Admin oficial, Vinícius, vínculo 1505 A e registro do aviso. Não criar novos Admins reais ou enviar mensagens de teste sem autorização específica.
7. Interface continua local via `npm run dev:official`; build não publica o site no GitHub Pages.

## Limites e continuidade

- Não inclui catálogo oficial, editor de preços/quantitativos, contratos, PDF/resumo nem histórico de contratos. A carga separada das 389 unidades foi autorizada e aplicada em 30/10; ver [inventário](inventario-unidades-2026-10-30.md). Essas unidades ainda não têm dados técnicos completos; não confundir controles de acesso preparados com catálogo preenchido.
- Scripts antigos de navegador/worker que apagam fixtures do banco local agora recusam o modelo novo antes de criar dados. Usar os roteiros em bancos temporários para o novo modelo; não liberar DELETE apenas para facilitar testes.
- A migração é aditiva, mas aumenta proteções no Auth e impede exclusões. Recuperação operacional deve preservar histórico; não desabilitar triggers ou conceder privilégios amplos para resolver uma falha sem revisão.

Referências de implementação: [API administrativa de atualização de usuário](https://supabase.com/docs/reference/javascript/auth-admin-updateuserbyid), [gestão de dados de usuários e triggers](https://supabase.com/docs/guides/auth/managing-user-data).
