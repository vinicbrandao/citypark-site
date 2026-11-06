# Editor de revisão de arquivos

Abra `/exclusive/laboratorio-imagens.html`. O endereço anterior também funciona. O laboratório começa vazio, sem imagens ou ambientes predefinidos. Revisões anteriores salvas neste navegador são preservadas em um projeto separado chamado “Revisão anterior — área social”.

Use **Novo projeto vazio** para iniciar outro estudo com biblioteca de imagens independente. Alterne entre projetos pelo seletor. Cada combinação tem campos para ambiente, unidade/terminação e tipologia, além de perspectiva ou planta baixa. Projetos podem conter várias unidades e ambientes; as imagens importadas ficam disponíveis apenas no projeto correspondente.

1. Use **Importar imagens** para selecionar PNG, JPG ou WebP (extraia arquivos ZIP antes). As imagens entram na biblioteca, desmarcadas em todas as combinações.
2. Crie uma combinação ou duplique uma existente. Preencha nome, ambiente/tipologia, visualização e observações.
3. Marque as camadas e ordene com as setas. A lista começa pelo fundo; cada imagem seguinte fica por cima. A ordem é independente por combinação.
4. Use **Exportar projeto com imagens**. Envie o JSON gerado ao responsável pela implementação; ele contém imagens originais em base64, nomes, dimensões, ordem, visibilidade e observações.
5. Use **Abrir projeto** para retomar um JSON exportado. Ele é validado e adicionado como outro projeto, preservando os projetos já abertos. JSONs da versão anterior continuam aceitos. A exportação inclui o projeto selecionado.

O salvamento automático usa IndexedDB no navegador e endereço atuais; não envia dados ao Supabase. Limpar os dados do navegador pode apagar essa cópia. A exportação é a cópia portátil e funciona em outro navegador. Arquivos grandes aumentam o JSON em aproximadamente um terço devido à codificação base64.

A revisão não aplica alterações ao catálogo de clientes. Perspectiva e planta baixa são metadados de cada combinação; as imagens não são geradas nem modificadas. Camadas com dimensões diferentes geram aviso e são centralizadas sem distorção. O projeto exportado tem formato `exclusive-image-review`, versão 1.
