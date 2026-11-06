# Avisos de prazo — ativos desde 30/10/2026

Publicado e agendado no Supabase oficial grfmiuopojbxxbdymqax. Job único citypark-deadline-reminders ativo com expressão */10 * * * * (a cada dez minutos, durante todo o dia). A fila existente deadline_notifications é reutilizada, sem novas tabelas do aplicativo. A entrega usa o Resend oficial pelo servidor e preserva o SMTP do login.

## Validação oficial concluída

Responsável autorizou publicação/agendamento e teste temporário de 15 dias na 1505 A/Gmail controlado. Chamadas reais sem autenticação ou com token errado retornaram 401. O handler também recusa segredos com menos de 32 caracteres.

Responsável salvou pessoalmente as credenciais. O token aleatório de 64 caracteres foi validado por digest, sem exposição do valor, e coincide nas Edge Functions e no Vault citypark_deadline_reminder_token_v2. O segredo antigo sem sufixo permanece sem uso. Extensões pg_cron 1.6.4 e pg_net 0.20.4 instaladas.

Teste real em 29/10: HTTP 200 com sent=1/failed=0; Resend confirmou Delivered para o Gmail autorizado. Repetição retornou sent=0/failed=0, preservando um único aviso com uma tentativa. Prazo da 1505 A removido após o teste, mantendo o registro enviado. Evidências em outputs/qa/deadline-delivered-gmail-20261029.png e deadline-test-restored-20261029.png.

Em 30/10, consulta inicial confirmou ausência do job; script autorizado executado e retorno confirmou active=true. Nova chamada autenticada retornou HTTP 200, sent=0/failed=0, prazo da 1505 A NULL e apenas o aviso anterior. Evidência: outputs/qa/deadline-schedule-active-20261030.png. A execução natural futura do cron ainda não foi observada nesta conferência. Suíte completa: 41 testes passaram.

## Regras

- Avisos aos 15, 10, 5 e 1 dias, calculados pela data de São Paulo; texto inclui horário e data nesse fuso.
- Aviso geral identifica a unidade; aviso de módulo identifica também seu nome.
- Sem prazo, unidade inativa/concluída ou sem proprietário vinculado: nenhum novo aviso elegível.
- Prazos removidos/alterados não têm seus avisos antigos reclamados para envio.
- Identificação única por unidade/cliente/escopo/data/marco no banco e Idempotency-Key no Resend. Tentativas no mesmo dia mantêm a mesma mensagem e chave; Resend conserva as chaves por 24 horas.
- Falhas não são marcadas como enviadas. Até cinco tentativas diárias, intervalo mínimo de dez minutos e reserva para evitar execução concorrente.
- Sent significa aceito pelo provedor, não confirmação de leitura ou entrega final. Entrega pode ser consultada no Resend.
- Cada execução processa até dez avisos, com limite de tempo de oito segundos por chamada e espaçamento entre pedidos.

## Configuração privada necessária nas Edge Functions

- DEADLINE_EMAIL_PROVIDER: resend
- RESEND_API_KEY: chave de envio da conta oficial, limitada ao subdomínio acesso.cityparkmcz.com.br; pode ser a mesma usada no SMTP, se guardada pela equipe.
- DEADLINE_EMAIL_FROM: City Park Exclusive <nao-responda@acesso.cityparkmcz.com.br>
- DEADLINE_REMINDER_TOKEN: segredo aleatório de pelo menos 32 caracteres, criado pela equipe e exclusivo desse agendamento.

A equipe insere e salva as credenciais diretamente no painel; nunca na conversa, no frontend ou no Git. O mesmo DEADLINE_REMINDER_TOKEN fica no Vault com nome citypark_deadline_reminder_token_v2. Nenhuma chave administrativa do Supabase precisa ser copiada: a função usa a credencial interna do próprio ambiente de servidor.

## Procedimento de implantação e manutenção

1. Publicar deadline-reminders e manter verify_jwt=false: a função exige o segredo exclusivo do agendador antes de acessar a fila. Não aceitar a chave pública do site como autenticação.
2. Configurar os quatro valores acima e o segredo do Vault. Não abrir nem imprimir segredos já existentes.
3. Testar rejeição de chamada sem autenticação e executar com fila vazia.
4. Somente mediante autorização, colocar um prazo de teste na unidade 1505 A para daqui a 15 dias e disparar um único aviso para o Gmail controlado. Confirmar entrega e deduplicação; remover o prazo do teste e preservar o registro do envio. Não cadastrar datas fictícias em outras unidades.
5. Ativar scripts/enable-official-deadline-schedule.sql após aprovação. Verifica a fila a cada dez minutos, ao longo do dia inteiro; cada marco é enviado uma vez. O script recusa agendamento duplicado e token ausente/curto. Não executa automaticamente em migrations nem na instalação inicial.
6. Conferir cron.job, execução e resposta HTTP do pg_net; cron executado não prova sozinho que a função enviou as mensagens. Desativar reversivelmente com cron.alter_job(job_id,active:=false), após identificar o único job pelo nome.

## Validações

Dez testes isolados do worker passaram: autenticação obrigatória, segredo curto, configuração ausente, URL insegura, Resend/identificação e fuso, quatro marcos e módulo, falhas HTTP/rede/recibo, falha no registro com repetição idêntica, fila vazia e transporte local legado. São testes sem rede ou destinatários reais.

As regras da fila possuem testes SQL locais anteriores; Docker indisponível na retomada impediu repeti-los. Entrega real, deduplicação, restauração e configuração ativa foram verificadas no projeto oficial conforme registro acima.

Referências: https://resend.com/docs/dashboard/emails/idempotency-keys e https://supabase.com/docs/guides/functions/schedule-functions.
