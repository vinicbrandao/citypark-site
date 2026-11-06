# Validação do login local

Verificado em 17/09/2026 no ambiente local City Park Exclusive.

## Resultado

Docker Engine 29.2.1 e Supabase local iniciados. Migration de clientes, vínculos, unidades e rascunhos aplicada. Duas contas fictícias criadas pelo script local. Nenhum cliente real foi cadastrado e nenhum projeto da conta Supabase na nuvem foi alterado.

## Verificações realizadas

- Seis testes automatizados de estado: isolamento entre unidades, recuperação do rascunho, falha ao salvar, limpeza ao sair, resposta atrasada de salvamento e valores inválidos.
- Testes contra a API real: autenticação por código, provedor de e-mail habilitado, cadastro público bloqueado, leitura restrita por unidade, bloqueio de leitura anônima e de alteração de vínculos.
- Escrita na unidade de outro cliente recusada; campos fora do catálogo recusados; revisão desatualizada recusada; atualização direta de rascunho recusada.
- Interface: solicitação de código recebida no Mailpit; conta A abre somente 1209A; escolha de varanda integrada salva e recuperada após recarregar; saída encerra a tela autenticada; conta B abre somente 1210A.
- Tela de login inspecionada visualmente em desktop. Build preparado para `/exclusive/`.

## Limites desta entrega

O ambiente da CLI é exclusivo para desenvolvimento. Os e-mails ficam na caixa de teste local. Ainda faltam cadastro administrativo pela interface, importação das unidades reais, regras definitivas de planta, preços oficiais, confirmação, prazos e preparação de produção. O catálogo atual continua sendo um protótipo.

## Recuperação do Docker

A inicialização do Docker Desktop falhava em sockets temporários. As pastas foram preservadas como `run.before-exclusive-repair`, `run.before-exclusive-repair-2` e `docker-secrets-engine.before-exclusive-repair` nas respectivas pastas locais do Docker. Imagens e volumes não foram resetados. A tentativa de desabilitar Model Runner pela CLI não concluiu; a correção efetiva foi recriar as pastas de sockets.
