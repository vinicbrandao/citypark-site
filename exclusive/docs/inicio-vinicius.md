# Roteiro vigente para Vinícius e Allef

Este plano substitui a ordem de prioridades da passagem de 18/09/2026. Primeiro login, cadastros e calendário por módulo/unidade; atendimento das arquitetas em seguida. As datas finais não são necessárias para começar. As entregas abaixo são propostas de implementação, não funcionalidades prontas.

## Situação para início

- Pronto: GitHub privado, acesso Write de vinicbrandao, código, migrations, seeds fictícios, testes e instruções locais.
- Implementado: login com senha e definição/recuperação por código, vínculos cliente/unidade, rascunhos com revisão e histórico. Concluir teste completo de usuário do fluxo de senha.
- Pendente: projeto Supabase online exclusivo do Exclusive, convite técnico do Vinícius, frontend de homologação e SMTP real.
- Pendente: importação revisada dos compradores, calendários, confirmação final e autorização das arquitetas por unidade.
- Vinícius pode desenvolver agora localmente. O ambiente online compartilhado ainda precisa ser configurado por Allef/TI.

## Primeiro dia do Vinícius

Instalar Git, Node.js compatível com Vite 8 (22.12+ na linha 22) e Docker Desktop com contêineres Linux. Manter Docker iniciado. Entrar no GitHub com sua conta individual.

```powershell
git clone https://github.com/planoa-construtora/citypark-exclusive.git
cd citypark-exclusive
git switch -c feat/acesso-calendarios
npm ci
docker network create -o com.docker.network.bridge.host_binding_ipv4=127.0.0.1 citypark-exclusive-local
npm run db:start
node scripts/seed-local.mjs
node scripts/seed-staff-local.mjs
npm run dev
```

Criar a rede uma única vez. Os seeds aceitam apenas Supabase local e geram .env.local. Não copiar credenciais de Allef. O banco local de cada pessoa é independente.

Abrir http://127.0.0.1:5173/exclusive/ e usar cliente.a@example.test em Primeiro acesso / Esqueci minha senha. Ler o código em http://127.0.0.1:54324/, definir senha fictícia, sair e entrar com senha. Conferir A apenas com 1209A e B apenas com 1210A; salvar, recarregar e conferir escolhas. Studio local: http://127.0.0.1:54323/.

Em outro terminal na raiz:

```powershell
npm test
npm run build
node scripts/test-access-local.mjs
node scripts/test-staff-local.mjs
```

Os testes de integração alteram rascunhos fictícios. Não usar contra dados reais. Após receber migrations novas, executar npx supabase migration up --local. Não executar reset em banco com conteúdo a preservar.

Entrega do dia: demonstração de login/salvamento e resultados dos testes, incluindo impedimentos. Ler src/main.js, app.js, supabase/migrations e scripts de teste antes de alterar.

## Entrega A Login e cadastros

1. Aproveitar o login existente. Testar primeiro acesso, senha correta/incorreta, código inválido/expirado, recuperação, cancelamento, logout e retorno ao configurador somente após definir a senha.
2. Preparar importador com modo de prévia sem escrita nem convites. Mostrar registros aceitos, repetidos e pendentes, motivo e linha de origem. Não enviar dados pessoais ao Git ou aos logs.
3. Campos: cliente, e-mail e unidade; complementar torre, pavimento numérico, terminação, tipologia e data da compra quando disponíveis. Campos ausentes ficam pendentes.
4. Não fundir pessoas por e-mail compartilhado, descartar coproprietários ou inferir data de compra. Allef revisa o relacionamento antes da carga.
5. Repetir o mesmo lote não pode duplicar clientes, vínculos ou contas. Convites são uma ação posterior explícita.

## Entrega B Planejamento e calendário dos módulos

Modelar módulos e lotes da obra, com associação explícita das unidades abrangidas. Filtros de torre/pavimento ajudam a selecionar, mas mudanças no cadastro não devem mudar silenciosamente o alcance de um prazo publicado.

Separar três coisas: data de compra do apartamento; previsão de compra parcial de materiais; janela efetiva de escolhas do cliente. Não criar prazo automaticamente pela data de compra do apartamento.

| Cadastro | Conteúdo proposto |
| --- | --- |
| Módulo | Identificador e nome, por exemplo alterações de planta |
| Lote | Nome, módulo e unidades abrangidas |
| Planejamento | Abertura, encerramento, compra parcial e execução previstos; datas opcionais |
| Publicação | Abertura e encerramento efetivos, versão, responsável e momento da publicação |
| Histórico | Antes/depois, autor e motivo de mudanças |

### Regras de implementação

- Calendário começa em rascunho. Permitir datas vazias ou prévias para administração. Não presumir ano para março/junho.
- Previsão não libera módulo. Publicação exige administrador, unidades selecionadas e datas válidas. A interface deve distinguir previsão de prazo vigente.
- Sem calendário publicado: aguardando calendário, sem aceitar escolhas operacionais ou confirmação. Datas fictícias somente em testes identificados.
- Usar relógio do servidor: antes da abertura, aguardando; abertura inclusive até encerramento exclusive, aberto; no encerramento e depois, encerrado.
- Mostrar America/Sao_Paulo; armazenar timestamps com fuso. Se o prazo for até o fim de um dia, utilizar início do dia seguinte como limite exclusivo e explicar isso na tela.
- Após encerramento, manter consulta e bloquear gravação/confirmação no banco. Esconder botão ou confiar no relógio do navegador não basta.
- Rejeitar calendários publicados conflitantes para a mesma unidade/módulo e datas invertidas.
- Revisar uma previsão não altera a janela vigente. Mudança de prazo publicado exige ação explícita, motivo e histórico.
- Não reabrir automaticamente para venda tardia. Exceções dependem de regra aprovada; arquitetas não contornam prazo.

Atenção: save_unit_draft hoje grava seis seleções juntas. Encerrar planta não pode impedir salvar bancadas abertas nem permitir que salvar bancadas altere planta encerrada. Comparar campos antigos/novos por módulo ou separar rascunhos numa migration revisada. Definir a associação dos seis campos a módulos e testar ambos os casos.

## Entrega C Painel mínimo

Administrador cria planejamento, seleciona unidades e publica datas efetivas. Cliente vê módulos abertos, aguardando ou encerrados para cada unidade.

Rascunho salvo não é solicitação confirmada. Não renomear Salvar progresso para confirmação/compra. Confirmação final permanece pendente e deverá registrar versão de escolhas e orçamento no servidor. Não liberar contratação com preços fictícios.

Autorizações das arquitetas e validação técnica vêm depois. As políticas de architect ativo ainda são amplas. Manter as arquitetas reais inativas até a restrição por unidade estar implementada.

## Ações paralelas de Allef e TI

1. Criar projeto Supabase exclusivo de homologação do Exclusive; não reutilizar planoa-si-db. Definir organização e responsável.
2. Convidar conta individual do Vinícius com permissão técnica adequada ao plano e ao escopo. Acesso ao painel Supabase é diferente de login no Exclusive.
3. Um responsável aplica migrations revisadas no projeto correto. Conferir identificador antes de vincular CLI ou alterar remoto. Não executar reset ou seeds locais no remoto.
4. Preparar endereço do frontend de homologação, URLs de Auth, cadastro público desabilitado, SMTP e modelos de e-mail. Testar com conta controlada antes de convidar clientes. Criar banco online não compartilha o site 127.0.0.1.
5. No frontend usar só URL/chave publicável. Service role e SMTP ficam em configuração secreta do backend, nunca no Git.
6. Compartilhar relatório de clientes por canal corporativo restrito. Allef aprova a prévia antes da importação; desenvolvimento diário usa dados fictícios.
7. Continuar Revit/laboratório e fornecer agrupamentos e datas como prévias quando disponíveis. O sistema aceita planejamento incompleto.

Homologação não é produção. Enquanto TI prepara o ambiente compartilhado, Vinícius progride localmente. A futura implantação no servidor corporativo continua pendente de avaliação.

## Cinco dias de trabalho sugeridos

| Dia | Vinícius | Allef e TI |
| --- | --- | --- |
| 1 | Instalar, testar e demonstrar login | Organizar homologação e conta de envio |
| 2 | Propor migrations e prévia de importação | Revisar regras e correspondência cliente/unidade |
| 3 | Implementar calendário e bloqueios no banco | Informar agrupamentos preliminares e avançar Revit |
| 4 | Painel mínimo e integração dos estados | Testar homologação quando disponível e revisar imagens |
| 5 | Demonstrar cenários e abrir PR | Validar entregas e registrar pendências |

É um roteiro, não promessa de concluir tudo em cinco dias. Se atrasar, priorizar cadastros corretos, login e regras do banco testadas antes de ampliar telas.

## Como Allef acompanha e aceita

Pedir atualização diária: concluído, evidência, impedimento e próximo passo. Exigir demonstração com dados fictícios:

- Um cliente com duas unidades e prazos diferentes.
- Calendário sem datas e apenas previsto não liberam acesso.
- Unidade aberta e encerrada respeitadas também na API.
- Planta encerrada não bloqueia bancada aberta; salvar bancada não altera planta encerrada.
- Mudar relógio do computador não reabre módulo.
- Cliente não altera calendário nem acessa unidade alheia; arquiteta não altera preços ou calendário.
- Conflitos de lote e datas invertidas são rejeitados.
- Importação repetida não duplica e linhas sem e-mail ficam pendentes.
- Rascunho e confirmação permanecem distintos.

## Entrega e revisão no GitHub

Branch por tarefa, commits pequenos e PR para main. Entregar novas migrations, testes, instruções e limitações. Não editar migrations publicadas. Mudanças de autorização passam por revisão técnica antes de integrar. Não enviar dados reais, tokens, backups ou JSONs grandes de imagens.

Preferir PRs separados para login/prévia de importação, regras de calendário e painel mínimo. O objetivo é demonstrar: pessoa certa, unidade certa, módulo certo e janela publicada, mesmo com planejamento ainda incompleto.

## Etapas após os primeiros cinco dias

A sequência abaixo é o plano de evolução, não uma declaração de funcionalidades entregues. As durações são estimativas iniciais em dias úteis de desenvolvimento, com revisão disponível; recalibrar no encerramento do Dia 5. Pendências dos critérios anteriores devem ser resolvidas antes de liberar a etapa dependente. A TI pode preparar infraestrutura em paralelo.

### Marco inicial Revisão do Dia 5

Allef e Vinícius demonstram o fluxo de acesso, prévia de importação e calendário com dados fictícios. Registrar o que passou, falhou e ficou pendente. Só considerar a base concluída quando as regras funcionarem também pela API. Se homologação/SMTP ainda não estiverem disponíveis, avançar em desenvolvimento local sem considerar o envio real validado.

### Etapa 1 Atendimento assistido e validação técnica

Estimativa: 3 a 5 dias úteis após a base de acesso estar validada.

- Vinícius implementa autorização de uma arquiteta por unidade, concessão pelo cliente e revogação. A autorização não concede poder para confirmar custos em nome do cliente.
- Administrador poderá registrar autorização recebida fora do sistema, com referência à evidência em armazenamento privado. Definir com Allef quem pode consultar essa evidência e por quanto tempo será mantida.
- Substituir o acesso amplo atual de architect ativo por políticas de leitura e escrita limitadas às unidades autorizadas. Atualizar os testes de equipe existentes; testar sessão já aberta após revogação.
- Implementar validação técnica de uma revisão específica, com profissional, data e observação. Alteração das escolhas exige nova validação, preservando a anterior no histórico.
- Allef e arquitetas revisam o processo, inclusive se a mesma profissional pode montar e validar as escolhas ou se haverá uma segunda revisora. Não presumir essa regra.

Aceite: uma arquiteta autorizada atende somente a unidade permitida; não altera preço nem prazo; revogação bloqueia novas operações; validação antiga não aprova escolhas novas. Só então ativar arquitetas reais.

### Etapa 2 Catálogo técnico e orçamento confiável

Estimativa: 4 a 7 dias úteis, dependendo das definições de Allef. A preparação dos dados pode ocorrer em paralelo à etapa 1.

- Allef entrega opções por tipologia/unidade, quantitativos do Revit, acabamentos, dependências técnicas e composições exportadas do laboratório. Identificar o que ainda não foi renderizado.
- Vinícius leva o catálogo e as regras para o banco, com versões e edição de preços exclusiva de administradores. Calcular valores no backend; não aceitar total calculado pelo navegador como autoridade.
- Definir preço por item, unidade de medida, quantidade, configuração padrão e adicional. Formalizar com Allef o tratamento de descontos, diferenças negativas e alterações de tabela de preços.
- Vincular imagens às opções validadas sem alterar o significado de rascunhos existentes. Imagens faltantes continuam sinalizadas; não representar uma composição incompleta como pronta.
- Preservar a versão do orçamento apresentado. Mudança de preço não altera silenciosamente uma proposta já confirmada.

Aceite: um conjunto de unidades representativas confere com orçamento manual aprovado por Allef; tentativas de adulterar total, quantidade ou preço pelo cliente são rejeitadas; arquiteta continua sem edição de preços. Encerrar uso operacional de valores fictícios antes de contratar.

### Etapa 3 Confirmação do cliente e fechamento por lote

Estimativa: 3 a 5 dias úteis, após catálogo/orçamento e validação técnica confiáveis.

- Separar os estados rascunho, aguardando validação técnica, validado, confirmado pelo cliente e encerrado para alterações. O calendário e o estado do pedido são informações distintas.
- Definir se validação técnica é requisito antes de confirmar, se haverá período de correção e como uma pendência será tratada no encerramento. Allef aprova essas regras antes da implementação.
- Mostrar ao cliente itens, quantitativos, total e condições aprovadas pela empresa antes da confirmação. Registrar no servidor autor, instante, revisão das escolhas e versão do orçamento.
- Impedir confirmação duplicada, fora do prazo ou de revisão desatualizada. Não tratar salvamento de rascunho como compra.
- Formalizar cancelamento, reabertura e exceção para venda tardia, sempre com responsável, motivo e histórico. Definir eventual assinatura/aceite com o setor responsável; não presumir que um clique atende a todos os requisitos contratuais.
- No encerramento de um lote, congelar uma versão dos pedidos para preparação da compra. Rascunhos e pedidos não confirmados não entram automaticamente na compra.

Aceite: cliente confirma exatamente a versão que revisou, dentro da janela autorizada; alterações posteriores exigem fluxo explícito; equipe consegue identificar quais unidades estão prontas para a compra parcial.

### Etapa 4 Relatórios para compras e execução

Estimativa: 2 a 4 dias úteis, após estabilizar as confirmações.

- Consolidar pedidos confirmados por lote, torre, pavimento, unidade, módulo, opção, material e quantidade, com referência à versão da seleção.
- Separar relatório de compra de materiais do relatório de execução por unidade. Mostrar pendências, unidades sem confirmação e padrões aplicáveis sem converter silêncio em compra.
- Gerar exportação conferível pela equipe de orçamento e obra. Registrar emissão/versão para comparar correções posteriores.
- Allef confere totais e uma amostra por unidade; compras e obra validam que os campos permitem executar o trabalho.

Aceite: os totais consolidados reconciliam com os pedidos individuais e a revisão congelada do lote; nenhum rascunho ou item cancelado aparece como contratação confirmada. Esta etapa é indispensável para apoiar a compra parcial de drywall.

### Etapa 5 Piloto controlado e preparação de produção

Reservar uma janela de 5 a 10 dias úteis para observar o piloto, além do tempo necessário às correções. Não é promessa de lançamento nessa data.

- Antes de convidar pessoas reais: homologação acessível, SMTP testado, regras de acesso revisadas, preços aprovados, backup e restauração demonstrados e nenhum defeito conhecido que permita acesso indevido.
- Allef escolhe um grupo pequeno e autorizado que cubra tipologias e situações diferentes. Iniciar com simulação claramente identificada; contratação real somente após aprovação formal do processo pela empresa.
- Verificar uso no celular, primeiro acesso, recuperação, atendimento assistido, leitura das opções, prazos, validação, confirmação e relatórios. Registrar falhas e dúvidas com responsável e prioridade.
- TI decide destino de produção: Supabase hospedado ou implantação própria no servidor. Se houver transferência, ensaiar estrutura, dados, Auth, arquivos e configurações em ambiente separado; preparar corte e retorno.
- Definir responsável por suporte, mudanças de e-mail, bloqueio de conta, manutenção, restauração e acompanhamento dos prazos da obra.

Aceite: cenários representativos concluídos, falhas impeditivas corrigidas, restauração testada e aprovação de Allef/TI antes de expandir convites. Dados fictícios não devem entrar na produção.

## Responsabilidades e acompanhamento após o Dia 5

| Responsável | Entrega recorrente |
| --- | --- |
| Vinícius | Implementação em PRs pequenos, migrations, testes e demonstração por etapa |
| Allef | Regras da obra, quantitativos, preços validados, agrupamentos/prazos e aceite funcional |
| Arquitetas | Critérios de validação e teste do atendimento assistido |
| TI | Homologação, SMTP, servidor, segredos, backups e operação |
| Revisor técnico | Revisão de permissões, funções privilegiadas e integridade dos dados antes de integrar |

Se não houver revisor técnico disponível, o estagiário mantém as mudanças em homologação até uma revisão adequada. A aprovação funcional de Allef não substitui a verificação técnica das permissões.

Ao final de cada etapa, registrar: demonstração, critérios aprovados, pendências, responsável e próximo marco. Definir datas de entrega após medir a primeira semana. Não somar as estimativas como compromisso fechado: definições técnicas, infraestrutura e correções podem alterar a sequência.

O resultado esperado antes da compra parcial é um fluxo completo e rastreável: unidade autorizada, janela publicada, escolha tecnicamente validada, orçamento aprovado, confirmação do cliente e relatório de compra por lote. O planejamento preliminar pode ser programado agora; a publicação dos prazos depende da decisão da obra.
