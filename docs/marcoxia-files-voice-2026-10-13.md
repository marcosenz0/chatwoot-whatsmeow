# MarcoXIA: arquivos por agente e voz ocasional — 13/10/2026

Marco autorizou conectar a chave fornecida da ElevenLabs ao Atendente HOT 1, somente no MD, selecionar voz feminina e testar. Pediu áudio a pedido, em dificuldade de leitura e ocasionalmente conforme contexto, com preferência por texto. Também pediu uma aba Arquivos logo abaixo de Instruções, com imagens, vídeos e links descritos para a IA selecionar e enviar quando solicitados.

## Implementação e limites

Catálogo próprio do MarcoXIA, separado dos documentos de conhecimento do Captain. Arquivos nativos ActiveStorage, título/descrição/tipo, link HTTP(S) literal e disponibilidade por item. Administração por conta e agente; 24 itens por página, busca, até 100 itens por agente, 40 MB por arquivo. JPG/PNG/WebP/GIF, MP4/WebM/MOV, PDF/TXT. Miniaturas carregadas sob demanda. Remover um item não apaga os anexos já enviados.

O modelo recebe apenas os metadados do catálogo ativo e devolve até três IDs. O servidor valida propriedade/disponibilidade, resolve o arquivo/link cadastrado e entrega pelo pipeline normal, mantendo remetente, assinatura, pausa manual e idempotência de partes. Não lê automaticamente os pixels/conteúdo desses arquivos: o responsável deve descrevê-los. Não gera fotos, tabelas ou links inexistentes. Não há cadastro de conteúdo de clientes nem alteração de identidade ou prompts editoriais.

Áudio contextual tem intervalo editável em respostas completas, sem contar cada bolha separada como um turno. Pedidos diretos de áudio/dificuldade de leitura podem ignorar esse intervalo; preferência explícita por texto é respeitada. Tamanho de explicações longas é uma orientação configurável para a escolha do modelo. A maioria das respostas permanece em texto. Falha de voz preserva texto. URLs continuam copiáveis.

Prévia real no MD: chave salva pelo endpoint nativo com criptografia confirmada, voz feminina Jessica, Multilingual v2, português; HTTP200, 94.084 bytes MP3, 5,85 segundos. Voz mantida desabilitada durante preparação do código. A conta verificada é Free. Chave, prompts completos e logs privados nunca devem entrar no Git ou handoff.

Testar agente simula seleção de arquivos e fala sem envio/síntese. Rascunhos do editor e análise para revisão continuam como texto, sem enviar anexos ocultos. Responder agora e mensagens recebidas usam a entrega automática completa.

## Validação e entrega

Em andamento: testes de isolamento/CRUD/upload, envio de anexos/links sem duplicação, intervalo de voz, preferências e renderização desktop/mobile; gate e publicação pendentes.

Configurar voz somente no Atendente HOT 1 do MD, preservar geral desligado e todas as ativações vigentes. Código compartilhado deve ser validado no principal antes de publicar a mesma imagem no MX/MD. Bridges, sessões, domínios, mounts e chaves existentes ficam preservados. Sem mensagens de teste a clientes.
