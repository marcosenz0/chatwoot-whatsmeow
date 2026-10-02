# Favoritas e gerenciamento de grupos WhatsApp Direct

> Revisão de 02/10/2026: as listas/favoritos de conversas e os temas foram removidos; o destaque e os dados do grupo foram reformulados. Leia primeiro [whatsmeow-ui-corrections-2026-10-02.md](whatsmeow-ui-corrections-2026-10-02.md) para as imagens atuais e validação. Este relatório mantém o histórico da entrega anterior, backups e limites dos recursos.

Entrega solicitada em 01/10/2026 para principal, MX e MD. A publicação usa uma imagem comum por componente, mantendo bancos, Redis, credenciais, domínios e sessões independentes. O Chatwoot oficial está fora do escopo. A autorização atual inclui português brasileiro e substitui a antiga restrição a publicar somente na principal.

## Código e publicação

- Chatwoot 4.18.0, baseado em `origin/develop` `c1e6883a4b`, com as integrações anteriores do fork e a correção de cache/retomada preservadas.
- [PR #25](https://github.com/marcosenz0/chatwoot-whatsmeow/pull/25), branch `codex/whatsmeow-stars-groups`; desenvolvimento em worktree isolado. O checkout principal continua com suas alterações locais anteriores, sem reset ou limpeza.
- Web/Sidekiq: `ghcr.io/marcosenz0/chatwoot-whatsmeow:fork-9afed3964f01e14fb4997a1d9d3e021d51b5eb16`.
- Manifesto web: `sha256:03bab226baa46581ca34df9d67d3f826efd104135481ac4b1df1645520ebfd94`; Docker ImageID: `sha256:fe0090d37838bf953d8e88e3a2d8ceb32c77f6c2620ecdeb6cb6e498416f8ebb`.
- Go: `ghcr.io/marcosenz0/chatwoot-whatsmeow:whatsmeow-54aae63ad477bc6d5bf0077a091a1a9ac7c0efa2`; Docker ImageID: `sha256:d40777437b6038662255808aebbd8dd741c0303a475a8b7ccd2dc30420f9300d`.
- Os commits posteriores ao Go `54aae63` alteram apenas Rails/interface/testes; os três Go executam o mesmo código necessário para esta entrega. As imagens ficam fixadas por SHA, sem depender de recompilar `develop` a cada reinício.
- A principal recebeu e validou cada candidato antes das demais instâncias. A última revisão do download foi aplicada primeiro à principal; a confirmação final de saúde e imagens dos três destinos está registrada abaixo.

| Domínio | Web / Sidekiq | Go separado |
| --- | --- | --- |
| `chatwoot.marcoswt.com.br` | `chatwoot-staging` / `chatwoot-staging-sidekiq` | `whatsmeow-staging` |
| `chatwootmx.marcoswt.com.br` | `chatwoot-mx` / `chatwoot-mx-sidekiq` | `whatsmeow-mx` |
| `chatwootmd.marcoswt.com.br` | `chatwoot-md` / `chatwoot-md-sidekiq` | `whatsmeow-md` |

Verificação final em 01/10 às 23:56 (America/Araguaina; 02/10 02:56 UTC): os nove containers estão em execução, com os seis web/Sidekiq no mesmo ImageID acima e os três Go no seu ImageID comum. `/health` respondeu HTTP 200 nos três domínios. Rails confirmou `.git_sha=9afed3964f01e14fb4997a1d9d3e021d51b5eb16`, migração `20261001090000` presente, nenhuma migração pendente e Go `healthy` em cada instância. Principal preservou três caixas conectadas e duas anteriormente desconectadas; MX preservou sua caixa pessoal conectada; MD continua sem caixa Whatsmeow pareada.

## Comportamento entregue

- **Mensagens favoritas:** menu global e filtro por conversa, sincronização com as estrelas existentes no WhatsApp, pesquisa, paginação, identificação do remetente e conversa, prévias de texto/imagem/áudio/vídeo/documentos e retirada da estrela. Clicar abre a mensagem original, carrega seu entorno cronológico e aplica destaque temporário. As prévias não duplicam os IDs usados nas âncoras da conversa.
- **Novo grupo:** seleção de contatos com pesquisa e chips removíveis, verificação de números informados manualmente e identificação conjunta PN/LID para evitar duplicados. O assistente mantém a seleção ao voltar e permite nome, foto, descrição, duração das mensagens temporárias e permissões antes da criação.
- **Dados do grupo:** abrem pelo nome ou avatar, com ações identificadas de voz, vídeo, adicionar e pesquisar. Incluem membros, pesquisa de membros, promoção/rebaixamento/remoção, adição, convite e redefinição de link, solicitações de entrada, permissões, alterações de membros e criação de grupo semelhante. A inclusão em comunidade usa a operação nativa e exige uma comunidade válida da sessão.
- **Organização:** favoritas da conversa, mídia/links/documentos, busca de mensagens, silenciar notificações, tema, favoritos de conversas, listas, exportação textual, fechar conversa, limpar a visualização e sair do grupo. Limpar oculta o histórico somente para o usuário atual no Chatwoot; mensagens, mídias, estrelas e o histórico do WhatsApp continuam preservados, inclusive a abertura por âncora.
- **Menu de conversas:** criar grupo, favoritas, selecionar conversas, marcar como lidas, bloqueio deste navegador e desconexão. O bloqueio usa PIN local de seis dígitos, sal e PBKDF2, com bloqueio após inatividade; configurar um PIN real não fez parte dos testes manuais.
- **Chamadas de grupo:** voz/vídeo em grupos de 3 a 32 membros, convidando os demais participantes de uma vez, com identificação do grupo e vídeo por participante. O evento de conexão de um participante remoto muda a interface para “Em ligação” e registra a duração no histórico. O aceite local de uma chamada recebida em grupo também dispara o callback de conexão uma única vez.
- Inglês e português brasileiro incluídos por pedido explícito do usuário. Emoji, stickers, áudio e anexos continuam usando o compositor existente.

## Decisões de implementação

`WhatsmeowMessageStar` guarda o estado ordenado por horário do evento, indexado por caixa/conversa/mensagem de origem. Estrelas recebidas antes do histórico aguardam a importação do original; a remoção de uma estrela antiga não vence um evento posterior. A recuperação consulta o cache de histórico da sessão e solicita mensagens indisponíveis ao dispositivo principal quando necessário. Não são inventados textos ou mensagens substitutas para originais ausentes.

APIs de favoritas, grupos, exportação e leitura respeitam conta, políticas e caixas acessíveis. A busca contempla conteúdo e identidade da conversa/remetente. Notas privadas ficam fora das favoritas e da exportação. A navegação por âncora valida a conversa e usa horário e ID, evitando que a ordem da importação de mensagens antigas quebre o salto. As extensões e filtros de permissões Enterprise foram conferidos.

Preferências de lista, tema, favorita da conversa e histórico oculto pertencem ao usuário e à conta. Leitura em lote atualiza os cursores próprios e notificadores, sem disparar callbacks de atualização de conversa alheios à leitura. Operações de grupo passam pelo WhatsApp e retornam suas permissões e erros; controles de administrador ficam desabilitados para sessões sem esse papel.

O serviço Go usa as bibliotecas existentes e um patch do `meowcaller` para preservar a identidade do grupo nos eventos e no aceite. O tratamento de mídia separa os participantes e mantém o fluxo anterior das chamadas diretas. Não houve alteração de versões do Gemfile ou lockfile de dependências.

## Validação

- [Canário final 36956460193](https://github.com/marcosenz0/chatwoot-whatsmeow/actions/runs/36956460193): **82 testes JS, 330 exemplos Rails, zero falhas**, migração a partir do esquema anterior do fork, **14 arquivos Ruby sem infrações**, build de produção e publicação aprovados. Os testes incluem permissão/isolamento de favoritas, eventos fora de ordem, recuperação tardia, âncoras, leitura/exportação e seleção PN/LID.
- [Go 36952854864](https://github.com/marcosenz0/chatwoot-whatsmeow/actions/runs/36952854864): testes do serviço e biblioteca com patch, `vet`, compilação e publicação aprovados. O fluxo de PR correspondente também passou.
- Grupos reais criados usando somente os números de teste autorizados pelo usuário: assistente com seleção/retorno, foto, descrição, timer de 24 horas e permissões confirmados. Lista de quatro membros, promoção/rebaixamento/remoção/readição e redefinição de convite conferidas. Outra sessão sem administração exibiu os controles restritos corretamente.
- Painéis de solicitações e alterações de membros, busca de mensagem, favorita/lista/tema, silenciar e reabrir conferidos. Limpar a visualização ocultou o histórico após recarregar e preservou a abertura da mensagem favorita. A saída do primeiro grupo descartável de teste foi confirmada.
- Áudio e vídeo sintéticos enviados apenas ao grupo de teste, favoritados e reproduzidos no painel; o salto para o áudio original e o desaparecimento do destaque foram confirmados. A captura de validação contém esses anexos sintéticos, sem imagem de câmera ou conteúdo de conversas privadas.
- MX recuperou **65 estados de favoritas**, com **60 originais disponíveis e cinco aguardando o original**. Uma favorita antiga abriu a mensagem correta no grupo de origem, com destaque; prévias antigas de áudio/vídeo também foram conferidas. A sessão pessoal que o usuário reconectou ao MX permanece **conectada**. Não aplicar a instrução histórica de desconectá-la.
- Chamada real de grupo de voz aceita e encerrada com duração de **2 min 45 s**; chamada iniciada em vídeo aceita no WhatsApp Desktop, com imagem da câmera do Chatwoot observada no aplicativo e duração de **5 min 37 s**. Os três demais membros foram convidados. A chamada foi encerrada para liberar a câmera do Note 12 enquanto o usuário utilizava o aparelho.
- A exportação possui teste de endpoint aprovado e não gerou erro novo no console ao acionar o botão na revisão final. O código mantém a URL do arquivo até depois de iniciar o download. **O evento de download do controle do navegador expirou; a gravação do arquivo pelo navegador não foi confirmada independentemente.**

## Limites e manutenção

- Originais e mídia antiga dependem do histórico/cache e do que o dispositivo principal ainda disponibiliza. Cinco favoritas MX permanecem pendentes; algumas mídias antigas já indisponíveis mantêm o aviso existente. IDs LID sem mapeamento conhecido não recebem um número inventado.
- Privacidade avançada, denunciar grupo e uma permissão independente de compartilhar o link de convite não estão expostas pelas operações disponíveis da integração; a interface explica a dependência do WhatsApp, sem indicar sucesso fictício. A criptografia do transporte WhatsApp não implica criptografia ponta a ponta do armazenamento do Chatwoot. Notificações e bloqueio local pertencem ao navegador/Chatwoot.
- Inclusão em comunidade, aprovação de uma solicitação real de entrada e três ou mais pessoas simultaneamente aceitando a chamada não foram confirmadas em teste real. A implementação e testes automatizados cobrem os respectivos caminhos. Recepção de vídeo de grupo no Chatwoot e conversão de voz para vídeo não receberam confirmação visual independente nesta etapa. O usuário confirmou testes anteriores de vídeo com o telefone; isso não substitui o teste específico de cada cenário de grupo.
- MD não tem caixa Whatsmeow pareada: publicação, migração e saúde foram verificadas, sem criar sessão ou afirmar chamada real nessa instância.
- A suíte geral CE/frontend e lint global do fork continuam com falhas em mocks/idiomas/jobs e regras já divergentes da base. Problemas introduzidos nesta entrega identificados na revisão foram corrigidos; o canário direcionado final está aprovado. Não declarar toda a suíte oficial verde.
- A auditoria herdada continua apontando `rack-proxy 0.7.7` por [GHSA-42qh-8mx8-7wqm](https://github.com/ncr/rack-proxy/security/advisories/GHSA-42qh-8mx8-7wqm). Gemfile/lockfile permanecem iguais à base; avaliar a dependência de desenvolvimento em manutenção própria. A divergência de collation principal 2.41/2.36 também é anterior à entrega.

## Backups e retomada

Dumps anteriores à migração nos volumes PostgreSQL de cada instância: `/var/lib/postgresql/data/fork-feature-backups/pre-stars-groups-20261001.dump`, formato custom, listagem `pg_restore -l` conferida. Tamanhos aproximados: principal 48 MB, MX 49 MB e MD 511 KB. São três arquivos em bancos/volumes separados. Não executar `db:schema:load` em produção.

A migração aditiva `20261001090000` deve estar aplicada em todas as bases. Principal/MX mantêm `db:migrate` no início; MD mantém `db:chatwoot_prepare`. Sidekiq MD conserva `zeroDowntime=false`, uma réplica e concorrência 3; filas, reservas, bancos, Redis e credenciais não foram compartilhados ou alterados.

Para retomar, conferir as imagens fixadas e `/health` em cada domínio, saúde Go e sessões pelo serviço correspondente. Preservar a sessão pessoal MX atualmente conectada e as caixas anteriormente desconectadas na principal. Ler este documento antes dos checkpoints anteriores; [upgrade 4.18](whatsmeow-upgrade-v4.18-2026-09-29.md) e [chamadas de setembro](whatsmeow-calls-handoff-2026-09-29.md) continuam como referência histórica. Uma aba que executa JavaScript anterior ao deploy precisa ser recarregada para receber a interface nova.
