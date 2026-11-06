# Perspectiva da área social

Arquivos recebidos em `sala opçãoes.zip`, preservados sem alteração visual em `assets/planta/social/`.

Todas as imagens têm 5000 × 1770 pixels e canal de transparência. Devem compartilhar o mesmo quadro e escala, sem recortar as bordas transparentes: essas bordas posicionam corretamente cada camada sobre a imagem base.

| Original | Arquivo no projeto | Conteúdo |
| --- | --- | --- |
| 01 base sala.png | base-sala.png | Imagem base da perspectiva |
| 02 piso cemente nebbia.png | piso-cemente-nebbia.png | Camada de acabamento |
| 03 NANTES BEIGE.png | piso-nantes-beige.png | Camada alternativa de acabamento |
| 04_OPÇÃO 02.png | opcao-02.png | Camada de alteração de paredes |
| 05_OPÇÃO 03.png | opcao-03.png | Camada de alteração de parede |
| EUROGLASS.png | euroglass.png | Camada do fechamento envidraçado |

## Diretriz de visualização

A perspectiva será a visualização padrão. A futura planta baixa deverá representar as mesmas escolhas, sem criar outra configuração ou alterar o preço ao trocar a visualização. A situação do pavimento existente não equivale a uma planta baixa das modificações.

## Associações pendentes

### Catálogo confirmado — três quartos

1. Padrão, sem Euroglass (`social-original`).
2. Padrão + Euroglass (`social-standard`, identificador anterior preservado para não alterar rascunhos existentes).
3. Integração da sala com varanda, remoção da porta da cozinha para a varanda e fechamento desse vão com alvenaria + Euroglass (`social-veranda`).
4. Integração da sala, varanda e cozinha, remoção da bancada da varanda e adição de ilha + Euroglass (`social-full`).

A ilha da quarta opção ainda não foi renderizada, conforme confirmado pelo usuário. As quatro opções são do catálogo de três quartos; isso não confirma que a perspectiva recebida sirva a todas as terminações. Os preços atuais continuam fictícios para teste.

As plantas recebidas indicam forro vinílico opcional na sala na terceira opção; na quarta, vinculam o forro vinílico na sala, cozinha e varanda e o granito da ilha ao da bancada. Essas dependências ainda precisam ser implementadas nos módulos de acabamento e quantitativos.

### Composição das imagens

- Padrão: base + OPÇÃO 02. Falta a esquadria entre sala e varanda.
- Padrão + Euroglass: base + OPÇÃO 02 + EUROGLASS. Falta a mesma esquadria.
- Sala + varanda: falta a camada da parede e do vão da porta de alumínio cozinha-varanda; por enquanto é exibida apenas a base com Euroglass e aviso de prévia parcial.
- Integração completa: base + OPÇÃO 03 + EUROGLASS. OPÇÃO 03 substitui OPÇÃO 02. Falta a ilha e a retirada visual da bancada da varanda.
- A abrangência por terminação da perspectiva ainda está pendente.

Correspondências confirmadas pelo usuário e registradas no manifest. As quatro composições permanecem parciais. Os acabamentos recebidos não introduzem preços nem escolhas contratuais de piso.
