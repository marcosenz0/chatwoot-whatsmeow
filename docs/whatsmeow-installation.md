# Guia de instalacao do Chatwoot com Whatsmeow

Este documento explica como instalar e manter este fork pessoal do Chatwoot com WhatsApp Direct via `whatsmeow-service`.

O estado atual do canario de chamadas nas tres instancias e as pendencias para retomar a PR #21 estao em [whatsmeow-calls-handoff-2026-09-29.md](whatsmeow-calls-handoff-2026-09-29.md).

Use este guia quando quiser subir o projeto no PC local, Docker, Easypanel ou Portainer. O fluxo principal continua sendo pelo GitHub, no branch `develop`.

## O que este fork tem

Este projeto e um fork do Chatwoot com um canal extra chamado WhatsApp Direct, implementado com `whatsmeow`. A ideia e conectar um WhatsApp real por QR Code diretamente no Chatwoot, sem Evolution API, sem provedor externo e sem ponte intermediaria.

Componentes principais:

- `rails`: interface web e API do Chatwoot.
- `sidekiq`: filas e processamento em segundo plano.
- `postgres`: banco principal do Chatwoot e sessoes do Whatsmeow.
- `redis`: filas/cache do Chatwoot.
- `whatsmeow-service`: servico Go que pareia o celular, recebe eventos do WhatsApp e envia mensagens.
- `ffmpeg`: necessario no container Go para converter/normalizar audio.

O Chatwoot fala com o Go por `WHATSMEOW_SERVICE_URL`.
O Go devolve mensagens para o Chatwoot por `WEBHOOK_URL`.

## Repositorio e imagens

Branch de trabalho:

```bash
develop
```

Imagem Docker do Chatwoot fork gerada pelo GitHub Actions:

```bash
ghcr.io/marcosenz0/chatwoot-whatsmeow:develop
```

### Baixar a versao completa em outro PC

O repositorio e publico e o branch padrao ja e o `develop`. Em um computador novo, use:

```bash
git clone --branch develop --single-branch https://github.com/marcosenz0/chatwoot-whatsmeow.git
cd chatwoot-whatsmeow
docker pull ghcr.io/marcosenz0/chatwoot-whatsmeow:develop
```

Para atualizar uma instalacao que ja foi clonada:

```bash
git switch develop
git pull --ff-only origin develop
docker pull ghcr.io/marcosenz0/chatwoot-whatsmeow:develop
```

No Docker Desktop, use essa imagem tanto no servico web quanto no Sidekiq. O `whatsmeow-service` fica no mesmo repositorio e deve ser construido pelo Dockerfile em `whatsmeow-service/`, conforme o exemplo de Docker Compose deste guia.

Importante: nao use `chatwoot/chatwoot:latest` para este fork. Essa imagem e do Chatwoot original e nao contem a integracao Whatsmeow.

O arquivo `docker-compose.production.yaml` original do projeto pode servir como referencia de estrutura, mas precisa trocar a imagem do Chatwoot e adicionar o servico `whatsmeow-service`.

## Variaveis obrigatorias

### Chatwoot web e Sidekiq

Use as mesmas variaveis no container web e no container Sidekiq:

```env
RAILS_ENV=production
NODE_ENV=production
INSTALLATION_ENV=docker
FRONTEND_URL=https://chatwoot.seu-dominio.com.br
SECRET_KEY_BASE=gere_um_valor_seguro

POSTGRES_HOST=postgres
POSTGRES_PORT=5432
POSTGRES_DATABASE=chatwoot
POSTGRES_USERNAME=postgres
POSTGRES_PASSWORD=senha_segura

REDIS_URL=redis://:senha_redis@redis:6379
REDIS_PASSWORD=senha_redis

RAILS_LOG_TO_STDOUT=true
RAILS_SERVE_STATIC_FILES=true

WHATSMEOW_SERVICE_URL=http://whatsmeow:8080
WHATSMEOW_SERVICE_TIMEOUT=60
WHATSMEOW_STATUS_TIMEOUT=330
WHATSMEOW_SHARED_SECRET=gere_outro_valor_longo_e_aleatorio
```

`WHATSMEOW_SERVICE_URL` tambem aceita mais de uma URL separada por virgula, o que ajuda quando o Easypanel muda o nome interno do servico:

```env
WHATSMEOW_SERVICE_URL=http://whatsmeow:8080,http://marcos-apps_whatsmeow-staging:8080
```

### Whatsmeow service

```env
PORT=8080
DATABASE_URL=postgres://postgres:senha_segura@postgres:5432/chatwoot?sslmode=disable
WEBHOOK_URL=http://rails:3000/api/v1/accounts/%s/whatsmeow/%s/callback
WHATSMEOW_STATUS_SEND_TIMEOUT_SECONDS=300
WHATSMEOW_SHARED_SECRET=use_exatamente_o_mesmo_valor_do_chatwoot
```

O `DATABASE_URL` do Go deve apontar para o mesmo Postgres do Chatwoot. Nao confie em fallback interno.

O `WEBHOOK_URL` precisa manter os dois `%s`. O primeiro recebe o ID da conta e o segundo recebe o ID da caixa de entrada/canal.

Em producao, prefira URL interna entre containers, por exemplo `http://rails:3000/...`. Use URL publica somente se os containers nao estiverem na mesma rede.

`WHATSMEOW_SHARED_SECRET` precisa ser identico no Chatwoot web, Sidekiq e whatsmeow-service. Sem ele, as rotas internas retornam `503`; `/health`, a consulta de estado da sessao, a verificacao de numero e a foto de perfil continuam publicas para preservar o monitoramento e as automacoes documentadas.

## Instalacao local sem Docker

Use este modo para desenvolvimento e correcao rapida.

1. Instale dependencias locais:

```bash
rbenv install $(cat .ruby-version)
eval "$(rbenv init -)"
bundle install
corepack enable
pnpm install
```

2. Garanta tambem:

- PostgreSQL com extensoes exigidas pelo Chatwoot.
- Redis.
- Go compativel com `whatsmeow-service/go.mod`.
- `ffmpeg` disponivel no PATH.

3. Configure `.env` do Chatwoot com:

```env
WHATSMEOW_SERVICE_URL=http://localhost:8080
```

4. Prepare o banco:

```bash
bundle exec rails db:chatwoot_prepare
```

5. Rode o Chatwoot:

```bash
overmind start -f Procfile.dev
```

Se preferir, rode web, Vite e Sidekiq separadamente seguindo o padrao do projeto.

6. Em outro terminal, rode o Go:

```bash
cd whatsmeow-service
go mod download
PORT=8080 DATABASE_URL="postgres://postgres:senha@localhost:5432/chatwoot?sslmode=disable" WEBHOOK_URL="http://localhost:3000/api/v1/accounts/%s/whatsmeow/%s/callback" go run .
```

No PowerShell:

```powershell
cd whatsmeow-service
$env:PORT="8080"
$env:DATABASE_URL="postgres://postgres:senha@localhost:5432/chatwoot?sslmode=disable"
$env:WEBHOOK_URL="http://localhost:3000/api/v1/accounts/%s/whatsmeow/%s/callback"
go run .
```

7. Teste:

```bash
curl http://localhost:8080/health
```

Depois acesse o Chatwoot, crie uma caixa de entrada WhatsApp Direct, gere o QR Code e escaneie no celular.

## API de chave Pix para Chatwoot e n8n

Todas as rotas abaixo usam a autenticacao normal da API do Chatwoot:

```http
api_access_token: SEU_TOKEN_DE_ACESSO
Content-Type: application/json
```

Os tipos aceitos sao `PHONE`, `CPF`, `EMAIL` e `EVP` (chave aleatoria). A configuracao pertence a inbox Whatsmeow compartilhada; somente administradores podem altera-la. Agentes atribuidos a inbox podem consultar e enviar a chave.

Consultar a configuracao:

```http
GET /api/v1/accounts/{account_id}/inboxes/{inbox_id}/whatsmeow_pix
```

Se o agente acessa a conversa pela equipe, sem ser membro direto da inbox, acrescente `?conversation_id={conversation_id}` na consulta. Tokens de AgentBot precisam estar vinculados a inbox de destino.

Salvar ou substituir a configuracao:

```http
PATCH /api/v1/accounts/{account_id}/inboxes/{inbox_id}/whatsmeow_pix

{
  "key_type": "EMAIL",
  "key": "financeiro@empresa.com.br",
  "merchant_name": "Empresa Exemplo"
}
```

Remover a configuracao:

```http
DELETE /api/v1/accounts/{account_id}/inboxes/{inbox_id}/whatsmeow_pix
```

Enviar a chave configurada para uma conversa:

```http
POST /api/v1/accounts/{account_id}/conversations/{conversation_id}/messages/pix

{}
```

Para um envio avulso pelo n8n, envie os mesmos tres campos no `POST`. Isso nao altera a configuracao da inbox:

```json
{
  "key_type": "EVP",
  "key": "123e4567-e89b-42d3-a456-426614174000",
  "merchant_name": "Empresa Exemplo"
}
```

Uma resposta bem-sucedida e o objeto padrao de mensagem do Chatwoot. Erros de validacao usam um formato estavel para automacoes:

```json
{
  "error": {
    "code": "invalid_pix_payload",
    "message": "Key is invalid"
  }
}
```

O `POST` cria primeiro a mensagem no historico do Chatwoot e o Sidekiq envia o Native Flow `payment_info` ao WhatsApp pelo `whatsmeow-service`. Por isso, web e Sidekiq devem executar a mesma imagem e o servico Go deve ser atualizado junto.

## Instalacao local com Docker Compose

Use este modo quando quiser simular mais de perto o ambiente de servidor.

Exemplo de servico extra para adicionar ao compose local:

```yaml
services:
  whatsmeow:
    build:
      context: ./whatsmeow-service
    environment:
      PORT: 8080
      DATABASE_URL: postgres://postgres:senha_segura@postgres:5432/chatwoot?sslmode=disable
      WEBHOOK_URL: http://rails:3000/api/v1/accounts/%s/whatsmeow/%s/callback
      WHATSMEOW_STATUS_SEND_TIMEOUT_SECONDS: 300
      WHATSMEOW_SHARED_SECRET: ${WHATSMEOW_SHARED_SECRET}
    ports:
      - "8080:8080"
    depends_on:
      - postgres
      - rails
```

No `.env` usado pelo Rails/Sidekiq:

```env
WHATSMEOW_SERVICE_URL=http://whatsmeow:8080
```

Fluxo recomendado:

```bash
docker compose up -d postgres redis
docker compose run --rm rails bundle exec rails db:chatwoot_prepare
docker compose up rails sidekiq vite whatsmeow
```

Se estiver usando um compose de producao, troque a imagem base do Chatwoot para:

```yaml
image: ghcr.io/marcosenz0/chatwoot-whatsmeow:develop
```

## Deploy no Easypanel

Este e o fluxo principal da VPS.

### Estrutura de apps/servicos

Crie ou mantenha os servicos abaixo no mesmo projeto/rede:

- Postgres, preferencialmente `pgvector/pgvector:pg16`.
- Redis com senha.
- Chatwoot web, usando a imagem `ghcr.io/marcosenz0/chatwoot-whatsmeow:develop` ou build pelo GitHub.
- Chatwoot Sidekiq, usando a mesma imagem do web.
- Whatsmeow service, usando o Dockerfile em `whatsmeow-service/`.

### Instancias do fork em `marcos-apps`

| Instancia | Dominio | Web | Sidekiq | Postgres | Redis | Whatsmeow |
| --- | --- | --- | --- | --- | --- | --- |
| Principal | `chatwoot.marcoswt.com.br` | `chatwoot-staging` | `chatwoot-staging-sidekiq` | `chatwoot-staging-db` | `chatwoot-staging-redis` | `whatsmeow-staging` |
| MX | `chatwootmx.marcoswt.com.br` | `chatwoot-mx` | `chatwoot-mx-sidekiq` | `chatwoot-mx-db` | `chatwoot-mx-redis` | `whatsmeow-mx` |
| MD | `chatwootmd.marcoswt.com.br` | `chatwoot-md` | `chatwoot-md-sidekiq` | `chatwoot-md-db` | `chatwoot-md-redis` | `whatsmeow-md` |

Cada instancia usa banco, Redis, chaves de aplicacao, sessoes WhatsApp e dominio proprios. O Chatwoot oficial em `chatwootoficial.marcoswt.com.br` nao faz parte dos deploys deste fork. Para uma mudanca do fork destinada a todos os ambientes, valide e implante a mesma imagem Chatwoot nos tres pares web/Sidekiq e o Go correspondente nos tres servicos Whatsmeow.

Em 29 de setembro de 2026, os tres pares web/Sidekiq receberam a imagem de chamadas `ghcr.io/marcosenz0/chatwoot-whatsmeow:calls-2da34374b58ffcabce53c2914b44cd410b152fc2`. Os seis deploys concluiram com sucesso e os tres dominios voltaram a responder HTTP 200; confirme a tag efetivamente ativa antes de novos testes. Os tres servicos Go usam a branch `codex/whatsmeow-voice-calls`, com contexto `/whatsmeow-service`. Esta implantacao e um canario da PR #21; depois da validacao de midia, publique a versao aprovada em `develop` e fixe a mesma imagem nos tres pares. O webhook interno do MD usa `http://chatwoot-md:3000/webhooks/whatsmeow/%s/%s`.

### Chatwoot web

Comando:

```bash
bundle exec rails s -p 3000 -b 0.0.0.0
```

Variaveis principais:

```env
FRONTEND_URL=https://chatwoot.marcoswt.com.br
WHATSMEOW_SERVICE_URL=http://nome-interno-do-whatsmeow:8080
```

### Chatwoot Sidekiq

Comando:

```bash
bundle exec sidekiq -C config/sidekiq.yml
```

Use as mesmas variaveis do web.

O Sidekiq precisa consumir a fila `default`. As publicacoes de Status usam essa fila de forma duravel mesmo quando o web de staging mantem `ACTIVE_JOB_ADAPTER=async` para outros jobs locais.

### Whatsmeow service

Build:

- GitHub source apontando para o mesmo repositorio.
- Branch `develop`.
- Dockerfile/contexto: `whatsmeow-service`.

Variaveis:

```env
PORT=8080
DATABASE_URL=postgres://postgres:senha_segura@nome-interno-do-postgres:5432/chatwoot?sslmode=disable
WEBHOOK_URL=http://nome-interno-do-chatwoot:3000/webhooks/whatsmeow/%s/%s
```

Exponha a API do Go publicamente somente se precisar consultar health/status fora da rede interna. Para funcionamento normal, rede interna basta.

### Chamadas de voz e vídeo pelo WhatsApp Direct

O navegador precisa alcançar o WebSocket de chamadas por HTTPS. Em cada serviço Whatsmeow, adicione no EasyPanel uma rota de domínio usando o mesmo host do Chatwoot correspondente, caminho público `/calls`, porta de destino `8081` e caminho de destino `/calls`. A rota existente do Chatwoot continua recebendo os outros caminhos. Mantenha a API normal do Go na porta `8080`.

No Chatwoot web de cada instância:

```env
WHATSMEOW_CALLS_URL=https://dominio-do-chatwoot-da-instancia
```

No serviço Whatsmeow correspondente:

```env
WHATSMEOW_CALLS_ENABLED=true
WHATSMEOW_CALLS_PORT=8081
WHATSMEOW_CALLS_ORIGIN=https://dominio-do-chatwoot-da-instancia
```

O web e o Go devem usar o mesmo `WHATSMEOW_SHARED_SECRET` já empregado pelas rotas internas. O proxy precisa permitir upgrade de WebSocket. Para receber chamadas no painel, mantenha `Reject Calls` desligado na configuração do inbox. As chamadas recebidas aparecem enquanto a conversa direta correspondente está aberta no navegador. A mídia de vídeo depende de WebCodecs no navegador. Os seletores de microfone, saída de áudio e câmera ficam nas setas ao lado dos botões correspondentes; a troca de saída usa `AudioContext.setSinkId`, que exige suporte e permissão do navegador. Os logs de uma chamada de voz atendida comprovaram fluxo de pacotes em ambos os sentidos, mas a inteligibilidade do áudio não foi aferida. Este PC **tem câmera**, inclusive uma C922; a afirmação anterior de ausência de câmera estava errada. O teste de vídeo ficou em `Conectando` enquanto aguardava a captura; a biblioteca de chamadas marca vídeo como experimental. Mantenha a PR em rascunho até concluir os testes de áudio e vídeo.

### Sequencia de deploy

1. Suba Postgres e Redis.
2. Prepare um banco novo com o esquema atual antes do primeiro boot do web/Sidekiq. Use o comando de preparacao do Chatwoot:

```bash
bundle exec rails db:chatwoot_prepare
```

   Se `db:migrate` ja iniciou migracoes antigas e falhou numa base nova ainda sem dados, carregue o `db/schema.rb` da mesma imagem uma unica vez, execute `db:seed` e volte ao comando permanente `db:chatwoot_prepare`:

   ```bash
   DISABLE_DATABASE_ENVIRONMENT_CHECK=1 bundle exec rails db:schema:load
   bundle exec rails db:seed
   ```

   Execute esses comandos apenas na base nova sem dados. Nunca deixe `db:schema:load` no boot permanente: ele pode substituir dados em reinicios futuros.

3. Suba Chatwoot web e Sidekiq usando a mesma imagem.
4. Suba o `whatsmeow-service`.
5. Confira o health:

```bash
curl http://nome-interno-do-whatsmeow:8080/health
```

6. No Chatwoot, crie uma caixa de entrada WhatsApp Direct, gere o QR Code e escaneie.

### Atualizacao pelo GitHub

1. Faça commit e push no branch `develop`.
2. Aguarde o GitHub Actions publicar `ghcr.io/marcosenz0/chatwoot-whatsmeow:develop`.
3. Se houve mudanca de contrato em `whatsmeow-service`, redeploy primeiro o servico Go e aguarde a restauracao das sessoes.
4. Se houve migration, rode `bundle exec rails db:chatwoot_prepare`.
5. No Easypanel, redeploy primeiro o Chatwoot Sidekiq e depois o Chatwoot web.

Para mudancas so de documentacao, nao precisa redeploy.

## Deploy no Portainer

No Portainer, crie uma stack com Postgres, Redis, Chatwoot web, Sidekiq e Whatsmeow.

Modelo base:

```yaml
version: "3.8"

services:
  postgres:
    image: pgvector/pgvector:pg16
    restart: always
    environment:
      POSTGRES_DB: chatwoot
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: senha_segura
    volumes:
      - postgres_data:/var/lib/postgresql/data

  redis:
    image: redis:alpine
    restart: always
    command: ["sh", "-c", "redis-server --requirepass \"$REDIS_PASSWORD\""]
    environment:
      REDIS_PASSWORD: senha_redis
    volumes:
      - redis_data:/data

  rails:
    image: ghcr.io/marcosenz0/chatwoot-whatsmeow:develop
    restart: always
    depends_on:
      - postgres
      - redis
      - whatsmeow
    ports:
      - "3000:3000"
    environment:
      RAILS_ENV: production
      NODE_ENV: production
      INSTALLATION_ENV: docker
      FRONTEND_URL: https://chatwoot.seu-dominio.com.br
      SECRET_KEY_BASE: gere_um_valor_seguro
      POSTGRES_HOST: postgres
      POSTGRES_PORT: 5432
      POSTGRES_DATABASE: chatwoot
      POSTGRES_USERNAME: postgres
      POSTGRES_PASSWORD: senha_segura
      REDIS_URL: redis://:senha_redis@redis:6379
      REDIS_PASSWORD: senha_redis
      RAILS_LOG_TO_STDOUT: "true"
      RAILS_SERVE_STATIC_FILES: "true"
      WHATSMEOW_SERVICE_URL: http://whatsmeow:8080
    volumes:
      - storage_data:/app/storage
    entrypoint: docker/entrypoints/rails.sh
    command: ["bundle", "exec", "rails", "s", "-p", "3000", "-b", "0.0.0.0"]

  sidekiq:
    image: ghcr.io/marcosenz0/chatwoot-whatsmeow:develop
    restart: always
    depends_on:
      - postgres
      - redis
    environment:
      RAILS_ENV: production
      NODE_ENV: production
      INSTALLATION_ENV: docker
      FRONTEND_URL: https://chatwoot.seu-dominio.com.br
      SECRET_KEY_BASE: gere_um_valor_seguro
      POSTGRES_HOST: postgres
      POSTGRES_PORT: 5432
      POSTGRES_DATABASE: chatwoot
      POSTGRES_USERNAME: postgres
      POSTGRES_PASSWORD: senha_segura
      REDIS_URL: redis://:senha_redis@redis:6379
      REDIS_PASSWORD: senha_redis
      RAILS_LOG_TO_STDOUT: "true"
      RAILS_SERVE_STATIC_FILES: "true"
      WHATSMEOW_SERVICE_URL: http://whatsmeow:8080
    volumes:
      - storage_data:/app/storage
    command: ["bundle", "exec", "sidekiq", "-C", "config/sidekiq.yml"]

  whatsmeow:
    build:
      context: ./whatsmeow-service
    restart: always
    depends_on:
      - postgres
    environment:
      PORT: 8080
      DATABASE_URL: postgres://postgres:senha_segura@postgres:5432/chatwoot?sslmode=disable
      WEBHOOK_URL: http://rails:3000/api/v1/accounts/%s/whatsmeow/%s/callback
    ports:
      - "8080:8080"

volumes:
  postgres_data:
  redis_data:
  storage_data:
```

Antes do primeiro uso, execute dentro do container Rails:

```bash
bundle exec rails db:chatwoot_prepare
```

## Rotinas uteis

Reconciliar contatos Whatsmeow antigos que foram criados com identificador `@lid`. O primeiro comando apenas mostra contagens e nao altera dados:

```bash
bundle exec rails whatsmeow:reconcile_contact_identities ACCOUNT_ID=<id>
```

Depois de conferir a previa, aplique a reconciliacao geral somente para identidades atuais. O LID da propria sessao e aliases nao confirmados sao ignorados:

```bash
bundle exec rails whatsmeow:reconcile_contact_identities ACCOUNT_ID=<id> APPLY=true
```

A rotina usa somente mapeamentos PN/LID confirmados pelo armazenamento do whatsmeow. Identidades nao resolvidas sao mantidas sem alteracao.

### Reparo do incidente de contatos mesclados

Nao use a reconciliacao geral para separar contatos que ja foram mesclados. Primeiro faca um `pg_dump` consistente e identifique o contato raiz contaminado pela caixa afetada. O reparo de incidente exige caixa e contato explicitos, faz dry-run por padrao e expande o cluster para todas as caixas Whatsmeow da conta:

```bash
bundle exec rails whatsmeow:repair_contact_identity_incident \
  ACCOUNT_ID=<account_id> INBOX_ID=<inbox_id> ROOT_CONTACT_ID=<contact_id> \
  SNAPSHOT_DIR=/app/storage/whatsmeow-identity-repair
```

Confira cada mapeamento PN/conversa. Para aplicar:

```bash
bundle exec rails whatsmeow:repair_contact_identity_incident \
  ACCOUNT_ID=<account_id> INBOX_ID=<inbox_id> ROOT_CONTACT_ID=<contact_id> \
  SNAPSHOT_DIR=/app/storage/whatsmeow-identity-repair \
  APPLY=true CONFIRM=split-corrupted-whatsmeow-contacts
```

O reparo nao apaga mensagens nem conversas. Ele ancora cada conversa no PN de seu `ContactInbox`, associa apenas LIDs confirmados pelo servico atualizado, coloca o LID proprio/aliases nao comprovados em contatos tecnicos sem telefone e executa uma verificacao pos-commit dos remetentes. Guarde o dump PostgreSQL e o snapshot JSON ate terminar a validacao.

Sincronizar fotos de perfil dos contatos Whatsmeow existentes:

```bash
bundle exec rails whatsmeow:sync_profile_pictures
```

Forcar atualizacao:

```bash
FORCE=true bundle exec rails whatsmeow:sync_profile_pictures
```

Rodar inline em ambiente sem worker ativo:

```bash
INLINE=true bundle exec rails whatsmeow:sync_profile_pictures
```

No PowerShell:

```powershell
$env:FORCE="true"
$env:INLINE="true"
bundle exec rails whatsmeow:sync_profile_pictures
```

## Checklist de teste depois de instalar

1. Acesse `https://chatwoot.seu-dominio.com.br`.
2. Crie uma caixa de entrada WhatsApp Direct.
3. Gere o QR Code e escaneie no celular.
4. Confirme que o canal aparece com indicador verde.
5. Envie uma mensagem de outro numero para o WhatsApp pareado.
6. Responda pelo Chatwoot e confirme que chegou no celular.
7. Teste audio gravado no Chatwoot.
8. Teste imagem, sticker e audio recebido.
9. Teste grupo, caso a opcao "Ignorar mensagens de grupos" esteja desligada.
10. Desconecte a instancia pela aba Configuracao e confirme que o indicador muda para vermelho.
11. Gere novo QR Code na mesma caixa e reconecte.

## Problemas comuns

### QR Code aparece conectado sem escanear

Verifique se a caixa de entrada nao esta reutilizando `channel_id` antigo ou sessao antiga no banco. Cada caixa precisa ter sessao isolada pelo ID da inbox.

Tambem confira se o `DATABASE_URL` do Go aponta para o banco correto.

### Mensagem nao chega no Chatwoot

Confira:

- `WEBHOOK_URL` do Go aponta para o Rails correto.
- Os dois `%s` continuam no `WEBHOOK_URL`.
- Rails web esta acessivel pelo nome interno usado no `WEBHOOK_URL`.
- Sidekiq esta rodando.
- A opcao "Ignorar mensagens de grupos" nao esta bloqueando grupos.

### Chatwoot nao envia mensagem

Confira:

- `WHATSMEOW_SERVICE_URL` no Rails/Sidekiq aponta para o Go correto.
- `whatsmeow-service` responde em `/health`.
- A instancia esta conectada.
- O contato tem telefone/JID roteavel.

### Audio nao toca ou nao envia

Confira se `ffmpeg` existe no container do `whatsmeow-service`:

```bash
ffmpeg -version
```

O Dockerfile atual do Go ja instala `ffmpeg`.

### Contatos ou grupos aparecem com `@lid`

Isso geralmente indica que a instancia ainda nao resolveu nome/telefone daquele participante. Aguarde novas mensagens ou rode as rotinas de sincronizacao quando aplicavel. A UI deve preferir nome, depois telefone real, e so entao IDs tecnicos como fallback.

## Para futuras IAs

Antes de mexer na integracao Whatsmeow, leia tambem:

- `docs/whatsmeow-progress.md`
- `whatsmeow-service/main.go`
- `app/services/whatsmeow/session_client.rb`
- `app/controllers/api/v1/accounts/whatsmeow_controller.rb`

Nao substitua este fork por imagem ou codigo do Chatwoot original. O diferencial do projeto e manter o Chatwoot com aparencia original, mas com WhatsApp Direct multi-instancia via Whatsmeow.
