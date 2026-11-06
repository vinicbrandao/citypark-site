# Catálogo de personalização: estado real do projeto

Leitura do repositório e do Supabase local em 05/10/2026. Allef modificou a pasta antes da entrada de Vini e iniciou testes locais para explorar o Exclusive. Portanto, os registros e o schema de outubro são protótipos que ajudam a levantar requisitos, não o modelo definitivo. Vini é responsável pela modelagem final do banco. Foram restaurados nesta pasta os seis arquivos de migration de outubro que já estavam aplicados no banco; a lista local agora coincide com as 12 versões aplicadas.

## Respostas ao ponto de retomada

1. **Usuários, clientes e unidades.** auth.users identifica pessoas; customer_users liga usuários a customers; customer_units liga clientes a units. staff_users guarda admin e architect. Existem staff_unit_assignments e autorização do cliente para a arquiteta.
2. **customer_units.** Chave primária (customer_id, unit_id), active, ownership_role (owner ou co_owner), purchase_date, external_ref único quando preenchido e created_at. A mesma unidade pode ter vários proprietários.
3. **Migrations aplicadas.** As seis migrations de setembro do repositório e as seis de 01–02/10/2026 estão aplicadas no Supabase local. As de outubro criam o catálogo, rascunho parcial, edição da equipe, acesso por unidade, autorização de arquiteta e revisão. Seus arquivos faltavam no repositório e foram recuperados do histórico SQL do próprio banco. Nenhuma nova migration foi aplicada nesta sessão.
4. **RLS.** O catálogo e a configuração têm somente leitura direta para authenticated, condicionada ao acesso à unidade por RLS. A escrita é feita por RPC. Admin acessa unidades ativas; architect precisa de atribuição ativa e autorização vigente de proprietário ativo. A autorização é revogada efetivamente se o vínculo do concedente deixa de estar ativo. O rascunho legado também foi restringido para architect por unidade.
5. **Rascunho e histórico.** O fluxo antigo usa unit_drafts, save_unit_draft e draft_history, ainda chamados pela interface. O fluxo novo usa unit_configuration_state como estado/revisão por unidade, customer_customizations como escolhas normalizadas e customization_history como instantâneos imutáveis de cada revisão. O rascunho parcial fica em draft_selections e é gravado no histórico como ui_draft; o completo usa catalog_ids.
6. **Reaproveitamento.** O modelo novo já aproveita o vínculo customer_units e revisão otimista. O legado permanece para transição da interface; não deve receber funcionalidades novas em paralelo.
7. **Plantas e unidades no protótipo.** plans guarda as 12 combinações social × suíte como se fossem plantas; unit_plans associa várias delas a cada unidade; plan_features guarda as duas escolhas. **Decisão de Vini:** essas combinações são escolhas sobre uma planta base, não 12 plantas. No modelo definitivo, cada unidade aponta para sua planta base reutilizável e as escolhas social/suíte ficam na configuração da unidade.
8. **Grupos e opções.** customization_groups define grupos globais; customization_options pertence a um grupo. Cada opção possui status e ordem. No protótipo há uma escolha por grupo em customer_customizations. O modelo definitivo deve incluir também área social e suíte entre os grupos de escolha, junto aos grupos de materiais. No banco local há 12 combinações de plantas da interface e 2 plantas de teste; 4 grupos e 8 opções da interface, mais 1 grupo e 2 opções de teste; 96 vínculos de disponibilidade da interface e 3 de teste. Esses registros são dados de teste do protótipo no banco local, separados das contas fictícias. Não encontrei um seed do catálogo nesta pasta.
9. **Compatibilidade.** option_compatibilities permite ou bloqueia uma opção para determinada planta. Os RPCs validam que todas as opções escolhidas estejam ativas e disponíveis para a planta e que não haja mais de uma por grupo. Não existe regra de dependência ou exclusão entre pares de opções; incluir isso somente se as regras de Allef exigirem.
10. **Owner e co_owner.** Ambos podem salvar configuração pelo RPC e conceder/revogar autorização à arquiteta. A revisão otimista serializa edições. Não há regra de prioridade entre proprietários nem RPC de envio final do cliente.
11. **Estado central.** unit_configuration_state guarda unidade, planta escolhida, revision, draft_selections e status. Os valores permitidos são draft, submitted e locked, mas os RPCs atuais salvam somente enquanto status é draft. Não foi encontrado fluxo que efetivamente submeta ou bloqueie a configuração.
12. **RPCs.** save_unit_configuration valida escolha completa; save_partial_unit_configuration valida rascunho parcial; save_staff_unit_configuration atende equipe autorizada; set_architect_authorization registra consentimento; review_unit_configuration registra uma revisão técnica ligada à revisão exata. Os clientes não devem editar essas tabelas diretamente. Futuro envio, aprovação final e regras adicionais de compatibilidade exigem operação transacional no banco.

## Como usar o protótipo na modelagem

As telas e escolhas atuais indicam entidades e relações candidatas: planta reutilizável, plantas disponíveis por unidade, grupos, opções, disponibilidade de opção por planta, configuração compartilhada, revisão, histórico e permissões por vínculo. A existência dessas tabelas e RPCs no teste local não confirma que nomes, cardinalidades, estados ou regras devam ser mantidos. Preços e quantitativos exibidos em app.js também são valores de demonstração.

Vini deve consolidar o modelo relacional e as regras do banco a partir desses casos de uso e da decisão sobre a planta base. Allef fornece/valida o conteúdo técnico das customizações, combinações possíveis, Revit, renders e quantitativos. Só depois de validar o modelo faz sentido criar migrations de ajuste, preparar dados reais e integrar a interface ao fluxo definitivo.

## Proposta inicial para Vini validar

- **Manter como base:** identidade em auth.users, vínculos customer_users/customer_units, unidade como centro da configuração compartilhada, planta reutilizável e histórico por revisão. Esses relacionamentos já respondem aos casos de várias unidades por cliente e vários proprietários por unidade.
- **Decisão confirmada sobre plantas:** as 12 combinações do teste são 4 escolhas de área social × 3 de suíte sobre uma planta base. A planta base é reutilizável entre unidades; essas escolhas pertencem à configuração da unidade. O modelo novo não deve criar uma linha em plans para cada combinação.
- **Módulo Planta e prazo:** Área social e Suíte Master são grupos do módulo Planta. O prazo será específico desse módulo por unidade; após o vencimento, escolhas ficam somente para leitura. O protótipo usa customization_windows com uma única janela por unidade e os RPCs verificam essa janela global, então eles precisam mudar para não bloquear outros módulos.
- **Revisar opções e compatibilidade:** o protótipo suporta uma opção por grupo e disponibilidade por planta. Confirmar se haverá grupos com várias escolhas e regras entre opções; só então acrescentar limites e relações de dependência/exclusão.
- **Separar configuração de autoria:** a configuração atual pertence à unidade. customer_customizations guarda o customer_id do vínculo usado no último salvamento, enquanto customization_history guarda o autor de cada revisão. Confirmar se o customer_id na escolha corrente tem sentido de negócio ou se apenas o histórico deve registrar quem alterou.
- **Fechar o ciclo de vida antes de ativá-lo:** draft/submitted/locked existem como valores no banco, mas falta definir quem envia, quem aprova, quando bloqueia e como reabre. Implementar transições por RPC somente depois dessa decisão.
- **Tratar preço e quantitativos separadamente:** os números de app.js são demonstração. Antes de valores oficiais, definir origem, vigência e instantâneo dos valores usados em cada configuração enviada.

Nenhuma dessas decisões exige substituir as migrations de teste agora. A migração seguinte deve representar apenas diferenças confirmadas no modelo.

## Estrutura alvo para a planta

- **Unidade:** o código 1208A representa andar 12, terminação 08 e torre A. Guardar andar, terminação e torre em campos separados; o código é a identificação de exibição. A planta pode variar conforme a terminação.
- **Planta base:** entidade própria com identidade e atributos técnicos estáveis; várias unidades podem referenciá-la. A equipe CityPark atribui explicitamente uma planta base a cada unidade. A terminação orienta essa atribuição, mas o código não deve selecionar a planta automaticamente.
- **Escolhas de planta:** área social e suíte são grupos de opções, com uma escolha em cada grupo quando a configuração estiver completa. O rascunho pode permanecer parcial.
- **Disponibilidade:** cada planta base determina quais opções de cada grupo são permitidas. Restrições entre opções, se existirem, são regras adicionais e não uma multiplicação de plantas.
- **Configuração e histórico:** uma configuração compartilhada por unidade registra as opções escolhidas, a revisão e o autor de cada alteração. Owner e co_owner acessam a mesma configuração.

A migração precisa receber a relação unidade → planta base definida pela equipe CityPark e converter apenas a configuração corrente. O histórico de revisões antigas deve permanecer intacto, com uma referência clara ao modelo legado. Esse mapeamento ainda não existe nos arquivos; por isso não é seguro alterar as chaves de plans/unit_plans agora.

## Divergência nos campos da unidade

Nos dados locais de teste, 1209A aparece com floor_number = 12, termination = 09A e tower = Torre Liberty. Isso difere da decomposição confirmada: 12 / 09 / A. O importador também compara termination como um único texto. O modelo definitivo deve separar o código da torre da terminação numérica e ajustar importação, validações e interface na mesma transição. Não inferir que Torre Liberty equivale à torre A; esse rótulo é dado de teste.

Como as plantas reais ainda estão em preparação, a migration de atribuição não deve preencher plantas a partir de terminação por suposição. Ela precisa receber a lista explícita unidade → planta base da equipe.

## Divergência e próximo passo

O checkpoint anterior dizia que o catálogo ainda não existia. No banco local há uma implementação experimental criada durante os testes, mas seis migrations estavam ausentes da pasta. As escolhas exibidas estão em app.js; src/main.js ainda usa unit_drafts e save_unit_draft. As contas fictícias de cliente, admin e arquiteta vêm separadamente de scripts/seed-local.mjs e scripts/seed-staff-local.mjs. O próximo trabalho é transformar os testes de Allef em requisitos do modelo definitivo e identificar o que pode ser reaproveitado ou precisa mudar.





