# Links nas descrições e lista compacta de membros — 02/10/2026

Solicitação adicional aos ajustes de interface anteriores. Implementação em `codex/whatsmeow-group-links-members`, worktree isolado; [PR #27](https://github.com/marcosenz0/chatwoot-whatsmeow/pull/27).

## Comportamento

- Descrições do painel são texto preservado, com quebras de linha e links clicáveis. O mesmo conteúdo é clicável nas configurações quando a descrição é somente leitura; a edição continua dependente das permissões do WhatsApp.
- Sites externos usam outra aba, com `noopener/noreferrer`. Convites de grupo usam a prévia existente e exigem a ação explícita de entrar. Links diretos `wa.me`, `api.whatsapp.com/send` e `web.whatsapp.com/send` oferecem a abertura de conversa no canal atual. Abrir a prévia não envia mensagens nem entra no grupo.
- Dono e administradores têm prioridade na lista lateral, limitada a nove membros. **Ver tudo (mais N)** e o ícone de pesquisa abrem a lista completa em janela própria, com pesquisa por nome/número. Fechar a janela mantém a lista lateral limitada.
- As linhas dos membros recebem destaque ao passar o mouse ou focar. Clicar abre um menu com Dados do contato, Código de segurança e Conversar com o nome salvo ou número. Dados exibe nome, telefone, foto e função disponíveis; a conversa usa o inbox atual e as identidades PN/LID existentes. O menu usa popover nativo, ancorado à linha, dentro do diálogo quando aberto.
- O componente de membro é compartilhado pela prévia e pela janela. Remover/promover/rebaixar continuam restritos aos administradores e ao contrato existente.
- O renderizador existente de mensagens aceita um inbox explícito e texto simples para reutilização nas descrições. A formatação normal das mensagens permanece no seu contexto. As prévias usam diálogos nativos para funcionar também sobre a janela de configurações; caches de número/convite são separados por inbox.
- Inglês e português brasileiro acompanham a implementação. Nenhuma migração ou alteração de Go foi necessária.

## Limitação do código de segurança

O provedor atual não expõe o código de segurança do WhatsApp. A opção informa essa limitação e orienta a conferência no aplicativo WhatsApp, em Dados do contato → Criptografia. Nenhum código é gerado artificialmente; nenhuma identidade ou chave de sessão é alterada.

## Validação e publicação

Publicado em principal, MX e MD. Revisão `9fe40d2c82c7499696b42f945ca4afa6fcbb4704`, [canário 37009805280](https://github.com/marcosenz0/chatwoot-whatsmeow/actions/runs/37009805280) concluído com sucesso.

O canário passou com 156 testes JavaScript em 17 arquivos, 330 exemplos Rails sem falhas e 14 arquivos Ruby sem infrações. Os testes locais de links/formatação/expansão passaram (55 exemplos), assim como o painel e os três casos de ações dos membros. Lint dos arquivos alterados: zero erros; avisos de chaves dinâmicas de i18n. O lint geral e verificações gerais do repositório continuam com falhas anteriores; não são apresentados como verdes.

A publicação ocorreu primeiro na principal, com validação visual, e depois da mesma imagem para MX e MD. Os seis serviços web/Sidekiq usam `fork-9fe40d2c82c7499696b42f945ca4afa6fcbb4704`, manifest `sha256:293b3e82225afd6be72b620c2e4adca2ba5977b9b878da799e258f3d687a8dad`, ImageID `sha256:33cf2c3b7e31eb00f2e4f5a75df7bd5895251048d3ef641d6b2e98c7ffdcfaef`. Os três containers Go mantiveram os mesmos IDs e a imagem `whatsmeow-54aae63ad477bc6d5bf0077a091a1a9ac7c0efa2`, sem reinício.

- Principal: sessão habitual do navegador preservada; canais 27/15/28 conectados, 23/10 já desconectados; três favoritas e zero pendentes. Nenhuma migração pendente e saúde Go confirmada.
- MX: sessão pessoal do canal 1 conectada; 69 favoritas, cinco aguardando originais, como antes. Nenhuma migração pendente e saúde Go confirmada.
- MD: página de conversa carregada e saúde Go confirmada; não possui inbox Whatsmeow, portanto não houve teste de grupo ao vivo nesta instância.
- Bancos, configurações, domínios e segredos permaneceram separados. Preferências extras de favoritos/listas/temas continuam ausentes. Chatwoot oficial fora do escopo.

No navegador, a principal confirmou nove membros com prioridade de dono/admin, busca por nome e número na janela completa, retorno à lista sem expansão e descrição com Ler mais/Ler menos. Links externos abriram outra aba; convites abriram a prévia nativa, inclusive sobre configurações somente leitura, sem entrar em grupos públicos. Link direto abriu a prévia de conversa. A descrição do grupo de teste usada nessa verificação foi restaurada.

O menu recebeu destaque cinza, ícones à esquerda e rótulo com nome salvo. Dados do contato e Código de segurança abriram diálogos próprios; fechar retornou à lista com a busca preservada. Foi corrigido o envio acidental do formulário pelos botões do menu usando `type="button"`. Conversar com abriu um número de teste autorizado no mesmo inbox do grupo, sem enviar mensagem. MX confirmou nove membros, prioridade de dono/admin, busca e menu em português na versão final. Não houve alteração de funções administrativas.
