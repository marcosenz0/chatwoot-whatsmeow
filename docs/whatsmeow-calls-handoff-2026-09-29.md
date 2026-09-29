# Handoff: chamadas WhatsApp Direct no Chatwoot (29/09/2026)

Este arquivo permite retomar a integracao em outro chat ou com outra IA. Nao registrar aqui segredos, numeros pessoais, conteudo de mensagens ou tokens de sessao. A sinalizacao de voz foi testada na revisao anterior; audio e video ainda exigem validacao de midia ponta a ponta.

## Onde continuar

- Repositorio: `marcosenz0/chatwoot-whatsmeow`; PR [#21](https://github.com/marcosenz0/chatwoot-whatsmeow/pull/21), **em rascunho**; branch remota `codex/whatsmeow-voice-calls`.
- Checkout isolado: `C:\Users\marco\.codex\worktrees\whatsmeow-voice-calls\Fork Chatwoot Marcos`. A imagem **anteriormente implantada** foi gerada do commit `73dfd600d0101e2b47b72fcd44ca3a521c43c269`. O desenvolvimento novo iniciou no commit `a99e7157b8b509eb80d217916095d2e5afaaf825`, com correcoes subsequentes na mesma branch; conferir o HEAD da PR, GitHub Actions e EasyPanel antes de presumir que esta no ar.
- A pasta principal `C:\Users\marco\OneDrive\Área de Trabalho\Projeto\Fork Chatwoot Marcos` esta em `develop` e contem outras alteracoes locais nao relacionadas. Nao usar `git reset`, `git clean`, `git pull` ou troca de branch que as descarte. O codigo de chamadas esta na branch/PR acima, nao no `develop` desse checkout.
- Este handoff deve ser lido junto com [whatsmeow-progress.md](whatsmeow-progress.md) e [whatsmeow-installation.md](whatsmeow-installation.md). O Chatwoot oficial (`chatwootoficial.marcoswt.com.br`) fica fora deste escopo.

## Objetivo e estado funcional

- Mostrar botoes de chamada de voz e video no cabecalho de conversas diretas de `Channel::Whatsmeow`, de forma parecida com WhatsApp Web. Grupos e outros canais nao recebem os controles.
- O painel de chamada permite iniciar, atender, recusar, silenciar o microfone, ligar/desligar a camera e encerrar. A implementacao tenta promover uma chamada de voz para video dentro da mesma ligacao.
- A interface usa `WhatsmeowConversationCall.vue` e `ConversationHeader.vue`; a API do navegador esta em `app/javascript/dashboard/api/whatsmeowCalls.js`. A pedido explicito do usuario, as strings da ligacao e da nova pagina estao traduzidas em `pt_BR`, alem do `en` fonte.
- Rails cria um token JWT HS256 de curta duracao (90 s) em `POST /api/v1/accounts/:account_id/conversations/:conversation_id/whatsmeow_call_session`. O controller esta em `app/controllers/api/v1/accounts/conversations/whatsmeow_call_sessions_controller.rb`; a disponibilidade da chamada sai no payload da conversa. A sessao vale para o inbox e o contato da conversa direta.
- `whatsmeow-service/calls.go` oferece WebSocket autenticado em `/calls/:channel_id` na porta interna `8081`, separado da API Go normal na `8080`. Ele valida token e `Origin` HTTPS exata, encaminha sinalizacao WhatsApp e quadros PCM/H264, e mantem um gerenciador de chamadas por cliente/sessao WhatsApp. `whatsmeow-service/main.go` inicia esse listener somente com `WHATSMEOW_CALLS_ENABLED=true`.
- O Go usa revisoes fixadas de `github.com/purpshell/meowcaller` e `github.com/polymorfa/hypermeow` em `go.mod`. O Dockerfile preserva a correcao local de recibos de Status por patch. A biblioteca de chamadas descreve video como experimental; nao presumir que a existencia dos botoes prove video funcional.
- A ultima correcao (`73dfd600d0`) envia `ended` quando um convite recebido e cancelado, emite `connected` ao atender, protege o fechamento duplicado de `AudioContext` no Vue e registra o primeiro quadro de microfone e de audio remoto para diagnostico.

## Revisao nova de interface e historico (`a99e7157b8`)

- A subaba `Ligacoes` foi adicionada apos `Status` na barra de Conversas, com icone de telefone. Sua rota Vue e `/app/accounts/:accountId/whatsmeow/calls` e usa `CallsPage.vue`. A listagem inclui favoritas, busca, recentes de entrada/saida/perdidas, foto/nome, duracao e nome da instancia sobre cada contato. A API de leitura e `GET /api/v1/accounts/:account_id/whatsmeow/calls`, sempre limitada aos inboxes acessiveis ao agente.
- O historico e registrado **a partir da implantacao nova** por eventos assinados `call_started`, `call_connected` e `call_ended` enviados pelo Go ao webhook existente. A tabela `whatsmeow_calls` foi criada na migration `20260929090000_create_whatsmeow_calls.rb`; o servico `Whatsmeow::CallEventService` consolida eventos repetidos ou fora de ordem e relaciona contato/conversa/instancia. Nao ha importacao retroativa de chamadas antigas do WhatsApp.
- `Nova ligacao` busca contatos salvos; `Discar numero` verifica o numero na sessao WhatsApp do inbox escolhido e abre/cria a conversa correspondente, iniciando a chamada de voz ou video. `Novo link de ligacao` usa a API real `CreateCallLink` do `meowcaller` via Rails/Go. `Programar ligacao` cria esse link e baixa um arquivo `.ics` para o usuario adicionar convidados no calendario; isto **nao** cria um agendamento nativo dentro do WhatsApp. Favoritos sao guardados no `localStorage` por conta e usuario deste navegador, sem sincronizacao entre dispositivos.
- O painel flutuante passou a exibir foto, nome e numero do contato, status, duracao e botoes de microfone/camera, convite de participante por numero, acesso rapido ao chat e encerrar. O Go chama `AddParticipant` para convidar e aceita automaticamente solicitacao de video durante a ligacao. A chamada recebida so passa para `connected` quando a biblioteca dispara `OnReady`, evitando mostrar uma conexao antes da midia estar pronta.
- O controller novo e `Api::V1::Accounts::WhatsmeowCallsController` (`index`, `dial`, `create_link`); no Go, o endpoint interno e `POST /sessions/:channel_id/call-links` protegido por token compartilhado. Nao confundir com o recurso `Call` Enterprise do Chatwoot.
- Verificacoes locais apos essa revisao: `go test ./...` passou; sintaxe Ruby e `git diff --check` passaram; Prettier analisou e formatou os componentes Vue. O Bundler/RSpec nao roda neste Windows porque faltam gems do projeto; os atalhos ESLint locais apontam para um `node_modules` compartilhado com junctions antigas. O primeiro CI do commit `a99e7157b8` apontou tres erros de ESLint em `CallsPage.vue` (helper nao usado e atributos na mesma linha); estes erros foram corrigidos em commit subsequente e precisam de nova verificacao.

## Tres instancias isoladas no EasyPanel

Projeto EasyPanel: `marcos-apps`. As tres bases de dados, Redis, chaves, sessoes WhatsApp e servicos Go sao separados. **Nao apontar as tres instancias para um unico Whatsmeow.**

| Instancia | Host HTTPS | Web / Sidekiq | Go correspondente |
| --- | --- | --- | --- |
| Principal | `chatwoot.marcoswt.com.br` | `chatwoot-staging` / `chatwoot-staging-sidekiq` | `whatsmeow-staging` |
| MX | `chatwootmx.marcoswt.com.br` | `chatwoot-mx` / `chatwoot-mx-sidekiq` | `whatsmeow-mx` |
| MD | `chatwootmd.marcoswt.com.br` | `chatwoot-md` / `chatwoot-md-sidekiq` | `whatsmeow-md` |

- Os seis servicos Chatwoot foram configurados e implantados com a **mesma** imagem `ghcr.io/marcosenz0/chatwoot-whatsmeow:calls-73dfd600d0101e2b47b72fcd44ca3a521c43c269`. A fonte da imagem foi conferida em cada web e Sidekiq no EasyPanel.
- Os tres servicos Go foram compilados e implantados a partir de `codex/whatsmeow-voice-calls`, com contexto `/whatsmeow-service`, cada um com seu `WHATSMEOW_CALLS_ORIGIN` e servico interno correspondente. No MD foi necessario desativar temporariamente a opcao de implantacao com tempo de inatividade zero para substituir a tarefa antiga; depois a rota passou a responder. Conferir esse ajuste antes de futuros redeploys do MD.
- Cada Chatwoot **web** usa `WHATSMEOW_CALLS_URL=https://<seu-host>`. Cada Go usa `WHATSMEOW_CALLS_ENABLED=true`, `WHATSMEOW_CALLS_PORT=8081` e `WHATSMEOW_CALLS_ORIGIN=https://<mesmo-host>`. O web e seu Go compartilham o `WHATSMEOW_SHARED_SECRET` ja existente naquela instancia; nunca copiar o segredo de outra instancia.
- Cada host possui uma rota HTTPS publica `/calls` apontando para `http://<Go correspondente>:8081/calls`. O WebSocket real usa `/calls/:channel_id`; `GET /calls` sozinho devolver 404 e esperado. A rota exige token assinado e `Origin` correta. A API Go da porta `8080` continua independente.
- Para receber ligacoes no painel, `Reject Calls` precisa estar desligado no inbox. A conversa direta correspondente precisa estar aberta no navegador. Em 29/09, o MD ainda nao tinha inbox Whatsmeow pareado, portanto nenhum teste de chamada real foi possivel nessa instancia.

## Validacao realizada

- `go test ./...` e `go build ./...` passaram no modulo Go. Testes de Go no CI, lint/testes frontend, compilacao Docker e publicacao da imagem canario passaram para o codigo implantado. O workflow `Publish Whatsmeow Calls Canary` do commit `73dfd600d0` concluiu com sucesso. Ruby syntax e lint direcionado dos arquivos novos tambem passaram.
- A suite ampla de CI da PR **nao esta verde**: lint Ruby global, varios shards backend e o check de review deployment falharam. Parte desses erros foi identificada como preexistente/fora das chamadas; revisar o detalhe antes de fazer merge, sem afirmar que todo o CI passou.
- Os tres `https://<host>/health` responderam HTTP 200. Em cada host, `GET /calls/27` com a propria `Origin` e sem token respondeu 401; sem `Origin`, a rota respondeu 403. Isso comprova roteamento e bloqueio de acesso, nao midia de chamada em MX/MD.
- No principal, uma chamada de saida iniciada no Chatwoot foi aceita no WhatsApp Desktop do Windows; o contador correu e a chamada foi encerrada pelo painel. Em outra chamada, o WhatsApp Desktop ligou para o inbox Pocobusinecl e o Chatwoot mostrou `Incoming call`; o agente atendeu **pelo Chatwoot, sem usar o celular**, viu `Connected`, alternou o botao de silenciar e encerrou. O contador do Windows avancou e a janela de chamada fechou.
- Uma tentativa anterior de chamada recebida havia sido atendida acidentalmente no celular e nao serviu como prova do fluxo no navegador; o teste acima foi repetido para eliminar essa ambiguidade.
- Os logs de midia foram adicionados (`first microphone audio frame` / `first decoded remote audio frame`), mas os registros acessados no EasyPanel estavam defasados e nao permitiram confirmar esses eventos na chamada real. Nao houve afericao independente da inteligibilidade do audio nos dois sentidos.

## Pendencias antes de declarar pronto

1. Fazer uma chamada de voz com dois dispositivos/participantes e **ouvir** audio inteligivel nos dois sentidos, alem de confirmar quadros de microfone e audio remoto nos logs atuais do Go. Testar mudo, reconexao/cancelamento e encerramento.
2. Testar video de saida e de entrada, ligar a camera durante a mesma chamada de voz, desligar e encerrar. **Correcao:** o PC tem a camera `C922 Pro Stream Webcam`, detectada nas classes PnP `Image` e `MEDIA`; a busca anterior apenas pela classe `Camera` estava errada. O usuario informou que ja permitiu camera no Chatwoot. Video e sua promocao ainda nao foram validados.
3. Testar uma chamada real em MX e, apos criar/parear um inbox Whatsmeow no MD, tambem no MD. Ate agora apenas o principal teve chamada real; os outros dois passaram nos testes de imagem, health e rota autenticada.
4. Conferir CI da revisao `a99e7157b8`, publicar a imagem correspondente nos tres web/Sidekiq e atualizar cada servico Go da sua propria instancia para a mesma branch. Rodar a migration em cada banco (verificar o job de release do Dockerfile/EasyPanel), inspecionar a aba `Ligacoes` nos tres dominos, e testar chamadas reais no principal. Registrar hash/tag exatos apos o deploy. Nao redeployar o Go antigo de `develop` antes de levar o codigo de chamadas para la.

## Referencias de pesquisa

- [Anuncio da Meta sobre ligacoes no WhatsApp Web](https://about.fb.com/br/news/2026/07/apresentamos-as-ligacoes-pelo-whatsapp-web-e-mais-novidades/).
- [Repositorio oficial do whatsmeow](https://github.com/tulir/whatsmeow): a implementacao padrao de chamadas ainda nao oferece o caminho completo usado aqui; esta PR usa `meowcaller` com o fork `hypermeow` fixado no modulo Go.
- [PR #1201 de sinalizacao de chamadas do whatsmeow](https://github.com/tulir/whatsmeow/pull/1201) e [meowcaller](https://github.com/purpshell/meowcaller).
