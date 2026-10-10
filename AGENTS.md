# Chatwoot Development Guidelines

## Build / Test / Lint

- **Setup**: `bundle install && pnpm install`
- **Run Dev**: `pnpm dev` or `overmind start -f ./Procfile.dev`
- **Seed Local Test Data**: `bundle exec rails db:seed` (quickly populates minimal data for standard feature verification)
- **Seed Search Test Data**: `bundle exec rails search:setup_test_data` (bulk fixture generation for search/performance/manual load scenarios)
- **Seed Account Sample Data (richer test data)**: `Seeders::AccountSeeder` is available as an internal utility and is exposed through Super Admin `Accounts#seed`, but can be used directly in dev workflows too:
  - UI path: Super Admin → Accounts → Seed (enqueues `Internal::SeedAccountJob`).
  - CLI path: `bundle exec rails runner "Internal::SeedAccountJob.perform_now(Account.find(<id>))"` (or call `Seeders::AccountSeeder.new(account: Account.find(<id>)).perform!` directly).
- **Lint JS/Vue**: `pnpm eslint` / `pnpm eslint:fix`
- **Lint Ruby**: `bundle exec rubocop -a`
- **Test JS**: `pnpm test` or `pnpm test:watch`
- **Test Ruby**: `bundle exec rspec spec/path/to/file_spec.rb`
- **Single Test**: `bundle exec rspec spec/path/to/file_spec.rb:LINE_NUMBER`
- **Run Project**: `overmind start -f Procfile.dev`
- **Ruby Version**: Manage Ruby via `rbenv` and install the version listed in `.ruby-version` (e.g., `rbenv install $(cat .ruby-version)`)
- **rbenv setup**: Before running any `bundle` or `rspec` commands, init rbenv in your shell (`eval "$(rbenv init -)"`) so the correct Ruby/Bundler versions are used
- Always prefer `bundle exec` for Ruby CLI tasks (rspec, rake, rubocop, etc.)

## Code Style

- **Ruby**: Follow RuboCop rules (150 character max line length)
- **Vue/JS**: Use ESLint (Airbnb base + Vue 3 recommended)
- **Vue Components**: Use PascalCase
- **Events**: Use camelCase
- **I18n**: No bare strings in templates; use i18n
- **Error Handling**: Use custom exceptions (`lib/custom_exceptions/`)
- **Models**: Validate presence/uniqueness, add proper indexes
- **Type Safety**: Use PropTypes in Vue, strong params in Rails
- **Naming**: Use clear, descriptive names with consistent casing
- **Vue API**: Always use Composition API with `<script setup>` at the top

## Styling

- **Tailwind Only**:  
  - Do not write custom CSS  
  - Do not use scoped CSS  
  - Do not use inline styles  
  - Always use Tailwind utility classes  
- **Colors**: Refer to `tailwind.config.js` for color definitions

## General Guidelines

- Prefer the smallest production-ready change that solves the current problem.
- Build for the expected production path first. Do not add speculative guards, fallbacks, retries, or edge-case handling unless the caller can actually hit that case or production has proven it necessary.
- Enforce eligibility and exclusivity rules at the earliest shared entry point. Do not repeat backup guards across downstream jobs, callbacks, services, or writes unless a proven independent path bypasses that point.
- Validate request parameters at the controller or request boundary, reusing existing errors so invalid input returns `422 Unprocessable Entity` instead of reaching models or Sentry.
- Accept only the documented type, shape, and value. Do not add compatibility coercions for malformed client values; fix official clients instead.
- When an impossible or misconfigured state would indicate a setup/deployment bug, let it fail loudly instead of silently skipping behavior.
- For locked/internal configs that must exist in production, prefer direct reads (`find`, `find_by!`, required hash keys) over silent fallbacks.
- Do not add validation or response checks unless the code uses the result or the check changes behavior meaningfully.
- Prefer existing repo dependencies/client libraries over hand-rolled protocol code for auth, signing, parsing, or API plumbing.
- Avoid one-use private helpers unless they hide real complexity or make the main flow meaningfully easier to read.
- Prefer minimal, readable code over elaborate abstractions; clarity beats cleverness
- Break down complex tasks into small, testable units
- Iterate after confirmation
- Avoid writing specs unless explicitly asked
- In specs, avoid custom helper methods for setup/data. Prefer `let` values and direct per-example setup; only add a helper when it removes meaningful repeated complexity.
- Remove dead/unreachable/unused code
- Don’t write multiple versions or backups for the same logic — pick the best approach and implement it
- Prefer `with_modified_env` (from spec helpers) over stubbing `ENV` directly in specs
- Specs in parallel/reloading environments: prefer comparing `error.class.name` over constant class equality when asserting raised errors

## Codex Worktree Workflow

- Use a separate git worktree + branch per task to keep changes isolated.
- Keep Codex-specific local setup under `.codex/` and use `Procfile.worktree` for worktree process orchestration.
- The setup workflow in `.codex/environments/environment.toml` should dynamically generate per-worktree DB/port values (Rails, Vite, Redis DB index) to avoid collisions.
- Start each worktree with its own Overmind socket/title so multiple instances can run at the same time.

## Commit Messages

- Prefer Conventional Commits: `type(scope): subject` (scope optional)
- Example: `feat(auth): add user authentication`
- Don't reference Claude in commit messages

## PR Description Format

- Start with a short, user-facing paragraph describing the product change.
- Add a `Closes` section with relevant issue links (GitHub, Linear, etc.).
- For feature PRs, add `How to test` from a product/UX standpoint.
- For bugfix PRs, use `How to reproduce` when helpful.
- Optionally add a `What changed` section for implementation highlights.
- Do not add a `How this was tested` section listing specs/commands.

## Project-Specific

- **Translations**:
  - For product and source-string changes, only update `en.yml` and `en.json`; other languages are handled through Crowdin and the community
  - Crowdin-generated translation sync PRs may update non-English locale files; do not flag those changes solely for modifying translated locale files
  - Preserve product and brand names, OAuth scopes, API values, and other machine-readable identifiers unless an official localized form exists
  - When reviewing Crowdin syncs, verify protected terms remain unchanged. Add newly introduced product names, brand names, and machine-readable identifiers to the Crowdin glossary as non-translatable, and keep the glossary current
  - Backend i18n → `en.yml`, Frontend i18n → `en.json`
- **Frontend**:
  - Use `components-next/` for message bubbles (the rest is being deprecated)

## Ruby Best Practices

- Use compact `module/class` definitions; avoid nested styles

## Frontend Conventions

- Prefer existing design-system utilities and shared composables.
- Use typography utilities instead of manually recreating font styles.
- Use logical Tailwind utilities (`ms`, `me`, `start`, `end`) for direction-aware layouts.
- Use `rem` for arbitrary CSS dimensions; preserve native numeric values required by chart/SVG APIs.
- Extract repeated or domain-specific strings, thresholds, colors, and durations into named constants.
- Use shared request-cancellation utilities instead of local `AbortController` logic.

## Enterprise Edition Notes

- Chatwoot has an Enterprise overlay under `enterprise/` that extends/overrides OSS code.
- When you add or modify core functionality, always check for corresponding files in `enterprise/` and keep behavior compatible.
- Follow the Enterprise development practices documented here:
  - https://chatwoot.help/hc/handbook/articles/developing-enterprise-edition-features-38

Practical checklist for any change impacting core logic or public APIs
- Search for related files in both trees before editing (e.g., `rg -n "FooService|ControllerName|ModelName" app enterprise`).
- If adding new endpoints, services, or models, consider whether Enterprise needs:
  - An override (e.g., `enterprise/app/...`), or
  - An extension point (e.g., `prepend_mod_with`, hooks, configuration) to avoid hard forks.
- Avoid hardcoding instance- or plan-specific behavior in OSS; prefer configuration, feature flags, or extension points consumed by Enterprise.
- Keep request/response contracts stable across OSS and Enterprise; update both sets of routes/controllers when introducing new APIs.
- When renaming/moving shared code, mirror the change in `enterprise/` to prevent drift.
- Tests: Add Enterprise-specific specs under `spec/enterprise`, mirroring OSS spec layout where applicable.
- When modifying existing OSS features for Enterprise-only behavior, add an Enterprise module (via `prepend_mod_with`/`include_mod_with`) instead of editing OSS files directly—especially for policies, controllers, and services. For Enterprise-exclusive features, place code directly under `enterprise/`.

## Branding / White-labeling note

- For user-facing strings that currently contain "Chatwoot" but should adapt to branded/self-hosted installs, prefer applying `replaceInstallationName` from `shared/composables/useBranding` in the UI layer (for example tooltip and suggestion labels) instead of adding hardcoded brand-specific copy.

## Active Memory / Resume Guidelines

MarcoXIA workspace delivery (October 10, 2026): principal/MX/MD web and workers use `fork-7106e0d49db61435634e264b9bca7f966134a462`. The memory menu respects restricted allowedOptions and was verified with owner #2170 while AI was off. Full-width editor, persistent private test chats/archive, notification cards and admin contact-memory editing/exclusion/reset are shipped. Gate 38054757405 passed 609 targeted tests, lint, build and image publication. Principal owner checks with rollback and browser persistence checks passed before MX/MD; all health endpoints are 200, 29 service configs and six bridges/sessions are preserved, and all 12 current AI activation states match. General support stays off, principal #2170 stays paused, MD #92 stays individually enabled with 20 recent messages. No lead test or customer messaging. Voice integration remains pending after automatic review blocked that implementation step; do not reproduce or work around it. PR 39 is ready and unmerged above PR 38. Read `docs/marcoxia-workspace-2026-10-10.md`; preserve the primary checkout's changes. Earlier pins below are historical.

MarcoXIA memory and human attention (October 9, 2026): principal/MX/MD web and workers use `fork-3605b2306c94ae890a40157ee961ec15e6594991`. Editable editorial instructions/effective prompt, persistent incremental memory, missed-call text replies, durable panel/WhatsApp alerts and independent resolution/manual or timed resumption are shipped. Gate 37969352164 passed 601 targeted tests, scoped lint and build; generic global CI remains non-green. Principal was validated first with transactional owner checks and a real-model no-send probe; MD #92 successfully rebuilt 24 earlier messages plus the latest 20 and received one delivered owner WhatsApp notice plus a native panel alert. Resolution preserved the pause; manual UI resumption restored the pilot. All 29 service configurations, bridge identities and sessions were preserved; all 11 AI activation states match, with only MD #92 context changed from 10 to 20. General support remains off, principal #2170 remains paused, MD #92 stays individually active on GPT-6 Luna with human Marcos. Cross-channel recall requires explicit operator approval after identity confirmation, then a customer mention. No sexual-service negotiation/payment automation, pornography routing or identity concealment is included; manual Pix is preserved. PR 38 is ready and unmerged above PRs 37/36/35/34/33/32. Read `docs/marcoxia-memory-human-2026-10-09.md` before resuming; older pins below are historical, and the primary checkout's existing changes must be preserved.

MarcoXIA presence and composer delivery (October 8, 2026): principal/MX/MD web and workers use `fork-c36b72e22554ccea25acc91380992b7e99daf572`. Animated analysis, configurable WhatsApp typing/real-microphone recording presence, the native composer routed to the selected agent and compact blue review controls are shipped. Gate 37875660115 passed 574 targeted tests, scoped lint and build; generic global CI remains non-green (see the handoff for translation, lint and security/dependency limits). Principal real-model draft/refinement/acceptance was verified without sending; the owner confirmed typing and recording/cancel status live on MD. All health endpoints returned 200, all 29 configurations and six bridge container/image identities were preserved, and all 11 AI activation states matched. General support remains off; principal owner 2170 remains paused and MD owner 92 remains individually active with context 10. PR 37 is ready for review and unmerged above PRs 36/35/34/33/32. Read `docs/marcoxia-presence-2026-10-08.md` for evidence and limits; preserve the primary checkout's existing changes.

MarcoXIA continuity delivery (October 8, 2026): principal/MX/MD web and workers use `fork-c2c876712c1b5ec70bb4e1ddbe455df20aa3dac6`. Individually enabled AI remains active through analysis, reviewed sending and later replies with general support off. Native context sliders, temporal context with agent timezone, list robot badges, the third right-click AI action and natural message splitting are shipped. Gate 37860072615 passed 555 targeted tests, scoped lint and build. Principal was validated first: three reviewed parts and one autonomous reply were delivered to the owner through WhatsApp; inbound test records used normal Rails callbacks. All health endpoints returned 200; 29 service configurations and all bridge container/image IDs were preserved. Principal owner conversation 2170 was restored paused; MD owner conversation 92 remains individually active; general support remains off. PR 36 is ready for review and unmerged above PRs 35/34/33/32. Read `docs/marcoxia-continuity-2026-10-08.md` for evidence and limits. Older app pins below are historical; preserve the primary checkout's existing changes.

WhatsApp profile delivery (October 8, 2026): principal/MX/MD web and workers use `fork-57b0bf6685237dc737246c47c00f997435b7d19b`; all three Whatsmeow bridges use `whatsmeow-57b0bf6685237dc737246c47c00f997435b7d19b`. Native PT-BR Perfil settings edit the connected name, current expiring About, photo with camera/upload/drag/zoom/confirmed removal, and supported Business details/hours. Full provider photos open from the conversation header, contact sidebar and audio avatar. Gate 37845790207 passed 512 frontend/Rails checks, Go suites/vet, scoped lint and build. Principal was validated first, then MX/MD; all health endpoints returned 200, 29 existing configurations and Telegram container identities were preserved, and connected sessions recovered without QR, including personal MX. General AI support remains off; owner conversation 2170 remains paused. PR 35 is ready and unmerged above PRs 34/33/32. Read `docs/whatsapp-profile-2026-10-08.md` for evidence and limits. Preserve the main checkout's pre-existing changes; older pins below are historical.

MarcoXIA controls revision (October 8, 2026): principal/MX/MD web and workers use `fork-71fc764be52db80807c13b8c13476b154cbe5a7b`. The compact black workspace has consistent icons, a quick general-support switch and per-profile Attendance/Activity. Explicit individual conversation activation works with general support off; conversation pause affects only that contact. Complete-public-history review and outgoing robot/name signatures are retained. Gate 37778773159 passed 442 targeted tests, scoped lint and build, including the real conversation-route regression. Principal was validated first, including a reviewed response delivered to the owner's WhatsApp, then MX/MD; all health endpoints returned 200, service checksums and bridge image/container IDs matched, and connected personal sessions were preserved. Felipe remains on principal inbox 27 with general support and automatic start off; owner conversation 2170 is paused. Live screenshots now work. PR 34 is mergeable and remains unmerged above PDF/Telegram PRs 33/32. Read `docs/marcoxia-agents-2026-10-07.md` for evidence and limits. Preserve the main checkout's pre-existing changes; older pins below are historical.

PDF viewer delivery (October 7, 2026): all principal/MX/MD web and worker services now use `fork-47a7931dc346640e0e809c04388b7432617acc7d`. PDFs offer Ver beside Baixar and a clean WhatsApp-style reader: one avatar/sender/file header, tools inside Editar PDF/menus, compact right-hand pages/zoom, search and annotations saved into a copy. Original-message navigation/highlight is preserved. Gate 37673535975 passed 301 specific tests, scoped lint and build; principal validated first, then MX/MD, all health endpoints 200. Existing environments/mounts/domains and Whatsmeow/Telegram bridge image/container IDs were preserved. PR 33 remains unmerged and is based on the unmerged personal Telegram branch; preserve that source and the main checkout's pre-existing changes. Read `docs/pdf-viewer-2026-10-07.md` for rollout and limits. Earlier app image pins below are historical.

Telegram personal QR installation (October 5, 2026): principal/MX/MD web and workers use `fork-49fbcd3993b763953257aaf2dd49a7e5205cc9ab`; isolated private Telegram bridges remain on `telegram-f78d26565c6a638e3639cbecf91f8e5347d5fdb4`. Gate 37401909121 passed 488 specific tests, lint and build; principal validated first, then MX/MD, all health endpoints 200. MD inbox 7, Emilly Telegram pessoal, is connected as @emillyvixctoriaa/+5563992157585, Marcos assigned and all four group/channel controls enabled. Live owner-account tests covered text/media/voice, edits, linked replies, read indicators and recovery after bridge restart without QR. Read `docs/telegram-personal-qr-2026-10-05.md` for evidence, limits and the repeat guide. PR 32 ready for review, not merged; preserve the deployed pin and pre-existing main-checkout changes; generic fork CI still has failures. Raven bots stay exclusive; API keys configured once, each number authorizes its own QR/2FA.


Previous shipped state (October 3, 2026): all three custom web/Sidekiq pairs use `fork-74572d3ef3dc65d5f881e665dda866f633713e48`, Chatwoot 4.18.0; all three Go services use `whatsmeow-d51b3cd8bcd21fb339e0896207d7c089a2414b85` with independent sessions/configuration. Read `docs/whatsmeow-deleted-view-once-2026-10-03.md` for deleted-message history, view-once notices, validation and playback limits, then `docs/instagram-native-previews-2026-10-03.md`, `docs/instagram-audio-md-2026-10-02.md`, `docs/whatsmeow-group-links-members-2026-10-02.md` and `docs/whatsmeow-ui-corrections-2026-10-02.md` for the preserved Instagram/storage/group UI features. Preserve the connected personal MX session. Earlier principal-only/disconnection checkpoints are historical. The main checkout has pre-existing local changes and older code; use an isolated worktree without discarding them.

Current deployment instruction (October 2, 2026): publish shared fork fixes to principal, MX and MD using the same pinned image, after validating principal. Keep each instance's data, storage, secrets and sessions separate; preserve the personal MX session. Instagram audio sender photos are shipped; automatic original/forwarded distinction is not available in the current Meta API.

Detailed Whatsmeow fork progress is tracked in `docs/whatsmeow-progress.md`. Installation/deployment instructions are tracked in `docs/whatsmeow-installation.md`. Keep this section short and move implementation notes there when they grow.

After each shipped change to a custom Chatwoot instance, update the relevant Markdown handoff before closing the task: record the user-visible behavior, key implementation decisions, deployment targets, validation, and any remaining limitation. Keep transient secrets and personal message contents out of these files. The three custom targets are `chatwoot.marcoswt.com.br`, `chatwootmx.marcoswt.com.br`, and `chatwootmd.marcoswt.com.br`; `chatwootoficial.marcoswt.com.br` is out of scope unless explicitly requested.

Current user instruction (October 2, 2026): remove the extra chat-list selector, chat favorites/lists/themes, restore the standard conversation background, improve the message-anchor highlight, and compact group details with expandable descriptions. Implement and validate on principal first, then publish the same image to principal, MX and MD. Include Brazilian Portuguese; keep databases, sessions, domains, services and secrets separate. Preserve the connected personal MX session. Track validation in `docs/whatsmeow-ui-corrections-2026-10-02.md`.

Latest group additions (October 2, 2026): clickable links in sidebar/read-only settings; native WhatsApp invite and direct-chat dialogs in the current inbox; nine members with owner/admin priority; full searchable roster in a separate dialog; hover and contact/conversation menu for members. Include Brazilian Portuguese. The current provider does not expose security codes: the menu explains verification in the WhatsApp app. Track the shipped state in `docs/whatsmeow-group-links-members-2026-10-02.md`.

### 🌟 Project Status
All primary core integrations between Chatwoot Staging and the Go-based `whatsmeow-service` are implemented, deployed, and healthy.
- **Connection indicators**: Green check / red X badges render correctly overlaying the WhatsApp icon inside `ChannelIcon.vue`.
- **Advanced settings**: The *Configuration* tab is fully visible and mapped for `Channel::Whatsmeow` channels, enabling toggle-saving of Always Online, Auto Read, Reject Calls, Ignore Groups/Status, and Newsletter. All check input fields use the `reset-base` class to prevent CSS stretching.
- **Inline QR Code**: QR code generation and pairing are built directly inside the *Configuration* tab status card. It automatically polls the Go status API until pairing succeeds.
- **Deletes fix**: Staging runs the `:async` adapter for `DeleteObjectJob`, making inbox deletions instant on refresh.

### 🌐 Custom Environments & Credentials
- **Chatwoot Fork/Staging Primary**: [https://chatwoot.marcoswt.com.br](https://chatwoot.marcoswt.com.br)
- **Chatwoot Fork/MX**: [https://chatwootmx.marcoswt.com.br](https://chatwootmx.marcoswt.com.br)
- **Chatwoot Fork/MD**: [https://chatwootmd.marcoswt.com.br](https://chatwootmd.marcoswt.com.br)
- **Chatwoot Fork/Staging Legacy Alias**: [https://staging-crm.marcoswt.com.br](https://staging-crm.marcoswt.com.br)
- **Official Chatwoot**: [https://chatwootoficial.marcoswt.com.br](https://chatwootoficial.marcoswt.com.br)
- **Whatsmeow API (Health)**: [https://staging-api.marcoswt.com.br/health](https://staging-api.marcoswt.com.br/health)
- **Test User**: `marcos@staging-crm.marcoswt.com.br` / `StagingPassword123!`
- **Staging Database URL**: `postgres://postgres:StagingPassword123!@chatwoot-staging-db:5432/chatwoot_staging`
- **Active Whatsmeow Container**: `marcos-apps_whatsmeow-staging`
- **Active Chatwoot Container**: `marcos-apps_chatwoot-staging`

### 🚀 Git Branch & Pushing Changes
- Code is integrated and pushed to the `develop` branch.
- Publishes are handled via Easypanel API triggers (scratch scripts `redeploy_chatwoot.js` and `redeploy_whatsmeow.js` in the workspace context).

### 📋 Pending Next Steps
1. **Multi-Inbox Verification**: Verify message routing when two separate Whatsmeow inboxes share the same phone number (the Go event handler should dispatch to all matching inboxes).
2. **Settings Scenarios**: Run manual tests on call rejection, auto-read, ignore groups/status, and newsletter features.
3. **Session Reconnection**: Verify session state recovery after restarting/rebooting both the Go service and the Rails server.
