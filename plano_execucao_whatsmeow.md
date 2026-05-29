# Plano de Execução Autônomo: Chatwoot + Whatsmeow (WhatsApp Direct)

Este documento estabelece o roteiro técnico e as diretrizes necessárias para iniciarmos a criação do canal Whatsmeow integrado nativamente ao seu Chatwoot no próximo chat. O plano foi desenhado para ser executado **100% de forma autônoma** por mim (IA) durante a sua ausência, sem que você precise intervir em nenhuma etapa técnica.

---

## 🔗 Informações de Repositório e Infraestrutura (100% Configurado e Validado ✅)

* **Seu Fork Oficial no GitHub:** `https://github.com/marcosenz0/chatwoot-whatsmeow`
* **GitHub Personal Access Token (PAT):** Configurado com sucesso em `chatwoot_mcp_config.json` (permissão total de leitura/escrita para automatizar commits e pushes).
* **Easypanel tRPC API Token:** Já integrado e funcional (permissão total para criar e gerenciar a stack de Staging).
* **Hostinger API Token:** Já disponível no ecossistema (permite à IA criar registros DNS automaticamente para o subdomínio de homologação).
* **Banco de Dados Postgres:** Mapeado e acessível na VPS.

---

## 🛠️ O Roteiro de Execução Autônoma (Fases do Projeto)

No próximo chat, sob o comando `/goal`, executarei sequencialmente todas as etapas listadas abaixo:

### Fase 1: Clonagem do Fork e Setup Local
1. Clonar o seu fork `marcosenz0/chatwoot-whatsmeow` utilizando o token autenticado.
2. Configurar o repositório upstream oficial do Chatwoot para manter as pontes de atualização futuras.
3. Configurar as branches e preparar as modificações.

### Fase 2: Configuração de DNS e Staging na VPS
1. **DNS Automático via Hostinger API:** Criar registros CNAME/A para os subdomínios de homologação:
   * `staging-crm.marcoswt.com.br` -> Apontando para o IP da sua VPS.
   * `staging-api.marcoswt.com.br` -> Apontando para o IP da sua VPS.
2. **Criação da Stack Staging no Easypanel:**
   * Criar o projeto `marcos-apps-staging`.
   * Criar o serviço `chatwoot-staging` (ligado ao seu fork).
   * Criar o banco de dados `chatwoot-staging-db` (PostgreSQL) e o cache `chatwoot-staging-redis`.

### Fase 3: Desenvolvimento do Serviço Whatsmeow Go (`whatsmeow-service`)
1. Escrever o microsserviço Go completo na pasta auxiliar.
2. Implementar as tabelas de sessão no Postgres (`whatsmeow_sessions`) usando GORM.
3. Desenvolver os endpoints internos para gerar QR Code, enviar mensagens e acompanhar os WebSockets do WhatsApp.
4. Programar o webhook de callbacks direcionado ao Rails.

### Fase 4: Customização do Backend Rails e Frontend VueJS
1. Criar as migrations Rails para o canal `Channel::Whatsmeow`.
2. Criar a rota de Callback no Rails para receber novas mensagens e logs de chamadas perdidas.
3. Desenvolver os componentes VueJS nativos no Chatwoot para exibir o QR Code em tempo real no fluxo de criação de canais de atendimento.

### Fase 5: Deploy e Validação Interna
1. Disparar o deploy de toda a stack no Easypanel.
2. Rodar testes de estresse internos e validar se a API de Staging está respondendo com o QR Code.

---

## 🚀 Como Iniciar no Próximo Chat

Quando você retornar e quiser que eu inicie todo o projeto e execute tudo sozinho, basta abrir um **novo chat** nesta mesma pasta e digitar:

> **/goal Baixe meu fork do Chatwoot do GitHub, crie a infraestrutura de Staging na VPS com DNS na Hostinger e implemente de forma completa e testada a integração com Whatsmeow em Go, conforme o plano no arquivo `plano_execucao_whatsmeow.md`. Só me chame quando o QR Code de homologação estiver pronto para eu escanear!**
