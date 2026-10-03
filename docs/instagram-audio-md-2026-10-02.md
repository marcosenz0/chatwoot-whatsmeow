# Áudios do Instagram no MD — 02/10/2026

Correção operacional em `chatwootmd.marcoswt.com.br`, investigada em worktree isolado `codex/instagram-audio-md` a partir de `origin/develop` (`e0b7ab424a`). Não exigiu alteração do código ou nova imagem.

## Causa e correção

O web `chatwoot-md` montava `/app/storage` no volume persistente `marcos-apps_chatwoot-md_storage`. O `chatwoot-md-sidekiq` não tinha montagem nessa pasta. Os webhooks do Instagram gravavam os anexos no filesystem temporário do worker; o banco registrava os blobs, mas o web retornava HTTP 404 ao servir os arquivos. A transcrição feita pelo web também não conseguia ler os anexos.

Os arquivos ainda presentes no worker foram copiados antes do redeploy, sem sobrescrever arquivos existentes do web. Uma cópia de recuperação foi preservada no servidor em `/etc/easypanel/projects/marcos-apps/chatwoot-md/audio-recovery-20261002/`. O worker foi colocado em quiet mode e a cópia foi repetida depois de confirmar zero trabalhos em execução.

Foi salvo no Easypanel um bind mount do `chatwoot-md-sidekiq`:

- Origem: `/etc/easypanel/projects/marcos-apps/chatwoot-md/volumes/storage`.
- Destino: `/app/storage`.

Essa origem é o mesmo diretório usado pelo volume do web. Criar um volume chamado `storage` separadamente no worker não resolveria: o Easypanel inclui o nome do serviço no nome do volume. A montagem permanece na configuração do painel para próximos deploys.

Somente o Sidekiq MD foi redeployado. Web e worker mantêm `fork-9fe40d2c82c7499696b42f945ca4afa6fcbb4704`. Bancos, Redis, integrações Meta, domínios e configurações de transcrição foram preservados. Principal, MX, Go e Chatwoot oficial não foram modificados; a sessão pessoal MX não foi tocada.

## Validação

- Clara: inbox 5, conversa 2, mensagem 30, anexo 16; arquivo de 26.461 bytes. URL passou de HTTP 404 para HTTP 200; player carregou 3,16 segundos, avançou e terminou a reprodução. Transcrição retornou e foi exibida na interface.
- Emilly: inbox 1, conversa 1, mensagem 31, anexo 17; arquivo de 61.350 bytes. Player carregou 7,48 segundos e avançou durante a reprodução. Transcrição retornou e foi exibida na interface.
- Rails no web confirmou que ambos os blobs existem no armazenamento persistente. O novo worker leu os dois arquivos com os tamanhos acima. Uma gravação temporária no novo worker foi lida pelo web e removida após a verificação, confirmando o compartilhamento também para futuras gravações.
- Docker confirmou o novo worker em execução com o bind mount correto; conexão Sidekiq/Redis foi registrada após a inicialização. Web, banco e Redis MD permaneceram em execução.
- Nenhuma mensagem foi enviada às contas durante a validação. Não houve novo webhook de áudio após o redeploy; a validação cobre os dois áudios recebidos e o acesso compartilhado ao armazenamento.

## Limitação do histórico

A recuperação cobre arquivos ainda existentes no worker antes desta correção. Algumas mídias antigas da conversa da Emilly continuavam indisponíveis; arquivos perdidos em redeploys anteriores não estavam nessa cópia e não foram recuperados nesta tarefa. Mensagens que a Meta apresenta como não suportadas seguem essa limitação do canal.

O problema afeta anexos recebidos por jobs, não apenas áudio. O armazenamento compartilhado corrige a configuração para os canais Instagram e Facebook da instância MD. Não armazenar transcrições, conteúdo de mensagens ou credenciais neste handoff.
## Fotos no player e recuperação de perfil

Atualização solicitada em 02/10/2026: a mesma imagem deve ser usada nas três instâncias customizadas, mantendo seus bancos, arquivos e sessões separados.

- A foto no player é uma escolha de apresentação para áudios recebidos em caixas Instagram, tanto Instagram Login quanto Instagram via Facebook. Usa o avatar do remetente e funciona em mensagens já recebidas, sem migrar ou reclassificar anexos.
- O indicador de microfone continua restrito aos metadados de mensagem de voz já existentes. O formato MP4 do Instagram não é usado para afirmar autoria ou encaminhamento. Áudios de arquivo nos demais canais mantêm o ícone de fones.
- O fluxo de perfil passa a consultar novamente o Instagram quando o contato não possui avatar ou quando o blob existe no banco mas o arquivo está ausente. A recuperação usa `Avatar::AvatarFromUrlJob` com `force: true` para permitir baixar novamente uma URL cujo hash já estava salvo. Avatares existentes e acessíveis são preservados.
- No MD, o contato de teste da Emilly tinha um avatar anexado no banco, porém sem arquivo no storage. A API retornou uma foto válida; ela foi baixada novamente. O contato correspondente à caixa da Clara já possuía arquivo acessível. Não houve união de contatos entre caixas nem alteração de identidades Meta.
- Principal e MX já tinham armazenamento compartilhado entre web e worker, confirmado pelas montagens reais do Docker. A correção de montagem anterior era necessária no MD. Nenhum armazenamento foi compartilhado entre instâncias.

A API utilizada não oferece uma distinção confirmada entre áudio original e encaminhado. Assim, a foto identifica quem enviou a mensagem no Instagram, sem comprovar quem gravou o áudio. A diferenciação automática solicitada para encaminhados permanece limitada por esse contrato.

## Publicação da atualização de fotos

[PR #28](https://github.com/marcosenz0/chatwoot-whatsmeow/pull/28), revisão de código `45be3b7a5fdd6607fe6b99f237d87b27c1817848`, [canário 37081406308](https://github.com/marcosenz0/chatwoot-whatsmeow/actions/runs/37081406308). A imagem foi validada primeiro na principal e depois aplicada também ao MX e MD.

Os seis web/Sidekiq usam `ghcr.io/marcosenz0/chatwoot-whatsmeow:fork-45be3b7a5fdd6607fe6b99f237d87b27c1817848`, Docker ImageID comum `sha256:435373fbc16400fd7327f19a8d5c607262962ebb52f345a14b95857bde6acb3d`, manifesto `sha256:9e1cdb7d4ff0175d258dfe725120ff648707b6ab046bfa07fda2f9c938dc94d3`. Os três Go mantiveram a imagem `whatsmeow-54aae63ad477bc6d5bf0077a091a1a9ac7c0efa2` e os mesmos containers, sem reinício.

- Canário: 156 testes JavaScript em 17 arquivos e 396 exemplos Rails sem falhas; 16 arquivos Ruby sem infrações; compilação e publicação aprovadas. Os testes existentes de Instagram e avatar foram incluídos na validação. Os 14 testes locais dos componentes de mensagem também passaram. Lint do player: zero erros, um aviso já existente de chave dinâmica de i18n. As verificações gerais herdadas do repositório não são apresentadas como verdes.
- Os três domínios voltaram a responder HTTP 200 em `/health`. Rails confirmou a revisão nova e Go saudável nos três. Principal manteve inboxes 27/15/28 conectados e 23/10 previamente desconectados. A inbox pessoal 1 do MX permaneceu conectada.
- Após o rollout, um arquivo temporário gravado pelo worker foi lido pelo web em cada uma das três instâncias; os arquivos de verificação foram removidos. Isso confirmou o compartilhamento de storage para novas gravações e a persistência da configuração depois do deploy.
- No MD, os dois avatares tinham arquivos de 6.836 bytes acessíveis. Os áudios de 26.461 e 61.350 bytes e suas transcrições continuaram disponíveis. A interface em português exibiu a foto no player do Instagram, sem o ícone amarelo de fones; reprodução e duração foram conferidas. Nenhuma mensagem foi enviada durante a validação.
- A consulta ao campo `is_forwarded` para a mensagem de áudio real foi rejeitada pela API com HTTP 400 e campo inexistente. Não foi implementada uma distinção fictícia entre original e encaminhado. Arquivos e mensagens de voz dos outros canais mantêm a apresentação existente.

Bancos, Redis, segredos e configurações de canal permaneceram separados. O Chatwoot oficial ficou fora do escopo. Uma aba com a versão anterior precisa ser recarregada para usar os novos assets.
