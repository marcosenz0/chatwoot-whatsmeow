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

[PR #29](https://github.com/marcosenz0/chatwoot-whatsmeow/pull/29), código `c583db06f3f7240c580e4f8fce4eb227f7e99e2a`, [canário 37089523220](https://github.com/marcosenz0/chatwoot-whatsmeow/actions/runs/37089523220). Publicação realizada primeiro na principal, depois MX e MD, com a mesma imagem nos seis serviços web/Sidekiq:

`ghcr.io/marcosenz0/chatwoot-whatsmeow:fork-c583db06f3f7240c580e4f8fce4eb227f7e99e2a`

Docker ImageID comum: `sha256:f28541c09f45468e378455bac8a1e7f28af0935fb0bb96fe85266dfedb7ab403`. Manifesto: `sha256:700ca170b841af13b8a84cdfc0b1470a6002188bd9c249b4ad448b28aed7dc88`.

- 168 testes JavaScript em 19 arquivos, 437 exemplos Rails sem falhas e 19 arquivos Ruby sem infrações. Lint dos arquivos de interface alterados aprovado. As verificações gerais herdadas do repositório não são apresentadas como verdes.
- Na principal, a prévia abriu a galeria sem navegar para fora do Chatwoot. Um reel público reproduziu no frame ampliado, com duração de 11,398 segundos e `readyState=4`. A rota de publicação `/p/` também abriu a incorporação. Imagem armazenada abriu na galeria; vídeo armazenado carregou 13,696 segundos e reproduziu no visualizador de 1552 × 796, mantendo a proporção. A incorporação vertical pode ter rolagem própria, conforme o formato fornecido pelo Instagram.
- As quatro notas privadas históricas criadas exclusivamente para validar a principal foram removidas após os testes. Não houve envio externo, e a atividade da conversa permaneceu inalterada.
- No MD, os anexos antigos das mensagens 22 e 23 foram reconhecidos como permalinks de reels sem baixar novamente o HTML. A mensagem 21 não tem URL; mensagens 24 e 27 continuam não suportadas e sem anexos. A navegação da galeria ignora anexos sem endereço. Os áudios e avatares das conversas de Clara e Emilly permanecem armazenados.
- A aba existente do MD foi recarregada e confirmou as prévias no histórico real da Emilly. O reel da mensagem 23 abriu na galeria, carregou duração de 11,398 segundos e iniciou a reprodução. Abas temporárias abertas durante o reinício demoraram a carregar os assets; foram encerradas, e a conferência foi concluída na aba existente. Os arquivos do dashboard responderam HTTP 200 também a partir do computador do usuário.
- Os três domínios responderam HTTP 200 após a inicialização. A revisão foi confirmada em Rails. Principal manteve inboxes 27/15/28 conectadas e 23/10 previamente desconectadas; a inbox pessoal 1 do MX permaneceu conectada.
- As montagens persistentes foram preservadas. Principal e MD usam volume no web e bind mount no worker: os caminhos correspondentes têm o mesmo dispositivo/inode no host, confirmando que acessam o mesmo diretório. MX usa o mesmo volume nos dois serviços. O armazenamento continua separado entre instâncias.
- Os três serviços Go mantiveram `whatsmeow-54aae63ad477bc6d5bf0077a091a1a9ac7c0efa2`, sem reinício. Bancos, Redis, segredos, domínios e sessões permanecem separados. Chatwoot oficial fora do escopo.

Recarregar abas abertas antes do deploy para carregar os novos assets. O worktree isolado preservou as alterações preexistentes do checkout principal.
