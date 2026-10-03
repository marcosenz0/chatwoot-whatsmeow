# Prévias nativas do Instagram — 03/10/2026

## Comportamento

A prévia padrão de publicações usa um cartão do próprio Chatwoot, com cores do tema atual, capa e detalhes públicos disponíveis. O clique de ampliação abre a galeria interna. A conversa não contém mais um iframe passivo com barra de rolagem inacessível. Na galeria, a rolagem própria aparece somente quando necessária e herda a barra compacta global do Chatwoot.

O menu da mensagem contém **Converter para link** e **Mostrar prévia**. A alternância é local à visualização; não altera o conteúdo recebido, não envia mensagens e volta ao padrão de prévia ao remontar a mensagem. O endereço exibido é o permalink canônico, sem parâmetros de rastreamento.

Links de perfil recebidos como mensagem de texto isolada também usam cartão. Nome, foto, descrição/bio e até seis fotos recentes aparecem apenas quando fornecidos pela página pública/incorporação. Uma foto disponível pode ser ampliada dentro da galeria. Dados ausentes não são inventados e não são interpretados como ausência de publicações no perfil.

Vídeos recebidos como arquivo preservam o player interno. A prévia também suporta controles nativos quando os metadados públicos fornecem uma fonte de vídeo diretamente reproduzível. Compartilhamentos que fornecem apenas permalink/capa mantêm uma opção explícita de tentar o player do Instagram na galeria, além do link para abrir o original.

## Implementação e limites

`Instagram::PreviewService` lê Open Graph e elementos públicos do HTML de publicação/perfil e da incorporação. Usa `SafeFetch`, limite de tamanho, prazo de leitura e cache de cinco minutos. Fontes de imagem/vídeo ficam restritas a hosts CDN da Meta. Não usa cookies da sessão do navegador nem endpoints privados do Instagram.

O endpoint exige acesso à conversa e aceita somente um permalink que já pertença à mensagem solicitada. URLs de perfil e publicações são normalizadas separadamente; caminhos de reels no plural e com prefixo de autor também são reconhecidos. A correção anterior que impede salvar páginas HTML como vídeo foi mantida.

A incorporação do Instagram pode rejeitar uma publicação que ainda abre para um usuário autenticado. A nova apresentação não afirma que esse conteúdo foi removido. Em um dos exemplos reais, a capa foi recuperada pela página pública apesar da falha da incorporação.

Os dois reels usados para a verificação real forneceram capas, mas não uma fonte direta de vídeo. O perfil compartilhado não forneceu foto/bio/publicações para a consulta pública. Esses casos continuam limitados pela disponibilidade de dados na Meta: o cartão explica a limitação e mantém o original acessível. O player opcional continua sendo conteúdo de terceiros, com aparência e disponibilidade controladas pelo Instagram. Compartilhamentos marcados `is_unsupported` que não possuem link nem anexo continuam sem dados suficientes para reconstrução.

A [documentação oficial da Meta](https://www.postman.com/meta/workspace/instagram/documentation/23987686-9386f468-7714-490f-9bfc-9442db5c8f00) descreve o recebimento de compartilhamentos com somente a URL. A experiência completa do aplicativo autenticado não é garantida pela integração de mensagens.

## Validação

[PR #30](https://github.com/marcosenz0/chatwoot-whatsmeow/pull/30), código `fa701c6257abf419c882eeb1d6a43f37f9b04fca`, [canário 37124033183](https://github.com/marcosenz0/chatwoot-whatsmeow/actions/runs/37124033183).

- 180 testes JavaScript em 21 arquivos; 455 exemplos Rails sem falhas; 25 arquivos Ruby sem infrações. Lint dos arquivos JS/Vue alterados sem erros, com um aviso preexistente de chave dinâmica no menu Whatsmeow.
- Na principal, os dois cartões carregaram capas reais; um também obteve o avatar público. Fundo nativo confirmado em `rgb(28, 29, 32)`, sem iframe na prévia padrão.
- Converter para link, retornar à prévia, ampliar e fechar a galeria foram verificados no navegador. A galeria usou `overflow-y: auto`, `scrollbar-width: thin` e rolagem efetiva; a conversa manteve `overflow-y: hidden` nos cartões sem barra interna.
- As três notas privadas históricas usadas exclusivamente para os testes da principal foram removidas, mantendo a atividade da conversa inalterada. Não houve envio externo.
- O perfil sem dados públicos permaneceu com nome de usuário/link e explicação da limitação, sem fotos ou bio inventadas.
- Após a publicação no MD, a verificação Rails confirmou a versão nova, os avatares dos contatos das caixas Clara/Emilly e os arquivos de áudio armazenados. A tentativa de recarregar e conferir visualmente o MD não terminou: a conexão de automação do navegador excedeu o prazo, inclusive ao retomar a documentação. A validação visual foi concluída na principal; não foi obtida uma captura final do MD.
- O fluxo canário específico passou. O lint geral do repositório ainda contém falhas preexistentes; não foi considerado uma validação integral verde do repositório.

## Publicação

Publicação concluída em sequência: principal validada primeiro, depois MX e MD. Os seis serviços web/Sidekiq usam a mesma imagem abaixo. Os três domínios responderam HTTP 200 na auditoria final:

`ghcr.io/marcosenz0/chatwoot-whatsmeow:fork-fa701c6257abf419c882eeb1d6a43f37f9b04fca`

Docker ImageID: `sha256:7aefeef2d7e05358d9998192f364c55f5bbe5078d7730b28463e8d90a0169db2`.

Principal manteve inboxes 27/15/28 conectadas e 23/10 previamente desconectadas. MX manteve a inbox pessoal 1 conectada. Os serviços Go não foram atualizados; bancos, sessões, segredos e armazenamento continuam separados. Chatwoot oficial fora do escopo.

Os três serviços Go conservaram a imagem `whatsmeow-54aae63ad477bc6d5bf0077a091a1a9ac7c0efa2` e seus containers. Os mounts de armazenamento de web/Sidekiq foram preservados, incluindo o armazenamento compartilhado de cada par na principal e no MD.

A documentação anterior em `docs/instagram-reels-posts-2026-10-02.md` descreve o primeiro rollout baseado em iframes. Este documento substitui a apresentação padrão e explicita que o sucesso de um reel no player incorporado não garante reprodução para todos os compartilhamentos.
