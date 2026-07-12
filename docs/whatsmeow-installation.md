# Guia de instalacao do Chatwoot com Whatsmeow

Este documento explica como instalar e manter este fork pessoal do Chatwoot com WhatsApp Direct via `whatsmeow-service`.

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

`WHATSMEOW_SHARED_SECRET` precisa ser identico no Chatwoot web, Sidekiq e whatsmeow-service. Quando configurado, ele protege os endpoints de Status e os callbacks do Go sem alterar os endpoints legados documentados para automacoes.

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

### Whatsmeow service

Build:

- GitHub source apontando para o mesmo repositorio.
- Branch `develop`.
- Dockerfile/contexto: `whatsmeow-service`.

Variaveis:

```env
PORT=8080
DATABASE_URL=postgres://postgres:senha_segura@nome-interno-do-postgres:5432/chatwoot?sslmode=disable
WEBHOOK_URL=http://nome-interno-do-chatwoot:3000/api/v1/accounts/%s/whatsmeow/%s/callback
```

Exponha a API do Go publicamente somente se precisar consultar health/status fora da rede interna. Para funcionamento normal, rede interna basta.

### Sequencia de deploy

1. Suba Postgres e Redis.
2. Suba Chatwoot web e Sidekiq.
3. Rode migrations/preparo do banco:

```bash
bundle exec rails db:chatwoot_prepare
```

4. Suba o `whatsmeow-service`.
5. Confira o health:

```bash
curl http://nome-interno-do-whatsmeow:8080/health
```

6. No Chatwoot, crie uma caixa de entrada WhatsApp Direct, gere o QR Code e escaneie.

### Atualizacao pelo GitHub

1. Faça commit e push no branch `develop`.
2. Aguarde o GitHub Actions publicar `ghcr.io/marcosenz0/chatwoot-whatsmeow:develop`.
3. No Easypanel, redeploy do Chatwoot web e Sidekiq.
4. Se houve mudanca em `whatsmeow-service`, redeploy tambem do servico Go.
5. Se houve migration, rode `bundle exec rails db:chatwoot_prepare`.

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

Depois de conferir a previa, aplique a reconciliacao:

```bash
bundle exec rails whatsmeow:reconcile_contact_identities ACCOUNT_ID=<id> APPLY=true
```

A rotina usa somente mapeamentos PN/LID confirmados pelo armazenamento do whatsmeow. Identidades nao resolvidas sao mantidas sem alteracao.

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
