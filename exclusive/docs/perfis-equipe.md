# Equipe — ambiente local

Perfis `admin` e `architect` persistidos em `staff_users`, separados dos vínculos de compradores. Apenas provisionamento com service role pode atribuir ou revogar esses perfis; nenhum usuário pode promover a própria conta.

Contas fictícias provisionadas sem envio de convites:

- admin.1@example.test
- admin.2@example.test
- admin.3@example.test
- architect.1@example.test
- architect.2@example.test

Entram pelo mesmo login por código, capturado no Mailpit local. As identidades reais aguardam os nomes e e-mails fornecidos pelo usuário.

Ambos os perfis ativos consultam as unidades ativas e salvam escolhas em atendimento. `draft_history` registra revisão, seleção, ator e perfil em cada salvamento. O cliente mantém acesso restrito aos vínculos anteriores. Revogação bloqueia novas operações de equipe no banco, mesmo com sessão já aberta.

O RPC permite apenas as seis seleções do catálogo; campos de preço, total e aprovação são rejeitados. O catálogo de preços ainda é fictício e está no código; não há editor de preços para nenhum perfil nesta etapa. Quando criado, sua escrita deve ser exclusiva de administradores no banco.

A aprovação ainda aguarda definição: validação técnica ou confirmação em nome do cliente. Nenhuma confirmação contratual ou aprovação foi criada automaticamente. O painel administrativo completo de cadastro e gestão de acessos também permanece como trabalho seguinte.

Relatório recebido: `Relatorio clientes 17-09-2026.xlsx`, aba Relatório, cabeçalhos nas linhas 7 e 162. Conferência inicial identificou 124 linhas com unidade e nome, 120 códigos de unidade distintos e 8 dessas linhas sem e-mail. As demais 116 têm formato simples de e-mail válido; isso não valida titularidade ou entrega. O arquivo contém também endereço, nascimento, estado civil, profissão e telefone, campos não necessários para provisionamento de login. Nenhum comprador foi importado ou convidado nesta etapa. Ainda é necessário conciliar linhas repetidas/coproprietários e completar tipologia/andar/torre antes de importar unidades sem inferências.

Verificação: `node scripts/test-staff-local.mjs`, `node scripts/test-access-local.mjs`, `npm test` e `npm run build`. Scripts de equipe só usam o Supabase local, por meio de `localEnvironment`.
