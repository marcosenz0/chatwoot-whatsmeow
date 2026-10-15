# Central da IA e alcance de arquivos, Pix e avisos

Marco aprovou a quarta proposta visual em 14/10/2026: cabeçalho compacto, ações de revisão, controles recolhidos, atalhos em três cartões, memória e pendências expansíveis. O título passou a Central da IA. A preparação de resposta continua exigindo revisão antes do envio, inclusive para áudio.

O botão Global começa desligado a cada abertura do painel. Ele define o alcance de novas inclusões feitas pelos atalhos:

- Desligado: apenas a conversa aberta.
- Ligado: todas as conversas do agente selecionado, dentro da mesma conta.

O botão não altera itens já salvos nem ativa a IA. Ativação, pausa automática, histórico e memória continuam sendo controles da conversa. O atalho Avisos permite editar números existentes e adicionar outro.

Nas abas completas do agente, arquivos, chaves Pix e números de aviso exibem e editam o alcance: Global, uma conversa específica ou contatos selecionados. O seletor de contatos permite adicionar e remover pessoas. Cada arquivo de um lote mantém descrição, disponibilidade e alcance independentes. O limite de duas chaves Pix ativas por agente permanece.

## Implementação

`MarcosxAiAudience` é compartilhado por recursos, chaves Pix e destinatários de aviso. A migração adiciona `audience`, `contact_ids` e referência à conversa; itens anteriores recebem Global. A API aceita o `display_id` da conversa e resolve a chave interna somente na conta atual. Contatos de outra conta, conjuntos vazios ou duplicados e formatos inválidos são rejeitados.

Os catálogos de arquivos e Pix são filtrados antes de entrar no prompt. A resposta estruturada valida a elegibilidade, e `DeliveryJob` consulta novamente o alcance antes da entrega. Assim, revogar o contato durante uma espera também impede o envio. Fora de uma conversa real, a prévia do prompt e o playground expõem somente itens globais.

A primeira chave Pix elegível é apresentada ao modelo como principal naquele atendimento, mesmo se a principal geral não estiver liberada para o contato. Isso não muda a ordem ou a disponibilidade persistida das chaves.

Os números de aviso ficam em `marcosx_ai_notification_targets`, com caixa WhatsApp, disponibilidade e alcance próprios. `NotificationRecipients` preserva os destinatários antigos como globais; a conversão para registro acontece quando o responsável os edita. O envio resolve os números permitidos para o contato e a caixa de origem de cada um. O job cancela avisos pendentes quando o destinatário deixa de ser permitido.

Nenhuma destas alterações muda o prompt editorial, a personalidade, a configuração de voz, a pausa ou a ativação de perfis existentes. As alterações de prompt são a filtragem dos catálogos. As restrições de envio ficam no servidor.

## Verificação

757 verificações direcionadas (403 Vue e 354 Rails), compilação, lint e publicação da imagem final aprovados no gate 38664233859. Inclui regressões de áudio revisado, presença, Pix nativo, arquivos em lote, memória e ativação.

Conferência visual com o CSS real: estrutura aprovada, menus com ícones e seta inteira, seleção e remoção de contatos, teclado e Escape. Em 640 px, os editores rolam mantendo salvar e cancelar acessíveis; os menus internos podem ocupar o fluxo do formulário para evitar corte pela área de rolagem. Os atalhos esperam o catálogo inicial antes de abrir, para respeitar as chaves ativas e preencher a caixa de avisos corretamente.

## Publicação concluída em 15/10/2026

Principal, MX e MD, incluindo os três workers, usam `ghcr.io/marcosenz0/chatwoot-whatsmeow:fork-71d732716f2596c0a309464c70fa9c5fb72db0f9`, imagem executada `sha256:f583b1fdf0448fd8cfa515786948e8508321d905959ab25248abe18729339b33`. Os três `/health` retornaram 200. Aplicada primeiro a migração aditiva pelo `MigrationContext.up`, depois worker e web em cada instalação, para evitar novos itens restritos enquanto houvesse worker antigo.

Os contratos nativos publicados passaram nas três instalações: criar, editar e excluir arquivos, Pix e números; resolver o ID público da conversa; impedir exposição para outro contato; rejeitar seleção vazia; mudar para Global; buscar contatos e rotear avisos. Todos os registros de teste ficaram dentro de transação revertida. Não houve envio de mensagens ou avisos, uso de LLM nem teste financeiro. A primeira verificação no MX comparou a contagem total de mensagens e encontrou tráfego de entrada concorrente; o probe foi corrigido para observar escritas SQL em mensagens pelo próprio processo, e passou sem nenhuma escrita.

Comparação final: os 78 estados de conversa e os dois perfis ficaram idênticos; principal 9, MD 69, MX 0. Atendimento geral continua desligado; MD92 permanece ativa com contexto de 20 mensagens. As 12 configurações de serviço mudaram apenas nos seis pins de web/worker. Credencial, credencial de voz, três recursos, memória de contato e cadastro Pix do MD conservaram os hashes. Os três recursos anteriores receberam Global; nenhum novo número ou Pix de teste ficou cadastrado.

As seis bridges conservaram os mesmos containers e imagens: WhatsApp `0632806ba01bdc63e6dd8ddc10af2d9466f0b60f`, Telegram `f78d26565c6a638e3639cbecf91f8e5347d5fdb4`. Sessões conectadas e desconexões anteriores preservadas; não reverter a correção WhatsApp 479.

UI publicada conferida primeiro na principal e depois no MD92: layout, Global desligado, padrão local no Pix, padrão Global em novo link, gerenciador de aviso existente, badges na biblioteca e adição/remoção de contato no editor sem salvar a alteração. Capturas em HOT ULTRA/operacao/design-painel-ia-14-10-2026: `central-publicada-principal.png`, `central-publicada-md.png`, `alcance-pix-publicado.png`, `arquivos-alcance-publicado.png`, `contatos-editor-publicado.png`. PR49 acima da PR48, sem merge. Mudanças preexistentes do checkout geral preservadas.
