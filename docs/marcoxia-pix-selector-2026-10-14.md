# Seletor Pix no padrão do Chatwoot — 14/10/2026

O cadastro de chaves por agente usava um select do navegador: a seta era cortada pelo estilo global e as opções abriam com o desenho do Windows. Agora usa `AiSelect`, o menu do próprio Chatwoot, com ícones de celular, CPF, e-mail e chave aleatória, seleção marcada e chevron separado do texto. O menu permanece dentro da camada do diálogo e acompanha a largura do campo. Escape fecha o menu e devolve o foco ao seletor, sem abandonar o cadastro.

A regra permanente está no início de `AGENTS.md`, tanto nesta branch quanto no checkout principal do fork. Interfaces futuras devem reutilizar os componentes visuais existentes, sem introduzir selects nativos, e conferir ícones, seta, menu aberto, teclado e largura menor com o CSS real.

Validação local: sete testes do cadastro passaram, incluindo escolha/salvamento do tipo, ícones, teclado e Escape. Lint sem erros. Prévia com o CSS do Chatwoot conferida no Chrome em largura normal e 640 px: quatro opções visíveis e seta inteira. A prévia usa apenas dados fictícios. Nenhum envio de mensagem é necessário para esta alteração visual.

Publicação nas três instalações e auditoria final: em andamento. Base: PR47 e imagens/bridges preservadas de sua entrega; não voltar à bridge anterior à correção do erro 479.
