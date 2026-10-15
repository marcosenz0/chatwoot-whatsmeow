# Biblioteca de arquivos no cadastro rápido — 15/10/2026

O cadastro rápido mostrava somente os novos uploads, mesmo quando o agente já tinha arquivos. Agora Seus arquivos aparece acima de Arquivos selecionados, com miniaturas quadradas compactas, busca e paginação independentes. Isso permite conferir o acervo antes de subir algo novamente.

Clique em uma miniatura para abrir a imagem inteira ou o player de vídeo existente. Fechar a prévia não seleciona nem anexa aquele item ao lote. Documentos e links exibem a identificação e um link para abrir. Um ícone de globo ou cadeado indica o alcance, com descrição acessível e tooltip, sem rótulo textual sobre a miniatura.

O botão direito abre o menu Chatwoot com Global ou Somente a conversa atual. A alteração é salva imediatamente e atualiza o ícone. Arquivos de outro atendimento e arquivos liberados por contatos continuam identificados; a opção da conversa atual só fica marcada se o ID também coincidir. As abas completas continuam permitindo a edição por contatos.

Os arquivos novos mantêm a seleção múltipla/acumulativa, descrição e disponibilidade individuais, X e alcance por arquivo. O ícone também aparece nas novas miniaturas. O menu de um item salvo nunca o inclui no lote e não reseta os campos dos novos uploads. Cancelar o lote descarta os rascunhos; alterações já confirmadas pelo menu do acervo são independentes.

## Implementação e limites

`SavedResourceLibrary.vue` utiliza os endpoints existentes do agente, com paginação de 24 itens e busca no servidor. A prévia reutiliza Dialog e ResourceVideoPlayer. `AudienceBadge` aceita modo somente ícone, preservando o modo textual anterior. AgentResources apenas integra a biblioteca e recarrega a listagem externa quando um alcance é salvo.

O ContextMenu compartilhado recebeu duas propriedades opcionais, sem mudar o padrão dos menus existentes: destino do teleport e modo topLayer. Na biblioteca, o menu fica no DOM do formulário para respeitar o diálogo e sobe à camada nativa de popover, evitando corte por rolagem ou transformação CSS. Posicionamento, ícones e corpo do menu seguem os componentes do Chatwoot. Shift+F10 abre o menu; setas/Home/End navegam; Escape fecha somente o menu e retorna o foco.

O foco real pode ficar na raiz externa do ContextMenu. Por isso, o componente emite keydown dessa raiz e a biblioteca o trata ali, incluindo eventos que sobem das opções. Escutar apenas a superfície interna deixava Escape chegar ao diálogo e fechar o cadastro. A regressão agora exercita explicitamente a raiz focada, além das opções.

Não houve migração de dados ou mudança no modelo, prompt, voz ou ativação. As restrições do catálogo e do envio continuam no backend da PR49.

## Verificação e publicação

Novas regressões cobrem prévia sem envio, edição de alcance de um único item, promoção de contatos para Global, falha sem alteração visual falsa, teclado, paginação e diferença entre IDs de conversa. Teste integrado confirma que os dados dos novos uploads sobrevivem à atualização da biblioteca e que somente eles entram no lote enviado à API.

Conferência visual local com o CSS real: biblioteca separada, imagem ampliada, vídeo reproduzido até o fim, seleção múltipla, alcance individual e descrição preservada após editar item salvo. Menu e salvar/cancelar conferidos em 640 pixels; override de viewport removido.

Gate final [38750551029](https://github.com/marcosenz0/chatwoot-whatsmeow/actions/runs/38750551029) aprovado: **764 testes direcionados (410 Vue + 354 Rails)**, lint, build e imagem. Principal, MX e MD, incluindo os três workers, publicados na mesma imagem `fork-583c5c0a49be8ae11f7876775c3f20989d135be1`. As três rotas de saúde retornaram 200 e os contratos nativos de arquivos/Pix/avisos passaram com rollback e sem envio de mensagens.

No navegador publicado, a imagem existente carregou em 941 × 1672 e o vídeo de 11,208 s reproduziu até o fim. Upload real de PNG neutro com a disponibilidade para a IA desligada passou por cadastro, prévia e alteração de conversa para Global. Arquivo e checksum foram verificados no servidor; o item temporário 16 foi removido e o acervo voltou aos três originais. Esse percurso foi realizado na primeira imagem da funcionalidade, `04628e2549`; a imagem final acrescenta a correção de teclado e teve o foco real da raiz, Escape, Shift+F10 e setas reconferidos no MD publicado.

Comparação final: 78 estados e perfis idênticos; hashes completos do MD preservados para credenciais, voz, três recursos e seus alcances, memória e uma chave Pix real. Doze configurações de serviços iguais exceto os seis pins de app/worker. Seis bridges e conexões preservadas (WhatsApp `0632806`, Telegram `f78d265`). IA geral desligada; MD92 individualmente ativa, contexto 20. Sem migração, alterações em prompts ou mensagens enviadas por esta tarefa.

Branch `codex/marcoxia-resource-library`, [PR50](https://github.com/marcosenz0/chatwoot-whatsmeow/pull/50) acima da PR49, pronta para revisão e sem merge. Evidências e captura final em HOT ULTRA `operacao/37-marcoxia-biblioteca-cadastro-15-10-2026.md` e `operacao/marcoxia-biblioteca-15-10-2026/validacao-publicacao.json`.
