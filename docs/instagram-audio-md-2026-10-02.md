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
