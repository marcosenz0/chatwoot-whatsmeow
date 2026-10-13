# MarcoXIA: arquivos por agente e voz ocasional — 13/10/2026

Marco autorizou conectar a chave fornecida da ElevenLabs ao Atendente HOT 1, somente no MD, selecionar voz feminina e testar. Pediu áudio a pedido, em dificuldade de leitura e ocasionalmente conforme contexto, com preferência por texto. Também pediu uma aba Arquivos logo abaixo de Instruções, com imagens, vídeos e links descritos para a IA selecionar e enviar quando solicitados.

## Implementação e limites

Catálogo próprio do MarcoXIA, separado dos documentos de conhecimento do Captain. Arquivos nativos ActiveStorage, título/descrição/tipo, link HTTP(S) literal e disponibilidade por item. Administração por conta e agente; 24 itens por página, busca, até 100 itens por agente, 40 MB por arquivo. JPG/PNG/WebP/GIF, MP4/WebM/MOV, PDF/TXT. Miniaturas carregadas sob demanda. Remover um item não apaga os anexos já enviados.

O modelo recebe apenas os metadados do catálogo ativo e devolve até três IDs. O servidor valida propriedade/disponibilidade, resolve o arquivo/link cadastrado e entrega pelo pipeline normal, mantendo remetente, assinatura, pausa manual e idempotência de partes. Não lê automaticamente os pixels/conteúdo desses arquivos: o responsável deve descrevê-los. Não gera fotos, tabelas ou links inexistentes. Não há cadastro de conteúdo de clientes nem alteração de identidade ou prompts editoriais.

Áudio contextual tem intervalo editável em respostas completas, sem contar cada bolha separada como um turno. Pedidos diretos de áudio/dificuldade de leitura podem ignorar esse intervalo; preferência explícita por texto é respeitada. Tamanho de explicações longas é uma orientação configurável para a escolha do modelo. A maioria das respostas permanece em texto. Falha de voz preserva texto. URLs continuam copiáveis.

Prévia real no MD: chave salva pelo endpoint nativo com criptografia confirmada, voz feminina Jessica, Multilingual v2, português; HTTP200, 94.084 bytes MP3, 5,85 segundos. Após a implantação, voz ativada somente no Atendente HOT 1 do MD: contextual, intervalo seis respostas completas por texto, orientação de explicação longa de 450 caracteres e limite de 1.200 por áudio, sem duplicar a fala em texto. Pedidos diretos ignoram o intervalo. A conta verificada é Free. Chave, prompts completos e logs privados nunca devem entrar no Git ou handoff.

Testar agente simula seleção de arquivos e fala sem envio/síntese. Rascunhos do editor e análise para revisão continuam como texto, sem enviar anexos ocultos. Responder agora e mensagens recebidas usam a entrega automática completa.

## Validação e entrega

Gate [38408784318](https://github.com/marcosenz0/chatwoot-whatsmeow/actions/runs/38408784318): **683 testes direcionados** (374 Vue + 309 Rails), lint, build e publicação aprovados. [PR42](https://github.com/marcosenz0/chatwoot-whatsmeow/pull/42) pronta para revisão, aberta acima da PR41; sem merge. Imagem de código `ghcr.io/marcosenz0/chatwoot-whatsmeow:fork-85c605ce42bafa4f97a9dbd9c23a5fc6382b7b0a`, imagem efetiva `sha256:e3703d37fbc2371969cad0ec2abe04cde096ef059fbfd54a56ad4c770e837bf0`.

Principal conferido primeiro; mesma imagem aplicada aos seis web/workers principal/MX/MD. SHA efetivo, tabelas de voz/arquivos e criptografia confirmados; saúde HTTP200. Auditoria compara 12 configurações de serviço preservadas exceto as seis imagens autorizadas, seis containers de bridges intactos e sessões conectadas preservadas. Antes de ativar a voz, os perfis brutos e **77 estados vigentes** (principal8/MD69/MX0) eram idênticos. Geral continua desligado, principal2170 pausado e MD92 individual ativo/contexto20. Ativação da voz alterou somente sua configuração no MD.

Contratos reais de cadastro, busca, atualização, exclusão e upload multipart testados no dono do principal e no MD, com isolamento e rollback integral. No MD, um incoming neutro temporário passou pelo agendador e pelo ConversationResponderService do Atendente HOT 1: modelo real preparou áudio, selecionou o link correto do catálogo, não solicitou handoff, e ElevenLabs gerou MP3 de 32.226 bytes/1,985 segundos. DeliveryJob foi apenas enfileirado em adaptador de teste; sem execução ou mensagem de teste ao WhatsApp. Todas as alterações do probe foram revertidas.

Prévia Vue com fixtures conferida em desktop e 390px, incluindo formulário e mudança de arquivo para link, sem rolagem horizontal. Após publicação, a interface real autenticada do MD mostrou Arquivos abaixo de Instruções, biblioteca vazia e Voz e áudio com chave salva, ElevenLabs e permissão ativa. Marco fará a confirmação de recebimento no WhatsApp.

Para testar: na conversa do próprio Marco, confirmar IA ligada/Atendente HOT 1 e enviar **“Emilly, fala comigo em áudio; não sei ler.”** Se houver mensagem já pendente ao ligar, usar **Responder agora**. Em Arquivos, adicionar os itens reais, descrever precisamente quando usá-los e manter disponíveis. Exemplo neutro: título “Tabela”, descrição “Imagem da tabela; enviar quando pedirem a tabela.” Testar agente continua como simulação privada; não confirma síntese ou recebimento no canal.

Preservar geral desligado e todas as ativações vigentes. Não cadastrar automaticamente mídias de outras tarefas nem inventar arquivos. Conteúdo real do catálogo ainda será escolhido e cadastrado por Marco. Não desligar o computador: a solicitação noturna anterior foi concluída antes desta nova tarefa.
