# Inventário oficial — 389 unidades cadastradas

Carga autorizada e aplicada em 30/10/2026 no projeto `grfmiuopojbxxbdymqax`. Origem: quatro prints contínuos conferidos pelo responsável. Cores comerciais ignoradas.

| Torre | Andares / terminações | Total |
| --- | --- | ---: |
| Liberty A | 2º–21º: 01–10; 22º: 01–09 | 209 |
| Liberty B | 2º–21º: 01–09 | 180 |
| Total | Códigos únicos e localização por torre/andar/terminação | 389 |

Preenchidos: `code`, `tower`, `tower_code`, `floor_label`, `floor_number`, `termination`, `termination_code`. Exemplo: `1505A`, torre A, 15º andar, terminação 05. Listagem da equipe ordenada por torre, andar numérico e terminação.

As 388 unidades novas estão inativas/Pendentes, com tipologia `A confirmar`, área e prazo NULL e sem planta, cliente ou janelas de módulo atribuídos. `typology` atualmente exige texto; `A confirmar` é marcador de ausência de informação, não tipologia técnica. Quantitativos/preços oficiais não foram inventados nem cadastrados.

A 1505 A existente foi preservada integralmente: mesmo UUID, ativa/Pendente, sem prazo, mesmo vínculo. Uma comparação com a cópia anterior confirmou todos os seus campos e as contagens anteriores de clientes, contas Auth, vínculos e avisos. O total oficial permanece em 19 tabelas com RLS e 26 versões; esta carga de dados não aplica a migration de permissões pendente.

Implementação: `scripts/prepare-unit-inventory.mjs` gera a lista e a carga transacional em `outputs/deployment/grfmiuopojbxxbdymqax/unit-inventory.sql`, com manifesto/hash. Não conecta ao banco nem executa automaticamente. Recusa códigos/localizações conflitantes, insere somente ausentes e preserva registros anteriores; repetir não duplica nem reinativa unidades já configuradas.

Validação: `node scripts/test-unit-inventory-local.mjs`, em banco temporário, passou com 389 unidades, repetição idempotente, conflito recusado e cliente restrito à própria unidade. Nenhum dado do banco Docker existente foi alterado.

Evidências privadas: `outputs/backups/units-before-inventory-*.json` (estado anterior das unidades e contagens relacionadas, não backup completo do projeto), `outputs/qa/unit-inventory-verified-20261030.json` e `outputs/qa/unit-inventory-official-20261030.png`.

Próximo preenchimento: tipologias reais, áreas, plantas-base, quantitativos/preços e vínculos, conforme dados oficiais. A ativação das unidades ocorre pela equipe quando apropriado. Não criar unidades além da lista aprovada, não derivar disponibilidade das cores e não substituir dados reais por marcadores em uma nova execução da carga.
