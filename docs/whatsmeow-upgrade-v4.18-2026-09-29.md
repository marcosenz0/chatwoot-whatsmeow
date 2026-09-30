# Atualizacao comum do fork para Chatwoot 4.18.0

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

A imagem anterior `fork-6ac94e9b03f1bbbd4d3e076e633f7ff2b0aa7e20` foi aprovada no canario 36660400574 (309 exemplos Rails, sem falhas) e publicada com digest `sha256:5e9b1ddb9776a607e3f2d025502cf788262ba27b80db8e7c880` (conferir digest final antes de registrar conclusao). Principal e MX migraram e responderam health 200; MD foi acionado em seguida. Na principal, VERSION_CW 4.18.0, SHA 6ac94e9, sem migracoes pendentes; middleware de producao nao inclui Vite/Proxy. Sessoes 27, 15 e 28 conectadas; 23 desconectada como antes.
