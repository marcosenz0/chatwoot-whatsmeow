# Mensagens apagadas e avisos de visualização única — 03/10/2026

## Comportamento

**Mensagens apagadas** aparece abaixo de **Mensagens favoritas** no menu global do WhatsApp Direct. O painel reutiliza as prévias das favoritas, com busca, filtro por caixa, paginação e identificação do remetente/conversa. Clicar em um resultado abre a conversa e a âncora da mensagem original. O menu e os dados do grupo também permitem abrir a lista filtrada para aquele grupo.

A lista mostra mensagens públicas marcadas como apagadas no WhatsApp. O tratamento de revogação existente já conserva o conteúdo e anexos no Chatwoot; nenhuma cópia de conteúdo ou migração foi necessária. Notas privadas, exclusões somente locais e conversas/caixas sem permissão ficam fora da consulta. Mensagens que não chegaram à integração não são reconstruídas. Arquivos ausentes não são recuperados pela listagem.

O serviço Go passa a tratar `events.UndecryptableMessage` com `UnavailableTypeViewOnce`. Esse aviso intencionalmente sem mídia é importado como uma mensagem normal, mantendo ID, remetente, conversa/grupo e horário. A mensagem explica que a mídia deve ser aberta no celular. Não solicita conteúdo restrito ao telefone nem tenta recuperar chaves ausentes.

Quando o próprio WhatsApp entrega mídia reproduzível, o player de foto/áudio/vídeo existente continua disponível. A interface distingue **Visualização única** de **Mensagem temporária** com prazo. A detecção considera flags da biblioteca, flags de mídia e expiração no contexto da mensagem. Isso não garante abertura de toda mídia de visualização única em dispositivo vinculado.

## Implementação

`WhatsmeowDeletedMessagesController` aplica conta, política de caixas e `Conversations::PermissionFilterService`, pesquisa conteúdo/remetente/conversa e pagina pela dupla horário original/ID. O painel compartilhado `MessageHistoryPanel` mantém a sincronização das favoritas e usa atualização da lista para as apagadas. Não altera mensagens recebidas ao listar ou navegar.

O endpoint de mensagem/conversa e sua navegação por âncora continuam os mesmos. O overlay Enterprise foi conferido; nenhuma extensão específica foi necessária. Inglês e português brasileiro incluídos por solicitação do usuário.

Na conferência do histórico real, um áudio antigo sem blob anexado provocava HTTP 500 na segunda página. `Attachment#file_metadata` agora representa a ausência do arquivo sem quebrar a serialização. O teste de regressão verifica a resposta da lista para esse áudio; URLs vazias não são apresentadas como arquivos recuperados.

## Publicação

[PR #31](https://github.com/marcosenz0/chatwoot-whatsmeow/pull/31) integrado em `develop` pelo merge `28335b5629cc2baf6910cbbd5d6dc18555ad07de`.

Aplicação e Sidekiq nas três instâncias:
- `ghcr.io/marcosenz0/chatwoot-whatsmeow:fork-74572d3ef3dc65d5f881e665dda866f633713e48`
- ImageID comum: `sha256:6f46faf3a06503dedc286598a9b15c2e378e1efd98a901118cb8d22ed8bbedd3`.

Serviço Go nas três instâncias:
- `ghcr.io/marcosenz0/chatwoot-whatsmeow:whatsmeow-d51b3cd8bcd21fb339e0896207d7c089a2414b85`
- ImageID comum: `sha256:7019a5837beea332dbab2b5477289479ae303d3c516bd239c66aa2b7bc13fdaa`.
- O diretório Go desse commit é idêntico ao da versão final da aplicação; os commits posteriores corrigem Ruby e o teste de áudio sem arquivo.

Rollout sequencial: principal validada antes de MX, depois MD. Nove containers em execução, mesmos ImageIDs por componente. `chatwoot.marcoswt.com.br`, `chatwootmx.marcoswt.com.br` e `chatwootmd.marcoswt.com.br` responderam HTTP 200. O Chatwoot oficial ficou fora do escopo.

Bancos, configurações, segredos e sessões permanecem separados. Os volumes de storage continuam específicos por instância. Na principal e no MD, os caminhos diferentes de web/worker foram conferidos por dispositivo/inode e apontam para o mesmo diretório; no MX, ambos usam o mesmo volume nomeado.

## Validação

- [Fluxo final 37139411373](https://github.com/marcosenz0/chatwoot-whatsmeow/actions/runs/37139411373): 182 testes JavaScript, 464 exemplos Rails, 27 arquivos Ruby sem infrações; build de produção e publicação concluídos.
- [Serviço Go 37137483950](https://github.com/marcosenz0/chatwoot-whatsmeow/actions/runs/37137483950): testes, `vet`, build e publicação aprovados. A execução local Windows sem os patches de dependências falhou na extensão preexistente de chamadas de grupo; o fluxo Linux aplica os patches pinados e passou.
- APIs reais autenticadas, com cliente temporário removido ao final: principal conta 2 e MX conta 1 retornaram 168 mensagens acessíveis cada, carregadas até o fim sem repetição. Conteúdo original da primeira página, marcadores, filtros e resposta da âncora foram verificados. MD retornou lista vazia com HTTP 200; não há caixa Whatsmeow configurada ali.
- Principal: caixas 27, 15 e 28 permaneceram conectadas; 23 e 10 já estavam desconectadas e mantiveram esse estado. A conversa pessoal usada como referência manteve a atividade anterior.
- MX: sessão pessoal da caixa 1 conectada após o rollout. MD: serviço saudável, sem sessões. Os três serviços Go responderam saúde `healthy`.
- As verificações amplas do repositório ainda apresentam falhas fora desta mudança, incluindo expectativas antigas de payload de pipelines, idioma, componentes Cloud Studio/previews, estilo e auditoria de dependências. Não declarar a suíte completa do repositório como aprovada. O gate específico acima e as APIs desta entrega passaram.
- A validação visual foi interrompida pelo controle do computador: não conseguiu determinar a URL atual do navegador com confiança para aplicar a política. Não foi continuada por outra automação de interface. Não há confirmação visual independente.

## Limites e retomada

O aviso resolve o sumiço para novos eventos de visualização única recebidos pela integração. Mensagens anteriores descartadas e ausentes do banco/histórico disponível não ganham conteúdo inventado. Não houve envio externo para testes nem marcação de abertura de mídia de visualização única. O novo fluxo de recebimento foi coberto por testes do evento Go e do serviço Rails; não houve teste de envio real de visualização única nesta execução.

Após atualizar a aba, abrir o menu global do WhatsApp e **Mensagens apagadas**. Para conferir o recebimento real de visualização única, enviar uma nova mídia de teste ao número conectado; o conteúdo só poderá abrir no Chatwoot se o WhatsApp fornecer o arquivo. Preservar a sessão pessoal MX em próximas atualizações.
