# Correções da interface de favoritas e grupos — 02/10/2026

Atualização posterior em 02/10/2026: principal, MX e MD usam `fork-9fe40d2c82c7499696b42f945ca4afa6fcbb4704` nos seis serviços web/Sidekiq. Links nas descrições, nove membros na lateral e janela pesquisável com menu de contato/conversa foram publicados. Go e sessões preservados. Leia [whatsmeow-group-links-members-2026-10-02.md](whatsmeow-group-links-members-2026-10-02.md) para a validação atual e a limitação do código de segurança. As imagens abaixo registram a entrega anterior.

Correção solicitada a partir dos prints da principal e do MX. A principal recebeu a implementação e a validação visual antes da publicação da mesma imagem no MX e no MD. O Chatwoot oficial permanece fora do escopo.

## Comportamento publicado

- Removido o seletor extra de listas/favoritos de conversas acima dos filtros, incluindo a lista criada nos testes anteriores. Removidos os controles e filtros dessas listas, dos favoritos de conversas e dos temas acrescentados na entrega anterior.
- O histórico usa novamente o fundo padrão do Chatwoot. Preferências antigas de tema deixam de alterar a conversa.
- O salto de uma mensagem favorita mantém a âncora e o carregamento do entorno, destacando a própria mensagem com contorno azul, sombra e transição suave. A linha inteira não recebe mais preenchimento verde.
- Dados do grupo têm nome legível com quebra de linha, edição em botão separado e ações circulares com rótulos abaixo. O espaçamento padrão herdado dos botões foi removido dessas ações para os textos caberem também no painel mínimo.
- Descrições longas ficam em três linhas e oferecem **Ler mais / Ler menos**. Membros sem permissão de edição também podem ler e expandir o texto; somente a edição depende da permissão.
- Grupos fora do limite já existente da chamada coletiva exibem adicionar/pesquisar no painel. O caminho e as restrições das chamadas continuam na integração anterior.
- Mensagens favoritas, criação e gerenciamento de grupos, mídia, busca, notificações e histórico oculto do usuário usam os fluxos já publicados. Inglês e português brasileiro acompanham a correção.

## Código e imagens

[PR #26](https://github.com/marcosenz0/chatwoot-whatsmeow/pull/26), branch `codex/whatsmeow-ui-corrections`, em worktree isolado a partir de `origin/develop` `0c34d6290ac5c0a6c5042a6418d9e885e38786c0`. As alterações anteriores do checkout principal foram preservadas.

- Web/Sidekiq: `ghcr.io/marcosenz0/chatwoot-whatsmeow:fork-10280d21bc22b3f2be29d9de6135e1b92c5fdcf0`.
- Manifesto publicado: `sha256:27beaf647b931644f71b3834a131739784a769996eaf42671118704f4e919cb1`.
- Docker ImageID comum aos seis serviços: `sha256:b3ff7021fda220e592fb94374d84f92915295b3ebbe574acf44a0625684e49af`.
- Os três Go mantêm `whatsmeow-54aae63ad477bc6d5bf0077a091a1a9ac7c0efa2`, ImageID `sha256:d40777437b6038662255808aebbd8dd741c0303a475a8b7ccd2dc30420f9300d`. Seus containers e sessões não foram reiniciados nesta correção.

| Destino | Web / Sidekiq | Go independente |
| --- | --- | --- |
| `chatwoot.marcoswt.com.br` | `chatwoot-staging` / `chatwoot-staging-sidekiq` | `whatsmeow-staging` |
| `chatwootmx.marcoswt.com.br` | `chatwoot-mx` / `chatwoot-mx-sidekiq` | `whatsmeow-mx` |
| `chatwootmd.marcoswt.com.br` | `chatwoot-md` / `chatwoot-md-sidekiq` | `whatsmeow-md` |

## Validação

- [Canário da revisão publicada 36964075111](https://github.com/marcosenz0/chatwoot-whatsmeow/actions/runs/36964075111): **104 testes JS e 330 exemplos Rails, zero falhas**, migração a partir do esquema anterior, **14 arquivos Ruby sem infrações**, compilação de produção e publicação aprovadas. Inclui os testes existentes de conteúdo expansível, API de conversas, âncoras e mídia.
- Lint dos arquivos JS/Vue alterados: zero erros, 12 avisos de chaves dinâmicas de i18n. As 51 chaves estáticas do painel de grupo foram conferidas em inglês e português brasileiro. Sintaxe do finder Ruby e whitespace também conferidos.
- Na principal, o grupo de teste voltou ao fundo padrão mesmo antes da limpeza das preferências antigas. O seletor extra não apareceu ao recarregar.
- Painel conferido nas larguras de **360 e 280 px**: quatro ações, cada rótulo em uma linha de 16 px, sem sobreposição ou rolagem horizontal. A largura foi restaurada após o teste. Descrição curta não exibe um controle de expansão desnecessário.
- Favorita de áudio abriu a mensagem original: o contorno envolveu 336 px de conteúdo dentro de uma linha de 630 px, mantendo o fundo da linha transparente. O destaque desapareceu depois. A captura local de validação usa o grupo e a mídia sintética dos testes anteriores; não foi publicada no Git.
- No MX, uma descrição longa em sessão sem administração passou de **72 px recolhida** para **720 px expandida** e voltou a 72 px. Ler mais/Ler menos funcionaram com texto legível e edição restrita. O grupo grande exibiu duas ações compactas, sem rolagem horizontal.
- MD foi recarregado no navegador e não exibiu o seletor extra. Continua sem caixa Whatsmeow pareada; sua publicação, esquema e saúde foram conferidos, sem criar uma sessão de teste.

Conferência operacional em **02/10/2026, 04:39 UTC**: os nove containers estavam em execução; os seis web/Sidekiq compartilhavam o ImageID acima. `/health` retornou HTTP 200 nos três domínios. Rails confirmou o SHA publicado, migração `20261001090000` presente, nenhuma migração pendente e Go `healthy` em cada destino. Principal preservou três caixas conectadas e duas anteriormente desconectadas; a sessão pessoal MX permaneceu conectada.

## Limpeza das preferências antigas

Removidas somente as propriedades `favorite`, `list` e `theme` dentro das preferências `whatsmeow_chats_*` de cada usuário. `cleared_before` e as demais configurações de interface foram preservadas. Mensagens, estrelas do WhatsApp, anexos e grupos não foram apagados.

| Destino | Usuários alterados | Preferências de conversas alteradas | Entradas antigas restantes |
| --- | ---: | ---: | ---: |
| Principal | 1 | 1 | 0 |
| MX | 0 | 0 | 0 |
| MD | 0 | 0 | 0 |

O registro de histórico oculto da principal continuou presente. A conferência final encontrou três favoritas na principal, **69 estados no MX — 64 com original e cinco pendentes** — e nenhuma no MD. A limpeza não alterou os estados das estrelas.

## Retomada e limites

Usar as imagens fixadas acima e preservar bancos, Redis, domínios, credenciais e sessões separados. Manter a sessão pessoal MX conectada e respeitar as caixas já desconectadas na principal. Uma aba com JavaScript anterior ao deploy precisa ser recarregada.

O composable existente `useExpandableContent` observa mudanças de largura e conteúdo. O destaque continua usando a navegação/eventos de âncora existentes. As mudanças de apresentação usam Tailwind; o filtro extra foi removido também do finder e do cliente de conversas, sem criar novos contratos ou overrides Enterprise.

Este documento substitui as descrições anteriores de listas, favoritos de conversas, temas e destaque verde. Os backups e os limites de recuperação de originais, mídia antiga, operações nativas, chamadas e exportação estão no [handoff de favoritas e grupos](whatsmeow-stars-groups-2026-10-01.md). As falhas herdadas da suíte geral CE/lint/auditoria permanecem registradas ali; a aprovação desta correção é do canário direcionado, não de toda a suíte oficial.
