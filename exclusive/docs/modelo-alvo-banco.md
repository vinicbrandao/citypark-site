# Modelo alvo do banco — CityPark Exclusive

Proposta de modelagem em 05/10/2026, baseada no EXCLUSIVE_STATUS.md, no schema local e nas decisões de Vini. O catálogo e as plantas reais ainda estão em preparação; esta proposta define relações e regras, não cadastra dados definitivos.

## Decisões confirmadas

- O código 1208A identifica andar 12, terminação 08 e torre A. Esses valores devem existir separadamente no banco.
- A equipe CityPark atribui explicitamente uma planta base à unidade. Unidades podem compartilhar a mesma planta; terminações diferentes podem receber plantas diferentes. O código não escolhe a planta automaticamente.
- Área social e Suíte Master são dois grupos do módulo Planta. Cada grupo oferece uma escolha entre suas opções. Essas escolhas alteram a configuração estrutural e/ou o mobiliário; as 12 combinações do protótipo não são 12 plantas base.
- O módulo Planta tem prazo próprio. Ao vencer, as escolhas permanecem visíveis, mas o cliente não pode mudá-las. Outros módulos não devem ser bloqueados por esse prazo.
- A configuração pertence à unidade e é compartilhada por owner e co_owner. O autor de cada alteração fica no histórico.

## Módulo Planta no protótipo

| Grupo | Opções descritas por Vini |
| --- | --- |
| Área social | Padrão; Padrão + Euroglass; Sala e Varanda Integradas + Euroglass; Sala e Varanda Integradas com Ilha + Euroglass |
| Suíte Master | Suíte padrão; Suíte Master ampliada + closet; Suíte Master ampliada + gabinete/quarto |

Esses nomes descrevem os casos de uso atuais; a lista técnica final será validada antes do cadastro definitivo. A quarta opção de Área social tem descrição diferente no app.js do protótipo, que também cita a cozinha. Não sincronizar nomes automaticamente sem essa validação.

## Entidades e relações alvo

| Entidade | Chave e relação principal | Papel |
| --- | --- | --- |
| units | id; code único; floor_number, termination_code, tower_code separados | Identifica a unidade. O código 1208A continua para exibição/importação. |
| base_plans | id; code único | Uma linha por planta base técnica reutilizável. plans permanece temporariamente como tabela de combinações do protótipo. |
| unit_base_plan_assignments | unit_id único → units; base_plan_id → base_plans | Planta base atual escolhida pela equipe. Ausência de linha significa atribuição pendente; registrar autor/data. Histórico de trocas será definido com o fluxo administrativo. |
| customers / customer_users / customer_units | Relações já existentes | Identificam proprietários e coproprietários com vínculo ativo à unidade. |
| customization_modules | code único | Organiza Planta e os demais módulos de personalização. |
| customization_groups | module_code → customization_modules | No módulo Planta: Área social e Suíte Master, cada um com exatamente uma opção quando completo. |
| customization_options | group_id → customization_groups | Opções como Padrão + Euroglass, sala/varanda integrada e suíte ampliada + closet. |
| base_plan_option_availability | (base_plan_id, option_id) | Define quais opções cada planta base permite. Regras entre opções entram em estrutura própria se necessárias. |
| unit_module_windows | (unit_id, module_code), opens_at, closes_at | Prazo definido pela equipe para cada unidade e módulo. Planta exige janela cadastrada para permitir edição. |
| unit_configuration | unit_id único; base_plan_id, status | Configuração central compartilhada. |
| unit_module_state | (unit_id, module_code), revision | Controla concorrência e progresso de cada módulo sem bloquear alterações em outro. |
| unit_configuration_selections | (unit_id, group_id, option_id) | Escolhas correntes, inclusive rascunho parcial. Não pertencem exclusivamente a um proprietário. |
| configuration_history | unidade, módulo, revisão, autor e instantâneo | Histórico imutável, incluindo o vínculo customer_units usado pelo autor quando aplicável. |

Exemplo: code = 1208A, floor_number = 12, termination_code = 08, tower_code = A. A equipe atribui o plan_id quando a planta base dessa unidade estiver preparada. Para o módulo Planta, a equipe também define a janela de edição dessa unidade.

## Regras que devem ficar no banco

1. Validar a decomposição do código e a unicidade de (tower_code, floor_number, termination_code). Guardar terminação como texto para preservar o zero inicial.
2. Permitir somente uma planta base atribuída por unidade de cada vez; várias unidades podem referenciar a mesma planta. Só o processo administrativo autorizado altera a atribuição.
3. Mostrar catálogo e configuração ao usuário somente quando customer_users e customer_units estiverem ativos para a unidade. A equipe técnica mantém escopo por unidade e autorização quando exigida.
4. Salvar por RPC transacional com escopo de módulo: verificar acesso, planta atribuída, opções disponíveis, cardinalidade dos grupos, regras de compatibilidade, janela e revisão esperada. Uma gravação de outro módulo não pode reescrever escolhas de Planta.
5. Para Planta, negar no servidor qualquer alteração quando a janela estiver ausente, suspensa, ainda não aberta ou encerrada. Comparar o horário do servidor com closes_at imediatamente antes de persistir. Continuar permitindo leitura e histórico depois do prazo.
6. Registrar cada edição em histórico sem reescrever revisões antigas. A regra de envio/aprovação e eventuais exceções administrativas ao prazo ainda precisam de definição.
7. Manter preços e quantitativos oficiais fora dos valores fictícios do frontend. Quando definidos, versionar a fonte e guardar um instantâneo dos valores usados na configuração enviada.

## Transição do protótipo local

O banco local hoje guarda 12 combinações de Área social × Suíte Master em plans, muitas relações em unit_plans e essas escolhas em plan_features. units.termination contém valores como 09A e units.tower contém um rótulo de teste como Torre Liberty. customization_windows tem uma única janela por unidade, aplicada à configuração inteira. Os RPCs atuais substituem todas as escolhas e verificam essa janela global. A interface ainda salva em unit_drafts.

A migration 20261005000100_unit_base_plans_and_modules.sql foi aplicada ao Supabase local em 06/10/2026 e teve o isolamento RLS validado em transação revertida. Ela separa os componentes da unidade, cria base_plans e sua atribuição por unidade, registra o módulo Planta e prepara janelas por unidade/módulo. Não migra opções, configuração nem RPCs. Depois de receber da equipe a lista unidade → planta base, converter somente a configuração corrente. O histórico do protótipo fica preservado como legado. Na ativação dos RPCs definitivos, revogar ou substituir save_unit_draft, save_unit_configuration, save_partial_unit_configuration e outros caminhos de gravação legados que possam contornar o prazo por módulo. Só então a interface passa a usar os novos RPCs.

Em 06/10/2026, a migration 20261006000100_module_choices.sql acrescentou ao Supabase local as tabelas de disponibilidade, incompatibilidade, escolhas, estado e histórico por módulo e o RPC save_unit_module_choices. Ele foi validado com fixtures revertidas, incluindo prazo e isolamento de módulos. Como a interface ainda usa o rascunho legado, a regra de prazo ainda não protege o fluxo atual do cliente. Nenhum dado oficial foi inserido.

Também em 06/10/2026, as migrations 20261006000200_architect_assistance_requests.sql e 20261006000300_unit_proposals.sql acrescentaram pedidos de ajuda e a primeira estrutura de proposta. Em 07/10/2026, `20261007000100_proposal_cycles_and_edit_limit.sql` refinou esse modelo: uma unidade pode manter vários ciclos históricos de proposta; cada ciclo possui no máximo quatro versões submetidas (envio inicial + três alterações); salvar módulos não cria versão de proposta; o parecer da arquiteta encerra o ciclo e libera o seguinte.

## Definições ainda necessárias para a migration completa

- Lista das plantas base reais e atribuição por unidade, quando a equipe CityPark a preparar.
- Opções técnicas e disponibilidade por planta, com Allef.
- Data de abertura/encerramento do módulo Planta para cada unidade e regras de eventual exceção administrativa.
- Owner e co_owner podem enviar e editar a mesma proposta. Cada ciclo permite 1 envio inicial + 3 alterações reenviadas. O quarto envio bloqueia novas edições do cliente até o parecer técnico; depois do parecer, um novo ciclo pode começar com o limite reiniciado. Ainda falta definir a aprovação comercial/final posterior ao parecer técnico.
- Origem e vigência de preços e quantitativos oficiais.






