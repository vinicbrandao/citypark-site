# Site CityPark com módulo Exclusive — teste local

O site comercial permanece na raiz deste repositório e continua usando Firebase. O código e as migrations do Exclusive estão em `exclusive/` e continuam usando Supabase. As contas e os bancos não são compartilhados.

## Iniciar

Requisitos: Node.js 22.12+ e, para login e dados de teste do Exclusive, o Supabase local já configurado com Docker.

```powershell
cd C:\citypark-site
npm ci --prefix exclusive
npm run dev
```

- Site comercial: `http://127.0.0.1:5173/`
- Exclusive: `http://127.0.0.1:5173/exclusive/`
- Laboratório do Exclusive: `http://127.0.0.1:5173/exclusive/laboratorio-imagens.html`

`npm run dev` serve o site comercial e executa o Vite do Exclusive na mesma origem, com atualização automática durante as edições. O Exclusive lê `exclusive/.env.local`, ignorado pelo Git. Este comando não usa `.env.official.local` nem inicia ou altera bancos.

Para iniciar o Supabase local pela primeira vez, siga [o README do Exclusive](exclusive/README.md). Se ele já estiver em execução, não repita os comandos de seed. Os comandos e testes do Exclusive também podem ser executados em `exclusive/` como antes.

O build independente continua disponível com `npm run build:exclusive`. Ele gera `exclusive/dist/`, sem publicar arquivos. Firebase e Supabase permanecem separados; nenhuma implantação ou migração de dados faz parte desta integração local.

## Validar localmente

```powershell
cd C:\citypark-site
npm test
npm run test:exclusive
npm --prefix exclusive run test:db-local
```

O teste de interface do configurador pode ser executado com `npm --prefix exclusive run test:customizer-layout-local` quando o Playwright estiver disponível. Os testes SQL executam suas fixtures em transações revertidas. Os roteiros antigos de jornada completa que apagam fixtures se recusam a rodar no modelo atual com histórico imutável; não remova essa proteção.

## Conectar ao Supabase oficial

A configuração privada em `exclusive/.env.official.local` usa o projeto `https://grfmiuopojbxxbdymqax.supabase.co` e permanece fora do Git. Para abrir o site unificado com o Exclusive nesse projeto:

```powershell
cd C:\citypark-site
npm run dev:official
```

Acesse `http://127.0.0.1:5175/exclusive/`. Alterações feitas nessa interface atingem o banco oficial. O comando `npm run dev` continua usando o Supabase local em `127.0.0.1:5173` para testes. Para gerar um build oficial sem publicar, use `npm run build:exclusive:official`.

## Integração de status comercial

O arquivo `apps-script/ExclusiveInventario.gs` usa a credencial do Apps Script para ler a coleção operacional de unidades do Firebase. Ele envia apenas identificação, status, destinação e data da venda para a Edge Function `commercial-inventory`. O gatilho de dez minutos é independente do fluxo comercial e sua instalação é explícita.

O envio usa as propriedades `EXCLUSIVE_INVENTORY_ENDPOINT` e `EXCLUSIVE_INVENTORY_TOKEN` do Apps Script. A Edge Function confere o mesmo segredo por meio de `COMMERCIAL_INVENTORY_TOKEN`. Use um token exclusivo para essa função. O frontend não precisa receber esse token.

A migration `20261105000100_commercial_inventory.sql` cria o inventário privado e mantém a regra desligada por padrão. Com a regra ligada, o cliente precisa ter vínculo válido, a unidade precisa estar ativa e a última leitura operacional do Firebase precisa indicar `vendida`, inclusive quando a destinação estiver vazia. A equipe do Exclusive trata exceções mantendo a unidade inativa ou administrando o vínculo do proprietário. A sincronização não modifica ativações, vínculos ou personalizações.

Antes de ativar, compare o inventário com `node scripts/conferir-unidades-comercial.mjs <inventario-comercial.json>` e confira códigos ausentes e duplicados. Em teste, use um inventário fictício e a migração em um banco local separado. Se o Firebase ficar indisponível, o Exclusive mantém o último status confirmado. Se a venda for desfeita ou a data da venda mudar, o administrador deve conferir o cliente vinculado e confirmá-lo em **Gerenciar** após a unidade voltar a ser elegível.