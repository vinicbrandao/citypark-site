# Permissões para produção — decisões de 30/10/2026

Regras aprovadas pelo responsável em resposta ao questionário. Este documento especifica o alvo e a revisão inicial do código; **não comprova implantação no Supabase**. Para o estado operacional, consultar [checkpoint](EXCLUSIVE_STATUS.md).

## Cliente

- Consulta somente suas unidades e preços apresentados nas opções. Experimenta escolhas durante a sessão; não salva rascunho persistente.
- Não altera nome, e-mail ou telefone. Admin preenche e mantém esses dados.
- Unidade inativa permanece como card cinza com aviso; configurador bloqueado. Conta sem vínculo mantém Acesso em preparação.
- Pode receber/salvar um PDF do resumo solicitado. Não interpretar isso como autorização para persistir rascunhos.
- Histórico visível ao cliente será de contratos: cada ocorrência com dia, hora e link para o PDF correspondente. Não expor a auditoria interna de acessos e alterações da equipe.
- PDF/resumo e histórico de contratos ainda pertencem à etapa de documentos adiada. Antes da implementação, distinguir exportar resumo de gerar/registrar contrato: somente o segundo tem a conclusão/inativação já definida. Não criar esse efeito no simples download de resumo.

## Arquiteta

- Consulta todas as unidades, inclusive inativas, e experimenta escolhas em atendimento, respeitando prazos.
- Consulta nome, e-mail e telefone do cliente; não edita esses dados, não cadastra contas e não altera vínculos.
- Ativa/inativa unidades pendentes. Reativação de concluída permanece exclusiva do Admin.
- Não altera plantas, imagens, opções, compatibilidades, preços ou quantitativos.
- Consulta livremente todo o histórico interno, inclusive ações de outras arquitetas e Admins.

## Admin

- Cadastra/edita nome, e-mail e telefone dos clientes; vincula e troca proprietário. Troca retira imediatamente o acesso anterior às operações futuras da unidade, inclusive com sessão aberta. Conteúdo já baixado não pode ser recolhido.
- Ativa/inativa contas por booleano, preservando dados e vínculos. Conta inativa perde acesso ao ambiente; unidade inativa é um bloqueio distinto.
- Cria Admins/arquitetas e revoga seus acessos por desativação. Nunca excluir fisicamente contas pela interface.
- Conta principal `exclusive@planoaengenharia.com.br` não pode ser removida, desativada ou rebaixada. Proteção deve acompanhar a identidade Auth, não apenas um texto mutável de e-mail, e impedir remoções em cascata.
- Gerencia status, prazos, preços e quantitativos; somente Admin reabre prazos e unidades concluídas.
- Consulta falhas de envio e solicita nova tentativa de aviso. Não reenviar um aviso já aceito pelo provedor; respeitar idempotência, destinatário/vínculo atual, conta ativa e prazo ainda elegível.
- Não apaga clientes, unidades ou catálogo: apenas desativação/arquivamento. Não altera nem apaga histórico. Reforma visual/funcional do histórico interno adiada; imutabilidade não depende dela.

## Inventário fixo de unidades

- Inventário fixo de **389 unidades**, configurado fora das permissões do Admin do aplicativo. Após envio e conferência dos quatro prints, a carga de identificação foi autorizada e concluída em 30/10: 209 A + 180 B. Dados técnicos continuam pendentes; ver [inventário](inventario-unidades-2026-10-30.md).
- Admin não cadastra unidades adicionais nem altera identificação/planta-base. Preços e quantitativos são os atributos técnicos editáveis; status, prazos e vínculo são controles operacionais confirmados separadamente.
- Resposta adicional confirmou troca de proprietário pelo Admin, com perda imediata do acesso anterior.
- Respostas negam edição de catálogo pela arquiteta; não concedem, por inferência, um editor irrestrito de estrutura/compatibilidade ao Admin. Essa estrutura permanece pré-configurada nesta etapa.

## Revisão inicial, anterior à implementação preparada

Atualização: os ajustes de acesso/contatos/equipe/avisos foram preparados e testados em cópias temporárias. Não foram publicados. Ver [entrega e limites](implantacao-permissoes-2026-10-30.md); a tabela abaixo preserva o diagnóstico que orientou essa entrega, não seu estado posterior.

| Regra | Situação conferida no repositório | Ajuste necessário |
| --- | --- | --- |
| Nome/e-mail só pelo Admin | Tabelas sem escrita direta do usuário; cadastro administrativo existente | Completar edição explícita por ID e sincronização segura do e-mail com Auth; auditar também alteração direta pela API Auth |
| Telefone | Campo ausente em `customers` e formulário | Coluna opcional para registros existentes, validação e cadastro/consulta; sem inventar telefones |
| Conta cliente ativa/inativa | `customer_users.active` controla vínculo de acesso, sem gestão completa de conta no painel | Definir bloqueio consistente e reversível em RLS/RPCs, sessão e fila; evitar criar cadastro duplicado ao reativar |
| Gestão de equipe | `staff_users.active` já existe; sem fluxo administrativo completo | Criação/revogação segura, impedir autopromoção e proteger identidade do Admin principal |
| Troca de proprietário | `set_unit_customer` já inativa vínculo anterior atomicamente | Testar sessão antiga e todos os caminhos de leitura/ação; preservar histórico |
| Unidades fixas | Usuários autenticados não têm escrita direta em `units`; cadastro pelo app inexistente | Auditar todos os RPCs/serviços, manter importação técnica separada e validar a lista oficial antes da carga |
| Catálogo, preços e quantitativos | Escrita direta negada aos perfis; protótipo ainda contém preços/quantidades demonstrativos no frontend | Persistência e edição administrativa dos valores oficiais, validação no servidor; não criar um editor irrestrito de catálogo |
| Histórico interno imutável | Perfis autenticados têm apenas leitura de `unit_activity_events` | Auditar caminhos privilegiados e impedir edição/remoção por serviços do aplicativo; preservar registros |
| Falhas e nova tentativa | Admin pode ler `deadline_notifications`; worker já reserva/reenvia falhas elegíveis | Painel e operação manual restrita ao Admin, com limites e auditoria; corrigir elegibilidade de contas bloqueadas e vínculos alterados |
| PDF e histórico de contratos | Não implementados por decisão anterior | Manter adiados; futuramente snapshot imutável, data/hora e acesso privado por identidade/vínculo autorizado |

Fontes revisadas: `src/configurator-adapter.js`, `app.js`, `supabase/functions/admin-customer/index.ts` e migrations de acesso/equipe/gestão/avisos. Trata-se de leitura estática, não de nova conferência do ambiente remoto.

## Critérios para validar os ajustes

1. Cliente não lê dados/unidades de outro cliente nem altera cadastro, mesmo chamando APIs diretamente.
2. Arquiteta consulta contatos/histórico e altera status permitido, mas não modifica cadastro, vínculo, prazo, catálogo ou valores.
3. Conta bloqueada perde acesso às consultas e RPCs com token ainda válido; não recebe novos avisos nem tentativas pendentes indevidas. Reativar não cria conta ou vínculo duplicado.
4. Após troca de proprietário, a sessão anterior é recusada no banco; o novo titular recebe apenas o acesso correspondente ao vínculo atual.
5. Admin comum não remove, bloqueia ou rebaixa o principal por nenhuma função exposta. Conta de cliente não pode obter perfil de equipe por pedido manipulado.
6. Histórico não aceita edição/exclusão por perfis ou endpoints do aplicativo. Revogar equipe preserva autoria passada.
7. Nova tentativa manual não duplica envio aceito, não contorna bloqueios e não entrega ao antigo proprietário.
8. Atualização migra dados existentes sem reset, novos clientes fictícios, perda de vínculos ou novas tabelas sem necessidade.

As decisões definem as permissões desejadas. Publicação de funções que ampliem acessos e demais alterações importantes no ambiente oficial serão apresentadas concretamente para autorização antes da aplicação.
