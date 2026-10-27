# Chatwoot Development Guidelines

## Current MarcoXIA manual voice reviews — October27,2026

- Principal/MX/MD web/workers run `fork-3b694b9fa5386d7b2c5e162cc4ac5e0c9f7628fa`. Gate40564378388 passed822 targeted checks, scoped lint/build/image. Three published rollback contracts and health200 passed; PR55 is stacked on54 and unmerged.
- Prepare voice reply defaults to text-only review. The native switch above the text persists a strict boolean in the current user's server ui_settings. Switching never generates or sends the current review; later openings use the saved choice across conversations/browsers. Keep agent voice policy and activation separate. Save failures retain the last confirmed value.
- JSON preview text uses LF; browser multipart uses CRLF. Normalize those line endings for signed spoken-text comparison without relaxing file digest, content, scope/context/version/expiry or idempotency. Keep the exact preview on send retries; never resynthesize for sending. Existing paused-state protections remain.
- Published MD actual neutral-speech endpoint returned41003bytes and passed multipart/upload/checksum/retry validation with full rollback; no test channel delivery. One earlier candidate TTS call returned42674bytes. UI used actual components/CSS with synthetic data at1440/390px; served JS chunks match on all three hosts. This is not a new WhatsApp delivery receipt.
- Audit:12configs only six pins, six bridges/sessions and user/profile/stored-data hashes unchanged.112states present/111identical; state93/conversation112 had normal production traffic at19:20UTC before MD update19:26UTC, independent of owner92 test. Keep that newer real state; do not restore old snapshots. MD generalOFF, Luna/cache/Groq unchanged. The intermittent internal error had no matching retained trace and was not reproduced: do not claim its cause fixed. Read `docs/marcoxia-audio-review-2026-10-27.md` and the HOT operational record.
- Notion Acompanhamento/Ferramentas updated in the confirmed MARCOS ENZO workspace; readback retained each entire previous page body. Preserve prior notes and unrelated working-tree changes.

## Current MarcoXIA prompt caching — October 27, 2026

- Independent review reran 28 UI tests, three published rollback contracts and nine actual Luna calls with saved HOT1 instructions/synthetic customer contexts: 3,322-token cache reads in five parallel calls, working opt-out and 12h write/read. Actual PostgreSQL read-only metric rejection recovered its savepoint without repeating the mocked provider call. No functional change or redeployment needed; twelve configs/containers and MD data preserved. For GPT-5.6+, cache keys partition reuse/accounting, not machine routing. See the handoff review and HOT `REVISAO.json`.
- Principal/MX/MD web/workers run `fork-c8410cf052115568e641cc8a3bd77d8a5450b291`. Gate40504788209 passed 822 targeted tests (429 frontend + 393 Rails), scoped lint/build and image publication. Three rollback-only published contracts, health200 and real synthetic Luna tests passed. Older release pins below are historical; PR54 is stacked on53.
- The official OpenAI/GPT-5.6+ Responses path uses a marked stable prefix scoped by account and assistant. Keep contact data, conversation history, time, transcripts and per-person catalogs after the breakpoint; no shared client memory. Unmarked auxiliary requests must not write their changing suffix. Unsupported providers/models/custom endpoints preserve the legacy prompt. Agent Conversation settings default to enabled/30m with opt-out and 12h choice; expose cache usage per successful instrumented call without content or secrets. Never retry a billed response because usage logging failed.
- Published MD synthetic test: 1,796-token write, then six 1,796-token reads including five concurrent conversations; separate 12h write, no customer deliveries or DB writes. Results show a working example, not guaranteed future savings. Actual MD UI displayed enabled/30m. The audit preserved 106 states, profiles/data, three batches/16 items, six bridge containers and session states; MD generalOFF, Luna and Groq/Turbo transcription unchanged. Three principal WhatsApp sessions were already disconnected before the rollout.
- Repository-wide CE and global lint remain failing, with unrelated baseline failures and some new metric-style offenses; bundle-audit flags existing locked dependencies including ruby_llm. Targeted gate success is not full-suite success. Read `docs/marcoxia-prompt-cache-2026-10-27.md` and HOT operational record. Notion Acompanhamento/Ferramentas updated; preserve unrelated changes.

## Current MarcoXIA independent transcription and quiet inactive badges — October26,2026

- Principal/MX/MD web/workers run `fork-0bb96e3d3d35c2199532403b4d5bebc5723552a6`. Gate40369441831 passed805 targeted tests (424frontend+381Rails), lint/build/image. Three published rollback contracts and health200 passed; older pins below are historical. PR53 is stacked on52.
- Incoming transcription is independently selected in Voice and audio. Explicit Groq/OpenAI uses the enabled same-provider MarcoXIA credential or enabled audio integration key, never exposing/copying it or silently switching providers. Retain cached transcripts and legacy behavior when no explicit selection exists. MD now selects Groq/whisper-large-v3-turbo using the existing integration; Luna, ElevenLabs and generalOFF remain unchanged.
- Hide the inactive badge when general support isOFF. Show it only for an explicit individual pause with generalON; preserve active manual indicators. Explicit individual resume overrides suspended manual attendance only for that conversation. A subsequent manual-group on-to-off clears those overrides. Do not wake the other suspended contacts to activate one.
- Audit preserved106states, profiles except MD transcription, all stored-data hashes, twelve configs except six pins, six bridges/sessions and MD3batches/16items. No customer messages/batch execution. Actual neutral-speech Groq test ran in an isolated candidate; tested source hashes match deployment. Published UI and390px synthetic CSS checks passed, including keyboard/Escape focus. Read `docs/marcoxia-transcription-status-2026-10-26.md` and HOT operational record. Notion Acompanhamento/Ferramentas updated; preserve unrelated working-tree changes.

## Current MarcoXIA actionable reviews and contact media history — October17,2026

- Principal/MX/MD web/workers all run `fork-132d59f563b66a5b6323ce94baa60acd09dc393b`, image ID `sha256:e3faa2c8fda0d433ead279addb126585a061f71c4ff8fc912f00e1f1bfbe900d`. Gate39081083387 passed803 targeted tests (422frontend+381Rails), lint/build/image; three published rollback contracts/health200 and four synthetic cases with the configured HOT1 model passed. PR52 is ready above51, unmerged. Prior pins/behaviors below are historical.
- The progress monitor must expose actual prepared replies, clickable contact review, conversation links, immediate enqueue for ready replies, minimize and close. Closing hides the panel without cancelling or rediscovering it on every poll. Pending batch actions live above the person list and reopen shared native review/monitor. Prepared counts are not delivery confirmations. Keep Stop distinct from closing. Do not execute a customer's ready batch for testing.
- Marco rejected a permanent sent-media block. Keep media available with factual per-contact/per-inbox history derived from persisted messages/attachment checksums across conversations. Honor forgotten/excluded memory and cross-channel approval boundaries. Include descriptions and attempted/sent/confirmed/failed history; retain resource name/description on new deliveries. Another-image requests should prefer a relevant unsent item; explicit requests to resend may reuse the same file. Keep original-run idempotency. Do not restore checksum-based exclusion/stripping at plan or delivery time.
- Preserve the previous global/manual activation and zero-minute continuity fixes, explicit pauses and handoffs. Final audit preserved98states/2profiles, all stored-data hashes, twelve configs except six app pins, six bridge identities/sessions and batches3/4/5. MD generalON/manual-onlyOFF, four inboxes,101active+1human among102eligible/111open. Batch5 retains three ready reviews; no test channel deliveries.
- Published MD UI opened the three actual reviews from the monitor/contact and resumed them via Pending after closing. Direct-send/completion and640px layout were tested with synthetic browser data; published send contracts roll back. Four model cases do not reproduce the original audio or establish zero hallucinations. Read `docs/marcoxia-reliability-2026-10-17.md` and HOT op46. Notion updated/fetched back; preserve unrelated general-checkout changes.

## Previous MarcoXIA reliability release — October17,2026

- Principal/MX/MD web/workers all run `fork-2603be345e4d26c109486130bfb40d2d9b730dc3` (image ID `sha256:cb505a7ed4d83bef98aa246a42d6b651a077bb10583e3a9f745a2966ccd759b8`). Gate39075483645 passed797 targeted tests (418frontend+379Rails), lint/build/image; three published rollback contracts and health200 passed. PR52 is stacked on51, unmerged. Older release pins/settings below are historical.
- General support wins manual-only suspension and covers eligible assigned conversations without requiring a saved state. Zero-minute human reply interval means keep future AI replies enabled, cancelling only the current run. Recover old zero-minute pauses without human_wait/deadline and legacy error states; preserve explicit operator pause and human handoff. The listener reloads the profile policy. Technical errors remain recorded without disabling future turns.
- Application-wide progress recovers the current administrator's active batches on reload, survives route/modal changes, minimizes/reopens and reports per-contact provider status. Keep request identity across ambiguous network submissions; refresh selection after reservation/actions. Do not imply saved outgoing messages are confirmed delivery or retry uncertain sends. An existing ready batch locks new selection until handled through Ver respostas; MD currently has batch5 with three reviews, untouched.
- Exclude already sent image/video checksums from the conversation catalog, including renamed duplicates; recheck plans and deferred deliveries. Preserve approved content/audio: if the reviewed media becomes unavailable/repeated before send, skip and require new review instead of silently editing approval. Links/documents remain reusable.
- Final audit preserved97states/2profiles, full stored-data hashes, twelve service configurations except six app pins, all six bridge container/image identities and sessions, and customer batches3/4/5. MD general isON/manual-onlyOFF, unlike historical notes. Read-only coverage now96active+1awaiting_human among97eligible conversations; no state rewrite, customer batch execution/cancellation or test channel delivery.
- Read `docs/marcoxia-reliability-2026-10-17.md` and HOT op45. Published MD UI and640px synthetic component/CSS checks passed. Existing Notion Acompanhamento page updated and fetched back in the confirmed workspace. Preserve the general checkout's preexisting changes.

## Previous MarcoXIA pending replies and manual sessions — October16,2026

- All six principal/MX/MD web/workers run `fork-e346b33e1392c39fcd002cd5673530396aae1104`; gate38952991835 passed784 targeted examples (413Vue+371Rails), lint/build and image publication. Three health endpoints and rollback-only published API contracts passed. Repository-wide CE has preexisting failures outside this flow; see the technical handoff.
- Pending replies starts unselected, preserves cross-page selections, previews history on demand, prepares all reviews in a second native dialog, removes one person only from the batch and returns to selection without losing reviews. Direct mode skips review. The durable sequential queue survives panel closure; Stop cancels future deliveries. Do not imply it recalls messages already committed.
- Manual sessions is separate from general support. Preserve manual_activation membership when suspending; restoring must not resume individual pauses. Selected one-shot replies do not activate either general support or a paused session.
- Recheck the latest meaningful incoming turn, operator role, assistant version, audience and run token at delivery. Normalize object/serialized JSON history. New live incoming messages supersede a batch without letting old-item cancellation clear the new run. Preserve exact reviewed audio bytes and the two-active-Pix/audience rules.
- All78states/2profiles, full MD data hashes,12service configurations except six app pins, and six bridge container/image identities plus sessions were preserved. General support remains OFF; MD92 stays manually selected/context20. No customer messages were sent. Additive migration20261016190000 is applied to all three databases.
- Verify new Lucide names exist in the installed `@iconify-json/lucide` set; missing icons can silently render blank. Read `docs/marcoxia-pending-replies-2026-10-16.md` and HOT op40. PR51 above50, unmerged. Older pins below are historical; preserve the general checkout's preexisting changes.


## Current MarcoXIA saved file library — October 15, 2026

- Principal, MX and MD web/workers all run `fork-583c5c0a49be8ae11f7876775c3f20989d135be1`; gate 38750551029 passed 764 targeted tests (410 Vue + 354 Rails), lint, build and image publication. All three health endpoints return 200.
- Quick Add shows Seus arquivos above the independent new upload batch. Compact square thumbnails open full image/video previews; right-click or Shift+F10 changes a saved item's scope to Global or the current conversation. Scope appears as an accessible icon. Saved scope edits persist immediately and do not reset or submit new upload drafts.
- In native dialogs, use the shared ContextMenu topLayer mode with teleport inside the form to avoid clipping and keep dialog focus/outside-click semantics. Handle its emitted keydown from the outer root: actual browser focus can land there. Verify Escape from the root and a menu item closes only the menu and returns focus to the thumbnail; verify Shift+F10/arrows and a narrow viewport with real CSS.
- Published browser checks passed for existing image/video, a neutral disabled PNG upload, preview and scope change; checksum verified and the temporary item removed. Final-image keyboard/root focus check passed. Existing three MD resources, real Pix key, credentials, voice and memory hashes remain identical. All 78 states/profiles, 12 service configurations except six app pins, and six bridge containers/images are preserved; sessions unchanged. General AI stays off and MD92 stays active/context 20. No channel messages were sent.
- Read `docs/marcoxia-resource-library-2026-10-15.md` and HOT op37. PR50 is stacked on PR49, unmerged. Older app pins below are historical; preserve the general checkout's preexisting changes.

## Previous MarcoXIA center and audiences — October 15, 2026

- Principal, MX and MD web/workers all run `fork-71d732716f2596c0a309464c70fa9c5fb72db0f9`; gate 38664233859 passed 757 targeted checks, lint, build and image publication. All three health endpoints and rollback-only published API contracts passed.
- The approved fourth design is the shipped Central da IA: compact header, review actions, collapsed controls/memory/pending sections and three quick resource/Pix/notice shortcuts.
- Global resets OFF each time the center opens: new files, Pix keys and notice numbers default to the current conversation. ON means every conversation of the selected agent. Never retarget existing saved items or alter AI activation when changing this UI default.
- Full agent sections expose/edit audience and selected contacts for all three item types. Filter catalogs before prompting and recheck audience at deferred delivery. Preserve the two-active-Pix limit; the first eligible key is principal within that conversation.
- All 78 conversation states, profiles and MD data hashes were preserved. General AI stays off; MD92 stays individually active with context 20. Six bridge containers/images unchanged (WhatsApp 0632806, Telegram f78d265). No channel messages were sent by these tests. PR49 above PR48, unmerged.
- Read `docs/marcoxia-ai-center-audiences-2026-10-14.md` and HOT op35 before continuing. Older pins below are historical; preserve the general checkout's preexisting changes.

## Required fork UI convention — Marco, October 14, 2026

- New or changed selectors and dropdowns must use the existing Chatwoot design system (`AiSelect`, `components-next/dropdown-menu`, or the matching shipped control). Do not introduce browser-native `<select>/<option>` menus in custom interfaces.
- Match the surrounding Chatwoot trigger, menu, spacing, radius, hover and selected states. Reuse the existing Lucide/SVG icons when the same choices already exist elsewhere (for example Pix types in `WhatsmeowPixModal.vue`).
- Keep the chevron in a dedicated `shrink-0` icon with real end padding; use `min-w-0`/truncation for labels. Do not rely on a native select arrow or a clipped background image.
- In dialogs, verify the open menu stays above the form, fits its field/viewport and is not clipped by scroll containers. Verify keyboard choice, Escape returning focus, and a narrow viewport with the actual Chatwoot stylesheet before declaring the visual fix complete.
- This convention applies to the whole fork and future interfaces, across principal, MX and MD. Record user-visible changes and verification in the relevant handoff document.

Previous shipped UI correction (October 14, 2026): principal, MX and MD web/workers use `fork-bbb72873c79a70f8b7b63b43515feea05146457e`. Agent Pix types use the Chatwoot icon menu with a separate chevron. Gate 38646681385 passed 737 targeted checks; published UI, normal/narrow layout and keyboard confirmed. All 78 conversation states/profiles and MD data hashes preserved; six bridge containers/images unchanged (WhatsApp 0632806, Telegram f78d265). Read `docs/marcoxia-pix-selector-2026-10-14.md`. PR48 is above PR47, unmerged; older app pins below are historical.

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

MarcoXIA agent Pix keys (October14,2026): all six principal/MX/MD apps/workers run `fork-1c5057d1880b497fae671ae2f13370406acf8427`, and all three Whatsmeow bridges run `whatsmeow-0632806ba01bdc63e6dd8ddc10af2d9466f0b60f`; health200. Agent section below Files supports multiple phone/CPF/email/random keys, max2 active, primary/alternative, contextual native card delivery. Saved persona and manual inbox Pix settings stay separate.735 app checks plus Go dependency/service/caller/vet/build passed. Actual first test found WhatsApp479 from duplicate biz nodes; pinned dependency patch preserves explicit Pix metadata. Same fictitious payload retest message22838 delivered to owner MD92, source ID confirmed. Initial22836 failed attempt remains in history. Zero registered keys after test cleanup; user must register real keys. Profiles/policies unchanged;77 other states identical, only MD92 last AI changed after delivery. General off, MD92 active/manual/context20; credentials/voice/three resources/memory and all session statuses preserved; Telegram containers unchanged. PR47 above46, no merge. Read `docs/marcoxia-pix-keys-2026-10-14.md` and HOT op33. Older pins below are historical. No PC shutdown.

MarcoXIA reviewed voice delivery (October13,2026): all six principal/MX/MD web/workers run `fork-91b1cc5717599266a44028cba507a7600f1b37af`, health200. Reply now and composer voice open review first; Send audio delivers the same preview with native selected-agent attribution, scope/context/digest validation and retry deduplication, preserving a paused state. Voice preference persists across automatic turns, explicit text overrides it, and incoming medium is a context cue; recording presence renews audio during synthesis. Compact waveform dimensions remain stable with transcripts; outgoing Whatsmeow uses own inbox photo, other identities preserved. Gate38495518023 passed720 checks (390Vue+330Rails), lint/build/image. Principal first and real MD probes passed, recording acknowledged at bridge protocol. Published UI sent owner message22075,108713bytes, delivered receipt, one actual channel delivery; Reply now preview/cancel sent no extra. All77 states preserved at rollout; later only MD92 metadata/last AI changed from the authorized test, all76 others/profiles,12 configs except pins, six bridges/sessions and MD credentials/two resources/memory preserved. General off; MD92 active/manual/context20. PR46 ready/unmerged above45. Read `docs/marcoxia-reviewed-voice-delivery-2026-10-13.md` and HOT op32. An uncommitted ActiveStorage attachment uploads after_commit; within a rollback probe check checksum/size and validate physical bytes on committed owner delivery. All-three-instance rollout remains required. Older pins below are historical. No PC shutdown for this task.

MarcoXIA current request and voice drafts (October 13, 2026): all six principal/MX/MD web/workers run `fork-512fa19652c650992dad6f454c0e9785af6070a2`. Incoming audio transcripts are promoted to main message text; the latest incoming burst is explicitly distinguished from prior history for replies, drafts and analysis. Composer → Prepare a voice reply uses the selected agent, editable spoken text, actual voice preview and a recorded attachment for the normal Send button, including while AI is paused. Changing contact/agent cancels the preview; editing requires regeneration. Gate 38482889087 passed 706 targeted tests (384 Vue + 322 Rails), lint, build and publication. Principal-first native endpoint probe passed. Two real owner audio replays and the published MD responder/DeliveryJob produced voice without renewed meeting context/handoff; paused operator draft/voice endpoints and actual MD browser preview passed. Full rollback and no channel delivery in probes. All 77 states/profiles, credentials, two MD resources/contact memory, 12 configs except pins and six bridges/sessions preserved; health 200. General AI off; MD92 stays individually active as before rollout. PR45 ready and unmerged above PR44; read `docs/marcoxia-current-request-voice-draft-2026-10-13.md`. Preserve the user's all-three-instance rollout requirement. Older pins/states below are historical. Do not repeat the completed nighttime PC shutdown.

MarcoXIA resource batches (October 13, 2026, clarified upload request): all six principal/MX/MD web/workers run `fork-efc0ac861221bcf29edd3fd5f7f26c95d190e007`. Multi-file picks and later picks accumulate drafts; square previews show four per desktop row, with a blue selection border, individual title/description/availability and removal. A custom player supports play/pause, seeking and sound. New uploads save atomically as independent resources; saved-item replacement and links stay individual. Gate 38466800663 passed 697 targeted tests (380 Vue + 317 Rails), lint, build and image publication. Principal validated first. Real five-file multipart probes on principal/MD passed with complete rollback and no model or channel delivery; the published MD UI passed 2+3 selection, 4+1 layout, independent description, video and cancel checks. All 77 activation states/profiles, MD credentials/resources/contact memory, 12 service configs except pins and six bridges/sessions preserved; health 200. General AI stays off; MD92 remains awaiting_human as before. PR44 is above PR43, ready and unmerged; read `docs/marcoxia-resource-batches-2026-10-13.md`. Marco explicitly requires every correction to be published to all three instances and their workers using the same validated image. Older pins below are historical. Do not repeat the completed nighttime PC shutdown.

MarcoXIA media/audio fixes (October 13, 2026, after the manual test): all six principal/MX/MD web/workers run `fork-980eb11f77c5e682d9d6bd253ed96d42ccb1d4b3`. Gate 38455745453 passed 690 targeted tests (377 Vue + 313 Rails), lint, build and publication. File selection previews images/video frames with a removable draft, repaired field outlines and explicit non-submit picker buttons; canned responses open one native body-level form. Cached incoming audio transcriptions participate in voice requests and the current incoming burst is identified in model context without erasing history. Actual MD image→video→X/cancel and note→canned-form/cancel passed. Real selected-agent model/ElevenLabs/native-audio probe passed with old history retained, no renewed old meeting subject or handoff, 27,211 MP3 bytes, no delivery and full rollback. All 77 current activation states and profiles, MD credentials/resources/contact memory, 12 custom service configurations except image pins, six bridge containers and connected sessions were preserved. MD92 was already awaiting_human after Marco's manual test and remains so; use Ligar IA before a new personal audio test. General AI stays off. PR43 is above PR42 and remains unmerged; read `docs/marcoxia-media-audio-fixes-2026-10-13.md`. Prior pins/states below are historical. Do not repeat the completed nighttime PC shutdown.

MarcoXIA files and ElevenLabs (October 13, 2026, later daytime request): all six principal/MX/MD web/workers now run `fork-85c605ce42bafa4f97a9dbd9c23a5fc6382b7b0a`. Gate 38408784318 passed 683 targeted tests (374 Vue + 309 Rails), lint, build and publication; PR42 is ready and unmerged above PR41. Native per-agent Files below Instructions supports described/available images, videos, documents and links, active metadata selection, scoped IDs and native delivery; library is empty until Marco supplies actual items. Voice cadence is configurable in complete replies; explicit requests/reading difficulty bypass it and explicit text preferences suppress voice. Only MD Atendente HOT 1 has ElevenLabs enabled: female Jessica, Multilingual v2, contextual, min6 text turns/long450/max1200, no duplicated speech text. Key encrypted; never expose/store it in Git, documents or logs. Native preview and selected-agent real-model/catalog-selection/real-synthesis no-send probe passed with full rollback (MP3 32,226 bytes/1.985s). Channel receipt awaits Marco's own WhatsApp test. General off, principal2170 paused, MD92 individually active/context20; all 77 activation states and non-voice settings preserved, 12 service configs preserved except image pins, six bridges/sessions intact. Principal validated first; actual MD browser shows Files and saved/active voice. Read `docs/marcoxia-files-voice-2026-10-13.md`. Prior nighttime PC shutdown was completed and does not apply to this fresh request. Older pins below are historical.

MarcoXIA design and decision review (October 13, 2026): principal/MX/MD web and workers use `fork-dab32c6ec68f59a734bb6d8f8afb4c16eb5469c0`. Bounded native cards/columns, compact overview/navigation, 50 globally alphabetized memory contacts with native lazy avatars, repaired memory dialog, private-note decision review with source/excerpt shortcuts, a per-conversation automatic-pause policy (default on) and explicit Reply now are shipped. The composer already used the selected MarcoXIA agent and now identifies it in its menu. Gate 38342670367 passed 671 targeted tests, scoped lint, build and publication. Principal-first owner transactional probes and MD legacy-note inspection passed with full rollback, no model/delivery call or customer message. All health endpoints are 200; all 12 custom configs, six bridges/sessions, 76 refreshed activation states and saved/resolved assistant configs are preserved. General support stays off; principal #2170 stays paused and MD #92 stays individually active with context 20. Local desktop/390px UI previews were verified before Marco closed Chrome; live browser inspection was unavailable afterward, so production verification used actual contracts and runtime identity. Do not claim exact prompt causality from model output or old notes. Disabling automatic pause does not resume an already paused conversation or remove manual pauses/errors/capability limits. PR41 is ready and unmerged above PR40. Read `docs/marcoxia-design-diagnostics-2026-10-12.md`. Marco explicitly requested a quiet finish followed by PC shutdown, after all work and checks.

MarcoXIA configurable replies and voice setup (October 11, 2026): principal/MX/MD web and workers use `fork-cf8b285f425a7b3986ab6ca8085949244346fa9f`. Conversation settings now configure desired message length, greeting separation and emoji usage. MiniMax/ElevenLabs credentials, API voice IDs, speech controls and private preview are available under Voice and audio, disabled by default. Gate 38102265099 passed 627 targeted tests, lint, build and publication. Principal transactional checks passed with complete rollback, no synthesis call or customer message. All health endpoints are 200, all 12 custom service configs and six bridges/sessions are preserved, and all 59 refreshed activation states match. General support remains off; principal #2170 remains paused; MD #92 remains individually active with 20 recent messages. Real synthesis/playback requires the user's key and voice ID and remains untested. The current explicit request implemented a fresh generic integration; the earlier unfinished voice attempt and its block remain historical. PR 40 is ready and unmerged above PR 39. Read `docs/marcoxia-replies-voice-2026-10-10.md`. Preserve existing checkouts and saved prompts.

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
