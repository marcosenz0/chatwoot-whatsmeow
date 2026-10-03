# Prévias de reels e posts do Instagram — 02/10/2026

## Implementação

Os compartilhamentos com permalink de publicação (`/p/`, `/reel/` ou `/tv/`) usam a visualização incorporável do Instagram. A prévia na conversa é passiva: clicar abre a galeria dentro do Chatwoot. Na galeria, o conteúdo fica maior e os controles da incorporação permitem reproduzir o reel. A ação de abrir o Instagram é um link separado e explícito.

Vídeos recebidos como arquivo mantêm o player e ganham um botão visível de ampliação para a galeria existente. Mídias sem URL ou que falham deixam de mostrar um player preto sem explicação.

O recebimento preserva permalinks sem baixar HTML como se fosse vídeo. Anexos já existentes com permalinks também usam a prévia, inclusive quando o blob HTML antigo está ausente. Arquivos de mídia baixados usam o armazenamento persistente, evitando depender de URLs temporárias da Meta. Áudios e fotos de remetentes continuam no fluxo publicado anteriormente.

Somente domínios exatos do Instagram e caminhos de publicações são aceitos para incorporação. Links de perfis e URLs de outros serviços não são transformados em frames. Não há scraping, download de vídeos a partir de páginas ou junção de identidades entre caixas.

## Limitações

O conteúdo precisa estar disponível para incorporação no Instagram. Conteúdo removido, privado ou com incorporação desativada pode não carregar; a opção de abrir o original permanece disponível quando há link. O player incorporado depende da Meta e não produz uma cópia persistente do reel.

Compartilhamentos de perfil que chegam com `is_unsupported`, sem mídia nem link, não podem ser reconstruídos. O aviso existente permanece. Uma mensagem antiga sem endereço também não recebe um link inventado.

## Validação e publicação

Em preparação no worktree `codex/instagram-media-preview`, a partir de `fac9690bd9`. Alvos autorizados: principal primeiro, depois MX e MD com a mesma imagem fixada. Bancos, armazenamento, segredos e sessões permanecem separados. Serviços Go e Chatwoot oficial fora do escopo.
