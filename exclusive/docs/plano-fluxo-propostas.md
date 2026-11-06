# Plano de ação — escolhas, ajuda e propostas

Estado em 06/10/2026. Este plano separa o que existe no Supabase local do que ainda precisa entrar em produção. Não há plantas, prazos, catálogo nem preços oficiais cadastrados.

## Dependências e regras a fechar

- CityPark: lista de plantas base reais, atribuição explícita por unidade, prazos por unidade/módulo e arquiteta responsável ou regra de distribuição.
- Allef/equipe: grupos e opções reais, disponibilidade por planta, compatibilidade e materiais de apresentação. Os dados atuais são de teste.
- **Decidido em 06/10/2026:** owner e co_owner podem enviar e editar a proposta da unidade.
- **Decidido em 07/10/2026:** cada ciclo de proposta permite 1 envio inicial + até 3 alterações reenviadas, totalizando no máximo 4 versões submetidas. Salvar módulos não consome uma alteração; a contagem aumenta somente no envio/reenvio explícito. Ao atingir a quarta versão, o cliente não pode continuar editando aquele ciclo. A arquiteta avalia somente a versão submetida mais recente. O parecer encerra o ciclo e libera uma nova proposta, novamente com 1 envio inicial + 3 alterações. Todos os ciclos e versões anteriores permanecem no histórico.
- Negócio ainda pendente: o que significa aprovação comercial/final após a viabilidade técnica e se haverá aviso adicional à equipe a cada reenvio.
- Atendimento: quem recebe o pedido de ajuda, como a arquiteta o aceita e se a autorização atual do cliente é suficiente para atuar. Definir os canais de aviso ao cliente e à equipe.

## Execução em ordem

| Etapa | Banco e regras | Interface e verificação | Conclusão esperada |
| --- | --- | --- | --- |
| 1. Preparar catálogo e prazos | Cadastrar plantas, atribuições, grupos, opções, disponibilidade por planta e janelas de edição com dados aprovados; manter histórico do protótipo. | Mostrar a planta e os prazos corretos da unidade. | Cada unidade de teste tem catálogo permitido e prazo verificável. |
| 2. Salvar por módulo | Criar configuração compartilhada por unidade, escolhas correntes, revisão por módulo e histórico imutável. RPC transacional valida acesso, planta, opções, compatibilidade, revisão e prazo com relógio do servidor. Ausência de prazo bloqueia a edição de Planta. | Trocar `save_unit_draft` pelo salvamento por módulo; impedir edição visual após o prazo. | Owner/co_owner e arquiteta autorizada salvam somente módulos permitidos; outro módulo não regrava Planta. |
| 3. Fechar desvios legados | Migrar escolhas correntes apenas com correspondência confiável; preservar revisões antigas; revogar/substituir `save_unit_draft`, `save_unit_configuration`, `save_partial_unit_configuration` e `save_staff_unit_configuration` quando a interface nova estiver pronta. | Conferir leitura e edição para cliente, admin e arquiteta. | Nenhum RPC antigo contorna prazo, escopo ou versão. |
| 4. Pedido de ajuda | Registrar pedido por unidade, cliente, arquiteta e estado; auditar quem pediu e atendeu. Reutilizar atribuição e autorização da arquiteta, ajustando suas regras conforme decisão da equipe. | Cliente pede ajuda; equipe vê e assume o pedido. | Arquiteta designada consegue editar a configuração da unidade com autoria registrada. |
| 5. Envio da proposta | Criar ato de envio transacional, identificador, revisão corrente, instante e instantâneo das escolhas e da planta; rejeitar envio incompleto ou com revisão desatualizada. O estado de envio deve ser separado do rascunho editável. Owner e co_owner têm o mesmo direito de envio. | Botão de enviar com confirmação do conteúdo; mensagem de recebimento só após sucesso do banco. | Equipe vê a mesma proposta da unidade, na revisão mais recente; cliente vê comprovante e estado. |
| 6. Edição após envio | Manter alterações como rascunho até o cliente reenviar. Cada ciclo aceita no máximo 4 versões submetidas: inicial + 3 alterações. Ao chegar à quarta, bloquear novas edições do cliente até o parecer. | Mostrar quantas alterações restam e oferecer reenvio explícito. | Salvar não gasta alteração; reenviar cria nova versão; o limite é garantido no banco. |
| 7. Revisão e comunicação | Ligar o parecer à versão submetida mais recente. Se existirem alterações salvas ainda não reenviadas, impedir o parecer. Ao registrar o parecer, encerrar o ciclo e liberar o próximo. | Mostrar estado, parecer e opção de preparar nova proposta. | Cliente recebe retorno rastreável; novo ciclo reinicia o limite de 1 + 3. |
| 8. Teste e ativação | Testar RLS, cliente de outra unidade, autorização revogada, owner/co_owner, conflito de revisões, prazo no limite, reenvio e revisão de versão antiga. | Testar a jornada ponta a ponta com dados fictícios antes dos reais. | Fluxo completo funciona sem perda de histórico nem acesso indevido. |

## Impacto nos fluxos existentes

O login e a associação cliente–unidade podem ser reaproveitados. A importação de clientes/unidades não precisa mudar para criar o envio da proposta, embora precise fornecer atribuições e prazos quando esses dados estiverem disponíveis.

O configurador e os quatro RPCs de gravação legados **precisam** mudar juntos: hoje salvam escolhas da unidade em bloco ou usam a janela global, o que permitiria alterar Planta após seu prazo. O fluxo da arquiteta também precisa acompanhar as novas revisões por módulo e por proposta; `configuration_reviews` atualmente revisa uma revisão de configuração em rascunho, sem envio formal. A autorização para a arquiteta já existe no banco, mas não há pedido de ajuda na interface.

## Contrato inicial do salvamento por módulo

Entrada: unidade, módulo, escolhas daquele módulo e revisão esperada. O cliente não informa preço, planta base, autor nem horário. O servidor identifica o usuário autenticado e seu vínculo owner/co_owner ou acesso de equipe.

Na mesma transação, o banco bloqueia a revisão corrente da unidade/módulo, verifica planta atribuída, opções ativas e disponíveis nessa planta, compatibilidade definida no catálogo e janela do módulo. Para Planta, janela ausente ou vencida rejeita a gravação. A função altera somente escolhas do módulo informado, aumenta a revisão e grava um instantâneo com autor e horário. Uma revisão desatualizada falha sem sobrescrever trabalho de outro proprietário ou da arquiteta.

A proposta enviada aponta para um instantâneo da configuração. Alterações salvas depois do envio continuam como rascunho e só viram uma nova versão da proposta quando o cliente reenviar explicitamente. Cada ciclo aceita no máximo quatro versões submetidas. A arquiteta abre a versão submetida mais recente; se houver rascunho mais novo ainda não reenviado, o parecer é bloqueado. Após o parecer, o ciclo é encerrado e o próximo envio cria um novo ciclo com o limite reiniciado.

## Próxima entrega técnica independente dos dados oficiais

O contrato foi implementado inicialmente em `20261006000100_module_choices.sql` e testado com fixtures locais revertidas. Próximo: validar e cadastrar o catálogo e os prazos oficiais, mapear as escolhas correntes e integrar a interface ao novo RPC, substituindo os caminhos antigos na mesma entrega. A ativação do envio depende também das regras de negócio ainda listadas acima.

Em 06/10/2026, a etapa 4 recebeu a estrutura de banco `20261006000200_architect_assistance_requests.sql` e teste transacional local. Pedir ajuda exige autorização vigente da arquiteta, concedida separadamente pelo cliente; cancelar o pedido não a revoga. Falta a interface de cliente e equipe.

No mesmo dia, `20261006000300_unit_proposals.sql` implementou no banco a proposta única por unidade, o envio por owner/co_owner, versões após novas escolhas e o parecer da arquiteta somente na versão atual. Os testes foram transacionais e revertidos. As etapas de interface, avisos externos, confirmação final e dados oficiais permanecem pendentes.

Em 07/10/2026, a migration `20261007000100_proposal_cycles_and_edit_limit.sql` substituiu o versionamento automático por salvamento por versões explícitas no envio, introduziu ciclos de proposta e o limite de 1 envio inicial + 3 alterações. O teste `scripts/test-unit-proposals-local.sql` foi atualizado para validar essa regra quando executado no Supabase local.
