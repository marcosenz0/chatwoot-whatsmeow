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

Backups consistentes anteriores a migracao da principal e do MX foram criados em seus respectivos volumes PostgreSQL: `/var/lib/postgresql/data/fork-upgrade-backups/pre-v4.18-20260929.dump`, formato custom, cerca de 46 MB cada. As listagens `pg_restore -l` foram conferidas. O PostgreSQL principal informou divergencia preexistente da versao de collation (base 2.41, ambiente 2.36); registrar e avaliar separadamente, sem alterar indices durante esta atualizacao.

Checks locais: sintaxe de 810 arquivos Ruby/Jbuilder alterados passou. ESLint dos 28 arquivos frontend que tiveram conflitos passou sem erros; seis avisos de chaves i18n dinamicas. Os 215 testes selecionados de conversas, inboxes, store e video passaram. A validacao JSON identificou e removeu uma chave SIDEBAR.CALLS duplicada em pt_BR, mantendo o nome Ligacoes. Testes Rails das integracoes e compilacao da imagem unica serao gates do canario.

O novo concern oficial InboxBotStatus participa da deteccao de MarcosX via external_bot_active?, evitando respostas simultaneas de Captain e MarcosX. A sincronizacao de templates Cloud preserva o erro explicito do fork e nao altera o timestamp em caso de falha; incorpora token de gerenciamento oficial, invalidacao de cache e paginacao por cursor apenas enquanto existir paging.next.

## Como retomar

1. Concluir validacoes, corrigir falhas concretas e publicar uma imagem imutavel do fork.
2. Guardar backups de MX e MD e registrar a revisao/imagem anterior de cada destino.
3. Atualizar web/Sidekiq por instancia, aplicar suas migracoes e confirmar health e UI.
4. Atualizar cada Go com a mesma revisao do repositorio e preservar sua configuracao/sessoes.
5. Validar cada instancia e registrar os resultados aqui e no handoff de chamadas.
6. Integrar a revisao aprovada em `develop`, manter a imagem comum fixada nos seis servicos e sincronizar a memoria Markdown do workspace principal.
