# Seletor Pix no padrão do Chatwoot — 14/10/2026

O cadastro de chaves por agente usava um select do navegador: a seta era cortada pelo estilo global e as opções abriam com o desenho do Windows. Agora usa `AiSelect`, o menu do próprio Chatwoot, com ícones de celular, CPF, e-mail e chave aleatória, seleção marcada e chevron separado do texto. O menu permanece dentro da camada do diálogo e acompanha a largura do campo. Escape fecha o menu e devolve o foco ao seletor, sem abandonar o cadastro.

A regra permanente está no início de `AGENTS.md`, tanto nesta branch quanto no checkout principal do fork. Interfaces futuras devem reutilizar os componentes visuais existentes, sem introduzir selects nativos, e conferir ícones, seta, menu aberto, teclado e largura menor com o CSS real.

Validação local: sete testes do cadastro passaram, incluindo escolha/salvamento do tipo, ícones, teclado e Escape. Lint sem erros. Prévia com o CSS do Chatwoot conferida no Chrome em largura normal e 640 px: quatro opções visíveis e seta inteira. A prévia usa apenas dados fictícios. Nenhum envio de mensagem é necessário para esta alteração visual.

Publicação concluída no principal, MX e MD, incluindo os três workers, com a mesma imagem `ghcr.io/marcosenz0/chatwoot-whatsmeow:fork-bbb72873c79a70f8b7b63b43515feea05146457e`. Gate `38646681385` aprovado: 397 testes de interface e 340 Rails, lint, compilação e imagem. Digest do manifesto `sha256:6e45e846e8ebfdf8de69027b19224dd168e815d8e958680b753663aba6db80ac`; imagem em execução `sha256:3bb4ac7ec8c375d4aacfe14380d77628a461742679c5016d52e4e5fb46170dd2` nos seis processos. Todas as instalações responderam 200 após iniciar.

Principal conferido primeiro: quatro opções, seleção do tipo e ícones corretos no cadastro publicado. MD/Atendente HOT1 também conferido, incluindo seleção, teclado e Escape. Nenhum select nativo restante nesse diálogo. MX recebeu exatamente o mesmo artefato; não possui agente cadastrado e nenhum foi criado apenas para a conferência.

Auditoria: 78 estados de conversa e todos os perfis idênticos ao estado anterior; credenciais, voz, três recursos, memória e cadastro Pix do MD com hashes preservados. Doze configurações de serviços comparadas: só os seis pins de apps/workers mudaram; as seis bridges mantiveram configuração, imagens e containers. As três WhatsApp continuam na 0632806 que corrigiu o erro479; Telegram permanece na f78d265. Nenhuma mensagem enviada, chave cadastrada ou política de atendimento alterada nesta tarefa.

Houve uma resposta 404 transitória do painel durante a atualização do worker MD; a leitura do estado mostrou o web já atualizado e o worker ainda anterior. Repetida somente a atualização do worker, concluída e conferida na auditoria. A construção completa demorou cerca de 23 min; os testes já estavam aprovados antes disso.

Capturas no HOT ULTRA: `operacao/marcoxia-seletor-pix-principal-14-10-2026.jpg` e `operacao/marcoxia-seletor-pix-publicado-14-10-2026.jpg`. PR48 baseada na47, sem merge. Para abas antigas, recarregar com Ctrl+F5.
