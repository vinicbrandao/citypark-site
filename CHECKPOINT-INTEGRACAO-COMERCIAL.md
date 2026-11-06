# Checkpoint da integração comercial com o Exclusive

Atualizado em 05/11/2026. Pasta de trabalho: `C:\citypark-site`.

## Estado confirmado

- O projeto oficial `grfmiopojbxxbdymqax` é o ambiente de testes do Exclusive. Abra o site com `npm run dev:official` na raiz. O Exclusive fica em `http://127.0.0.1:5175/exclusive/`.
- O Supabase oficial está com 28 migrations. O backup privado de esquema e dados foi feito antes da atualização em `exclusive/outputs/deployment/grfmiuopojbxxbdymqax/backup-pre-integracao-20261105-163849/`.
- As funções `admin-customer`, `admin-staff` e `commercial-inventory` foram publicadas no Supabase oficial. O administrador confirmou que o painel funciona. O receptor de inventário recusou a chamada sem o segredo dedicado.
- A regra comercial está **ligada** no Supabase oficial. A leitura manual de 05/11 às 17:14 (São Paulo) cruzou as 389 unidades por código e torre. O resultado conferido no banco foi **151 elegíveis e 238 bloqueadas por status comercial**.
- A **1505A** constava como Disponível no Firebase e ficou bloqueada para personalização pelo cliente. O cadastro da unidade e o vínculo da conta de teste foram preservados.

## Regras em vigor

- O status operacional `vendida` torna a unidade elegível, inclusive com destinação vazia. A equipe ativa a unidade e vincula o proprietário no Exclusive. A regra não altera prazos ou personalizações concluídas.
- Se uma revenda for detectada, o administrador confere o vínculo e usa **Confirmar proprietário vinculado** em **Gerenciar**. A confirmação fica no histórico.
- Se a sincronização falhar, vale a última leitura confirmada. Vendas sem data preenchida podem dificultar a detecção de uma revenda ocorrida entre duas leituras.

## Próxima etapa

Instalar o envio automático no projeto Apps Script comercial. Adicionar `apps-script/ExclusiveInventario.gs`, configurar o endpoint e o segredo dedicado nas propriedades do script e executar `sincronizarInventarioExclusive` manualmente. Após confirmar o recebimento no Supabase, instalar o gatilho de dez minutos com `instalarGatilhoInventarioExclusive` e verificar uma execução automática.

**O gatilho ainda não está instalado.** Até lá, o acesso reflete a última leitura manual. O [guia da integração](INTEGRACAO-EXCLUSIVE.md) descreve a configuração do receptor.
