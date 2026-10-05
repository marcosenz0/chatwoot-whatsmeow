# Telegram personal account QR integration — October 5, 2026

**Implemented and deployed to principal, MX and MD. Emilly inbox creation, QR pairing and live message validation remain pending while a follow-up fixes channel-card eligibility and missing locale index imports discovered in the deployed wizard. Chrome control is restored.** Marco requests personal-number support in MD without any bot. The Raven sales bots, packages, groups and webhooks remain exclusively with Raven.

New `Channel::TelegramPersonal` is separate from `Channel::Telegram` (Bot API). Rails provides inbox creation, admin-only pairing/status/password/logout, message delivery and authenticated callbacks. Vue displays renewable QR, optional 2FA, account identity and connection state in English/Brazilian Portuguese. One Telegram application API ID/hash is configured once on the server; additional accounts only authorize separate sessions. The interface links to `my.telegram.org/apps` for server administrators.

The Python/Telethon service uses official MTProto QR authentication, durable SQLite event delivery and persistent per-account/inbox sessions. Outgoing requests have stable Telegram random IDs, partial-send checkpoints and Chatwoot echo correlation. Incoming files are queued before download, delivered to scoped Rails storage, then removed from the service after callback acknowledgment. FFmpeg normalizes recorded audio to Telegram Opus voice messages. Broadcasts and groups are independently configurable; sales bots are always excluded.

Inbox controls separate **ignore_groups/ignore_channels** (new imports) from **hide_groups/hide_channels** (list visibility of stored history). Both default true. Hiding is reversible and never deletes history. Backend list counts and filtering plus frontend live updates respect visibility. Telegram groups participate in existing group tabs.

## Environment and deployment

Rails web and Sidekiq: `TELEGRAM_PERSONAL_SERVICE_URL`, `TELEGRAM_PERSONAL_SHARED_SECRET`.

Service: `TELEGRAM_API_ID`, `TELEGRAM_API_HASH`, same per-instance `TELEGRAM_PERSONAL_SHARED_SECRET` (at least 32 random characters), `CHATWOOT_INTERNAL_URL`, `TELEGRAM_PERSONAL_DATA_DIR=/data`. Private network only; no public service port. Single worker. Persistent writable volume `/data`, UID10001. Session files grant account access: keep outside source/logs and isolate each instance's volume/secrets.

Migration: `20261005120000_create_channel_telegram_personal.rb`.

Workflow `.github/workflows/telegram_personal.yml` gates Python, Vue/regression tests, Rails/regression specs, Ruby lint and frontend build before producing pinned app and service images. Publish principal first, validate, then identical app image MX/MD with separate services/storage. Preserve existing Whatsmeow MX session; no Go service changes. Official Chatwoot excluded.

## Validation and limits

Local service tests: 15 passed, including QR refresh/2FA, wrong number logout, retry/dedup/partial echo, durable media download, Opus voice normalization, separate group/channel options and namespace isolation. Expanded Vue regression tests: 226 passed. Linux CI passed 233 Rails examples, Ruby lint and the production frontend build for commit `02be54b195`. Final service health check, schema foreign key and settings-form tests passed in workflow `37386175872` (229 Vue tests, 233 Rails examples, 15 service tests). General repository CI also ran: frontend lint has no errors in modified files; unrelated existing frontend lint and legacy backend specs fail. The global Ruby lint found one new long SQL line, corrected before delivery; the pre-existing finder class-length offense remains. Windows local Rails dependencies absent; Rails gate runs on Linux with PostgreSQL/Redis. Do not declare live connection or all repository tests passed.

No initial bulk Telegram history import. New updates and available catch-up are imported; temporary media stays a notice to open in Telegram. Files up to 50 MB per outgoing message. Outgoing edits/deletions and group administration are outside this first delivery. Incoming edits/deletions and read receipts are synchronized. Broadcast posting still depends on the Telegram account's actual permissions.

## Shipped installation and next action

All six custom Rails web/Sidekiq services now use `ghcr.io/marcosenz0/chatwoot-whatsmeow:fork-c8d31fcb9074e8896d401d5cb96f3928b6f8abe1`. Principal was validated first, then MX/MD updated with the same image. `/health` returns HTTP 200 on all three sites, and server-rendered `telegramPersonalEnabled` is true.

Each instance has its own private `telegram-personal-staging`, `telegram-personal-mx` or `telegram-personal-md` service, `/data` named volume and independent shared secret. All use approved service image `telegram-f78d26565c6a638e3639cbecf91f8e5347d5fdb4`; Docker health checks pass. No public ports/domains were created. Existing environments, storage and resource limits were preserved. Whatsmeow MX/MD container IDs and their Go image remain unchanged.

Principal runtime smoke check: created a disposable personal inbox, confirmed all four defaults true, queried the live private service through the scoped Rails status endpoint, saved independent ignore/hide choices and removed only that empty test inbox. No Telegram account was paired in the test and no human messages were sent.

Specific validation/publish gate: https://github.com/marcosenz0/chatwoot-whatsmeow/actions/runs/37386855177 (passed). PR: https://github.com/marcosenz0/chatwoot-whatsmeow/pull/32 (draft until live UI/pairing validation).

Remaining: restore Chrome extension control, create the Emilly personal inbox in MD with the verified number, scan its bridge-specific QR, complete optional 2FA and validate authorized private receipt/reply/media and session persistence. Chrome web login does not authorize the new service session. Marco was asked to reload the MD inbox wizard and reconnect the Codex extension; do not claim the number is connected before that pairing succeeds.

Repeat for Clara: Settings → Inboxes → Add Inbox → Telegram personal → name and international number → scan QR using that number's Telegram app → optional 2FA → assign agents. Application API credentials are already configured once on the server. The four ignore/hide controls are on the inbox Configuration tab; hide reversibly removes stored group/channel conversations from list/counts, while ignore blocks new imports.

Sources: [Telegram QR](https://core.telegram.org/api/qr-login), [obtaining application credentials](https://core.telegram.org/api/obtaining_api_id), [Telethon QR](https://docs.telethon.dev/en/stable/modules/client.html#telethon.client.auth.AuthMethods.qr_login). `TDLib`, `gotd/td` and community Chatwoot bridges were researched; native integrated QR UI was implemented for this fork.


## Wizard follow-up

The deployed MD wizard exposed a disabled card and untranslated keys. Added the configured personal channel to ChannelItem eligibility and imported telegramPersonal.json in both production locale indices. Three regression tests mount the real ChannelList/ChannelItem/ChannelSelector with production English/Portuguese messages, check the native button is enabled and routes to the personal-account form, and check the option stays hidden when the bridge is disabled. Follow-up CI and image rollout pending; Emilly pairing still pending.
