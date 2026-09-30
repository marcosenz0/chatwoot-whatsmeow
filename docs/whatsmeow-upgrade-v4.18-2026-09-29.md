# Atualizacao comum do fork para Chatwoot 4.18.0

## Estado final em 30/09/2026

**Publicacao concluida nos tres destinos customizados.** Os seis containers web/Sidekiq confirmaram `VERSION_CW=4.18.0` e `.git_sha=fa9cf49af5cf588651175cd2058c94a10dd740d5`. Os tres bancos nao possuem migracoes pendentes; os tres Go estao saudaveis e escutam chamadas em 8081. A ultima troca, Sidekiq MD, concluiu em **30/09 04:07:45 UTC** (01:07:45 America/Araguaina).

O pedido mais recente autoriza novamente principal, MX e MD, substituindo a restricao anterior a principal. O fork e comum; bancos, Redis, segredos, sessoes, dominios e Go continuam separados. `chatwootoficial.marcoswt.com.br` e os servicos EasyPanel `chatwoot` / `chatwoot-sidekiq` ficaram fora do escopo. A sessao pessoal removida do MX permanece desconectada.

### Codigo e imagem comum

- Release oficial incorporada: [v4.18.0](https://github.com/chatwoot/chatwoot/releases/tag/v4.18.0), publicada em 18/09/2026. Base anterior: 4.14.1. Rails 7.2.3.1, Ruby 3.4.4, Node 24 e pnpm 10.2.0.
- [PR #22](https://github.com/marcosenz0/chatwoot-whatsmeow/pull/22) integrou a atualizacao, merge `b3015c972cb78b2afa55f8eb12f272411e8d55b1`.
- [PR #23](https://github.com/marcosenz0/chatwoot-whatsmeow/pull/23) integrou a correcao do cache/retomada, merge `a9345a85698b2b4e5a6fef4008b3049aa061f77f`, em 30/09 03:40:03 UTC. **origin/develop contem o codigo de chamadas e as duas correcoes.** PR #21 e referencia historica em rascunho, com codigo ja incorporado.
- Imagem final fixada nos seis servicos: `ghcr.io/marcosenz0/chatwoot-whatsmeow:fork-fa9cf49af5cf588651175cd2058c94a10dd740d5`.
- Digest do manifesto: `sha256:308abd1bf67f495441e3e187b794f6e82cc65eec144a9e0f2a6f75f23528b7d9`. Docker ImageID dos seis containers: `sha256:f2a44476f6dd06a26acd71663920e2d604d381f2fb7acd8d00cfbf16dc0ad62a` (identificador diferente do manifesto).
- Os tres Go compilam o mesmo repositorio, branch `develop`, caminho `/whatsmeow-service`, Dockerfile, com deploy automatico desligado. A correcao fa9cf49 alterou somente frontend/tests; o codigo Go e identico entre os merges #22/#23.
- Go ImageID comum: `sha256:11615dd2fbcaa9a4f0390fe6ddad4039fec28c8d7ea64b94c3b3d336402a944e`. SHA256 de `/app/main` confirmado nos tres: `26d63d9432deedb644d46eef3a67626d0eba7cc3be2ed1a56963faa4f556ac9f`.

### Publicacao e verificacao real

| Instancia | Web / Sidekiq | Go separado | Resultado final |
| --- | --- | --- | --- |
| `chatwoot.marcoswt.com.br` | `chatwoot-staging` / `chatwoot-staging-sidekiq` | `whatsmeow-staging` | 4.18.0/fa9cf49 nos dois; health 200; sem migracoes pendentes; Go healthy/8081 |
| `chatwootmx.marcoswt.com.br` | `chatwoot-mx` / `chatwoot-mx-sidekiq` | `whatsmeow-mx` | 4.18.0/fa9cf49 nos dois; health 200; sem migracoes pendentes; Go healthy/8081 |
| `chatwootmd.marcoswt.com.br` | `chatwoot-md` / `chatwoot-md-sidekiq` | `whatsmeow-md` | 4.18.0/fa9cf49 nos dois; health 200; sem migracoes pendentes; Go healthy/8081 |

- Principal: contas 1 e 2, 15 inboxes no total, 35 chamadas preservadas. A conta 2 da UI tem cinco inboxes. Whatsmeow 27, 15 e 28 conectados; 23 e 10 desconectados como antes.
- MX: conta 1, uma inbox, duas chamadas preservadas; sessao da inbox 1 desconectada. Nao copiar account ID 2 da principal para URLs MX.
- MD: conta 1, tres inboxes, zero chamadas, sem canais Whatsmeow pareados. Nao declarar teste real de chamadas MD nem parear um numero sem pedido.
- Sidekiq 7.3.10 confirmado nos tres workers; updates Swarm concluidos (`State=completed`). `/calls` de cada dominio aponta somente ao Go correspondente em 8081; API normal em 8080. Chaves/origens/tokens/sessoes nao foram compartilhados.
- Conferencia publica final: `/health`, `/app` e o asset `/vite/assets/dashboard-Dha91atA.js` responderam HTTP 200 nos tres hosts; o asset final e identico. O HTML exige revalidacao (`max-age=0, private, must-revalidate`). Isso confirma entrega da mesma compilacao, sem substituir a verificacao visual de uma sessao autenticada.
- Comandos web preservados: principal/MX executam `db:migrate` antes de Puma; MD executa `db:chatwoot_prepare`. Nao executar `db:schema:load` em bases com dados.
- O Sidekiq MD ficou em `Pending: insufficient resources`: `zeroDowntime=true` exigia reservar memoria para duas copias. Foi alterado somente `deploy.zeroDowntime=false` nesse worker e repetida a implantacao. Comando `bundle exec sidekiq -C config/sidekiq.yml -c 3`, replica unica, filas, Redis, CPU/memoria e reservas foram preservados. A substituicao sequencial concluiu; nao aumentar recursos para repetir esse update.

### Correcao de abas antigas e conversas desatualizadas

Foi reproduzido um bloqueio de IndexedDB: outra aba antiga mantinha a conexao aberta enquanto uma nova precisava migrar o cache. Dados continuavam intactos; recarregar a aba antiga liberou o bloqueio.

- `DataManager` compartilha a abertura em andamento e fecha conexoes quando outra aba solicita atualizar a versao. Se a abertura estiver bloqueada, `CacheEnabledApiClient` usa a consulta de rede existente e recupera o cache quando o bloqueio termina. Nao foi adicionado timeout arbitrario.
- `ReconnectService` consulta lista, conversa ativa e mensagens ao voltar a aba (`visibilitychange`), restaurar pagina do cache de navegacao (`pageshow.persisted`) e recuperar rede. Eventos concorrentes compartilham a sincronizacao; reload apos desconexao superior a tres horas foi preservado.
- `App.vue` remove o listener anterior ao trocar de conta.
- Uma aba que ainda executa o JavaScript anterior deve carregar esta versao uma vez. Depois, esses eventos atualizam os dados automaticamente; nao foi implementada troca automatica de codigo numa pagina que permaneceu aberta durante um deploy.

### Integracoes preservadas e gates

- Whatsmeow, Pix, Status, grupos, reacoes, historico, pipelines, campanhas/automacoes duraveis e MarcosX IA preservados. Chamadas oficiais Cloud coexistem com a rota Whatsmeow. Filtros de grupos/ancoras cronologicas preservados; cursor de leitura Whatsmeow usa `reorder(created_at: :desc, id: :desc)`.
- `InboxBotStatus` considera MarcosX/bot externo para evitar respostas simultaneas com Captain. Templates Cloud mantem erro explicito/timestamp em falha e incorporam token de gerenciamento, invalidacao e paging.next oficial; API v22 preservada. OpenAI/Groq/transcricao e as guardas oficiais de gravacao coexistem.
- Migracoes oficiais aditivas ao esquema do fork; `fflate` mantido; pnpm 10.2.0; `airbnb-base/legacy` inexistente corrigido para `airbnb-base`. Dockerfile raiz recebeu `VIPS_BLOCK_UNTRUSTED=1` oficial. pt_BR manteve Ligacoes apos remover chave duplicada.
- Canario final [36664518232](https://github.com/marcosenz0/chatwoot-whatsmeow/actions/runs/36664518232): migracao do esquema anterior do fork, **309 exemplos Rails / zero falhas**, build de producao e publicacao da imagem final aprovados. Intermediario 36660400574 tambem passou.
- **46 testes de cache/retomada aprovados**, com bloqueio real entre conexoes IndexedDB, liberacao/recuperacao; lint dos cinco arquivos alterados aprovado. Mais 307 testes direcionados passaram durante o merge: total direcionado 353. Sintaxe de 810 Ruby/Jbuilder e validacao de 1.228 JSON passaram; lint dos 28 frontend com conflitos sem erros/seis avisos i18n.
- Go 36660405878 e Docker 36660405825 aprovados. Binario, health e listener conferidos nos tres containers atuais. Rails runners em 30/09 04:08-04:09 UTC confirmaram versao/SHA, dados, sessoes e migracoes nos tres webs. Nenhum middleware Vite/Proxy em producao nos tres.
- Rotacao Android, recuperacao/reordenacao RTP, seletores e pesquisa ja validados pelo usuario antes deste upgrade estao na imagem comum. Reconhecimento facial nao foi acrescentado; o usuario confirmou audio inteligivel e video continuo no teste anterior de 2 min 49 s.

### Limites da verificacao e manutencao separada

- Historico/interface portuguesa da principal conferidos na imagem intermediaria 4.18.0. A verificacao visual final/retomada real da imagem fa9cf49 nao concluiu: o navegador ficou indisponivel durante a ultima etapa. Os deploys foram concluidos e conferidos pelo acesso de administracao do servidor. Nao declarar verificacao visual final MX/MD nem nova chamada real apos o upgrade como realizadas.
- Suite CE completa e lint global ainda falham em expectativas/mocks de idiomas, payloads/jobs extras do fork e Cloud v14. AttachmentsPreview e CloudStudioPanels sao duas suites frontend remanescentes; ReplyBox foi corrigido e revalidado. Nao declarar suite oficial inteira aprovada.
- `bundle-audit` aponta `rack-proxy 0.7.7`, dependencia de `vite_ruby 3.10.2`, por [GHSA-42qh-8mx8-7wqm](https://github.com/ncr/rack-proxy/security/advisories/GHSA-42qh-8mx8-7wqm). Advisory confirma 1.0.0-1.0.2; anteriores nao avaliados, e a restricao do vite_ruby impede atualizar diretamente para 1.0.3. Ausencia do proxy em producao confirmada nao equivale a auditoria limpa; migrar a dependencia de desenvolvimento em trabalho proprio.
- Collation do PostgreSQL principal (base 2.41 / ambiente 2.36) ja divergente antes do upgrade: avaliar/reindexar em manutencao propria, sem `REFRESH COLLATION VERSION` isolado.
- Ofertas duplicadas de chamadas reproduzidas/corrigidas. Logs antigos MX compativeis, mas nao provam a origem de todas as recusas anteriores. Sessao pessoal MX removida.

### Backup, rollback e retomada

- Dumps consistentes anteriores a migracao nos respectivos volumes PostgreSQL: `/var/lib/postgresql/data/fork-upgrade-backups/pre-v4.18-20260929.dump`, formato custom, `pg_restore -l` conferido. Principal/MX cerca de 46 MB cada; MD cerca de 487 KB. Nao transferidos para armazenamento publico.
- Imagens anteriores: principal `calls-eeaf61d3149e465af71eac50f4805ce2acc6c6d9`; MX/MD `calls-2da34374b58ffcabce53c2914b44cd410b152fc2`; Go principal anterior `bd474b7328d428b714faf3f20544f1df957d98e7`. Avaliar compatibilidade das migracoes antes de rollback; restaurar dump somente em manutencao controlada quando necessario, nunca automaticamente/apagando volumes.
- Worktree atual: `C:/Users/marco/.codex/worktrees/chatwoot-common-update/Fork Chatwoot Marcos`, branch local `codex/chatwoot-v4.18-common`; codigo comum em `origin/develop` (a9345a8569 antes do commit final de documentacao). Commit posterior so de Markdown nao exige trocar a imagem validada.
- Checkout principal `C:/Users/marco/OneDrive/Área de Trabalho/Projeto/Fork Chatwoot Marcos` ainda em revisao anterior com mudancas locais preexistentes; Markdown atualizado seletivamente. Nao executar reset/clean/pull cego. Preservar AGENTS, CONTRIBUTING, CODE_OF_CONDUCT, docs e pastas locais antes de sincronizar codigo.
- Ler tambem handoff de chamadas, progresso e instalacao. Quando o navegador voltar, confirmar visualmente MX/MD e retorno a conversa ativa sem reload. MD nao tem Whatsmeow pareado; nao reconectar a sessao pessoal MX para um teste.
- MCP EasyPanel instalado espera envelope tRPC antigo e pode retornar erro de decodificacao apos aplicar uma mutacao. API atual retorna `{json: ...}`; verificar configuracao e containers antes de repetir. Helpers locais em `.codex/easypanel_admin.py` / `.codex/easypanel_shell.py` usam credenciais existentes somente em memoria, fora dos Markdown/repositorio.

## Checkpoints historicos anteriores a conclusao

As instrucoes e estados pendentes abaixo descrevem o progresso durante o merge; o estado final e a orientacao para retomar estao acima.

## Pedido e escopo atual

Em 29/09/2026 o usuario autorizou novamente publicar nas tres instancias customizadas: principal, MX e MD. Todas devem usar uma imagem comum do mesmo fork; bancos, Redis, segredos, sessoes WhatsApp, dominios e servicos Go permanecem separados. O Chatwoot oficial instalado separadamente continua fora do escopo. A sessao pessoal desconectada do MX nao deve ser reconectada automaticamente.

## Integracao em andamento

- Base validada das chamadas: `5bafe5cb77`, incluindo rotacao Android, recuperacao e reordenacao de video, seletores de dispositivos, pesquisa arredondada e historico nas conversas.
- Release oficial estavel escolhida: [v4.18.0](https://github.com/chatwoot/chatwoot/releases/tag/v4.18.0), publicada em 18/09/2026. A base anterior era 4.14.1.
- Worktree da atualizacao: `chatwoot-common-update`, branch `codex/chatwoot-v4.18-common`.
- Resolucao preserva endpoints, canais e sessoes Whatsmeow, Pix, Status, grupos, reacoes, historico, pipelines, campanhas/automacoes proprias e MarcosX AI. O fluxo de entrega de campanhas do fork permanece baseado em jobs e registros proprios. As chamadas oficiais de WhatsApp Cloud continuam separadas das chamadas Whatsmeow.
- Dependencias oficiais atualizadas; `fflate` usado pelo fork foi mantido. Lockfile regenerado com pnpm 10.2.0.
- Esquema combina migracoes oficiais com as tabelas do fork. As migracoes precisam ser executadas individualmente em cada base.
- Correcao da configuracao ESLint: `airbnb-base/legacy` nao existe no pacote instalado; utilizar `airbnb-base`.

## Publicacao e verificacao

A publicacao ainda esta pendente neste checkpoint. Nao declarar as instancias atualizadas ate registrar as imagens ativas, migracoes, sessoes e validacao de cada destino.

Backups consistentes anteriores a migracao das tres bases foram criados em seus respectivos volumes PostgreSQL: `/var/lib/postgresql/data/fork-upgrade-backups/pre-v4.18-20260929.dump`, formato custom. Principal e MX: cerca de 46 MB cada; MD: cerca de 487 KB. As listagens `pg_restore -l` foram conferidas. O PostgreSQL principal informou divergencia preexistente da versao de collation (base 2.41, ambiente 2.36); registrar e avaliar separadamente, sem alterar indices durante esta atualizacao.

Checks locais: sintaxe de 810 arquivos Ruby/Jbuilder alterados passou. ESLint dos 28 arquivos frontend que tiveram conflitos passou sem erros; seis avisos de chaves i18n dinamicas. Os 215 testes selecionados de conversas, inboxes, store e video passaram. A validacao JSON identificou e removeu uma chave SIDEBAR.CALLS duplicada em pt_BR, mantendo o nome Ligacoes. Testes Rails das integracoes e compilacao da imagem unica serao gates do canario.

O novo concern oficial InboxBotStatus participa da deteccao de MarcosX via external_bot_active?, evitando respostas simultaneas de Captain e MarcosX. A sincronizacao de templates Cloud preserva o erro explicito do fork e nao altera o timestamp em caso de falha; incorpora token de gerenciamento oficial, invalidacao de cache e paginacao por cursor apenas enquanto existir paging.next.

Checkpoint de 30/09 02:45 UTC: PR [#22](https://github.com/marcosenz0/chatwoot-whatsmeow/pull/22) integrada em `develop`, merge `b3015c972cb78b2afa55f8eb12f272411e8d55b1`. Revisao candidata da imagem comum: `6ac94e9b03f1bbbd4d3e076e633f7ff2b0aa7e20`; compilacao/publicacao no canario `36660400574` ainda em andamento. As origens dos tres servicos Go foram ajustadas para `develop`, caminho `/whatsmeow-service`, sem iniciar o redeploy antes da nova imagem web. As rotas `/calls` e origens foram conferidas por instancia, cada uma apontando ao respectivo Go na porta 8081.

- Migracao a partir do esquema real do fork anterior passou em PostgreSQL 16. O teste remove apenas do banco efemero de CI os marcadores artificiais inseridos por schema:load; nao alterar schema_migrations em producao.
- Gate Rails das integracoes passou; agora inclui CloudTemplateService e reautorizacao. Go `36660405878` passou testes da biblioteca e servico, vet e build.
- Mais 92 testes do ReplyBox passaram depois de adaptar o mock da rota; total frontend direcionado: 307. As falhas do editor na suite geral eram a ausencia de $route na simulacao, sem erro equivalente na rota real.
- Correcao de leitura Whatsmeow: reorder(created_at: :desc, id: :desc) calcula corretamente o ultimo cursor apesar do escopo ASC do modelo Message.
- O Dockerfile raiz foi alinhado ao Dockerfile oficial com VIPS_BLOCK_UNTRUSTED=1, pois o workflow do fork compila pela raiz.
- A suite CE completa e o lint global ainda nao estao verdes. Ha expectativas antigas de idiomas, payloads estendidos do fork, mocks HTTP v14 e jobs extras. Na interface, a execucao anterior teve 459 arquivos passando e tres suites falhando; o ReplyBox foi corrigido e revalidado separadamente. Nao descrever isso como aprovacao de toda a suite oficial.
- bundle-audit aponta rack-proxy 0.7.7 (dependencia de vite_ruby 3.10.2) por GHSA-42qh-8mx8-7wqm. O advisory confirma 1.0.0-1.0.2; as versoes anteriores nao foram avaliadas. A restricao do vite_ruby impede atualizar diretamente para 1.0.3. Confirmar ausencia de ViteRuby::DevServerProxy no middleware de producao; nao ignorar o alerta nem declarar auditoria limpa.

## Como retomar

1. Concluir validacoes, corrigir falhas concretas e publicar uma imagem imutavel do fork.
2. Guardar backups de MX e MD e registrar a revisao/imagem anterior de cada destino.
3. Atualizar web/Sidekiq por instancia, aplicar suas migracoes e confirmar health e UI.
4. Atualizar cada Go com a mesma revisao do repositorio e preservar sua configuracao/sessoes.
5. Validar cada instancia e registrar os resultados aqui e no handoff de chamadas.
6. Integrar a revisao aprovada em `develop`, manter a imagem comum fixada nos seis servicos e sincronizar a memoria Markdown do workspace principal.

## Correcao adicional de retomada do navegador (30/09)

O usuario relatou que abas restauradas exibiam conversas antigas ate recarregar manualmente. Na principal, uma aba anterior mantinha o IndexedDB aberto e bloqueava a migracao do cache; cinco inboxes e 35 chamadas estavam intactos no banco. Recarregar a aba antiga liberou o cache e o historico voltou.

A correcao em validacao faz o cache liberar conexoes quando outra aba precisa atualizar o esquema e usa a consulta de rede existente quando uma aba antiga bloqueia essa atualizacao. ReconnectService passa a sincronizar lista, conversa ativa e mensagens ao voltar a aba, restaurar pagina do cache de navegacao ou recuperar rede. Eventos simultaneos compartilham a sincronizacao. Ao trocar a conta, o listener anterior e removido. Os 46 testes direcionados de DataManager, CacheEnabledApiClient e ReconnectService passaram, incluindo bloqueio real de IndexedDB entre conexoes e recuperacao posterior. ESLint dos cinco arquivos alterados passou. Publicacao desta correcao ainda pendente.

A imagem intermediaria `fork-6ac94e9b03f1bbbd4d3e076e633f7ff2b0aa7e20` foi aprovada no canario 36660400574 (309 exemplos Rails, sem falhas) e publicada com digest `sha256:5e9b1ddb9776a607e3f2d025502cf788262ba27b80db054d94de720fb8e7c880`. Depois foi substituida pela imagem final fa9cf49 acima. Principal e MX migraram e responderam health 200; MD foi acionado em seguida. Na principal, VERSION_CW 4.18.0, SHA 6ac94e9, sem migracoes pendentes; middleware de producao nao inclui Vite/Proxy. Sessoes 27, 15 e 28 conectadas; 23 desconectada como antes.
