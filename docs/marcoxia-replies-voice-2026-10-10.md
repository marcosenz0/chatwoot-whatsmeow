# MarcoXIA message splitting, emojis and voice setup — October 10, 2026

## User-visible behavior

Conversation settings expose a desired message length, greeting separation, the existing maximum parts and delivery interval. The splitter groups short complete sentences up to the chosen approximate length and keeps an opening greeting separate when enabled. It does not divide word by word. URLs, numbers, common titles and multiline lists remain intact. A long sentence can exceed the desired length; reaching the maximum parts joins the remaining text without losing it. Existing model-produced separate message items remain separate.

Text emoji usage can be disabled, occasional or expressive. Occasional mode permits at most one emoji per response and suppresses emojis when they appeared in the three recent outgoing messages. The model is also instructed to avoid an emoji signature. Reaction settings are independent.

The administrator's Voice and audio tab configures MiniMax or ElevenLabs, an API voice ID, speech model and controls, request-only or contextual behavior, length, spoken instructions and literal pronunciation substitutions. API keys are per-account and per-assistant, stored with Active Record encryption, and never placed in the agent config, prompt or response. Missing encryption rejects key storage; missing keys or voice IDs leaves the response in text. New voice configuration is disabled by default and never changes support activation.

The preview explicitly uses the saved configuration, is private and may consume synthesis/text-model credits after keys are supplied. Test chats simulate the proposed spoken text without calling synthesis. Display names such as Alice 03 are not assumed to be an API voice ID.

The provider requests use fixed official endpoints and return MP3. Spoken text excludes URLs and emojis, applies configured substitutions, and expands numeric text through the existing text model when needed. A synthesis error is recorded without provider body/key data and falls back to the complete text response. When synthesis succeeds, the durable delivery job creates an audio attachment with its transcript in context, retains link-bearing text messages and optionally sends the complete written response too. The run token is checked again after synthesis so pausing or new incoming messages can cancel delivery. Existing provider-side audio delivery is reused; WhatsApp Direct retains its recorded-audio conversion behavior. No provider-level exactly-once guarantee is claimed.

Operator-approved composer/analysis text edits do not reuse a stale audio proposal. Pause acknowledgements are text only. Supported messaging channels are WhatsApp Direct/Cloud, Telegram bot/personal and Instagram/Facebook; unsupported channels continue with text. Actual synthesis and playback for each provider require a configured key and voice and remain untested without them.

## Implementation and validation

The former voice attempt never shipped; this request implements a fresh integration rather than restoring the deferred local scaffolding. The prior assistant instructions, inbox coverage, general activation and individual states must remain unchanged. The primary checkout and earlier worktree are preserved; this task is isolated on codex/marcoxia-replies-voice, based on PR 39.

Local checks so far: 27 agent UI tests passed, production build passed, scoped Ruby Lint/Layout/Security passed (native Windows line endings excluded only locally). Regression coverage includes configurable short greetings/size, complete sentences, links/lists, repeated emoji suppression, voice key encryption/access/account isolation, provider contracts, numeric normalization, separate audio/link delivery, text fallback, duplicate jobs and cancellation during synthesis.

The final Linux gate [38102265099](https://github.com/marcosenz0/chatwoot-whatsmeow/actions/runs/38102265099) passed 627 targeted tests (334 Vue and 293 Rails), scoped lint, production build and image publication. The first gate found only a new authorization test expecting 403 while the existing account API returns 401; the test was aligned. The generated schema was included before the final gate. The generic fork CI has unrelated failures; the directed delivery gate is green.

Published on October 11 to principal, MX and MD, web and workers, using `fork-cf8b285f425a7b3986ab6ca8085949244346fa9f`. Principal was validated before the other targets. A transactional live probe confirmed separate greeting, suppression of a recent emoji, configurable grouping, missing-key text behavior, real encrypted key round trip and rollback with no activation change. Its temporary fake credential never called a provider and was rolled back.

All three health endpoints return 200. The 12 custom Chatwoot/bridge service settings were preserved except the six authorized app image pins; the six bridge container/image identities and connected sessions are unchanged. Fresh activation snapshots were taken on resumption rather than restoring the earlier snapshot: all 59 current states and saved assistant attributes match after rollout. General support remains off; principal #2170 remains paused and MD #92 remains individually active with 20 recent messages. The project snapshot also shows a change to the unrelated painel-modelos environment since the older snapshot; this delivery did not modify that service.

The live principal and MD interfaces show the new conversation controls and the Voice and audio tab. Missing credentials disable voice preview. The current MD name Atendente HOT 1 is preserved. No real provider key was obtained or purchased, no synthesis API was called, and no customer message was sent. Actual voice quality and playback await the user's provider key and API voice ID.

## Provider references

- [MiniMax synchronous speech API](https://platform.minimax.io/docs/api-reference/speech-t2a-http)
- [ElevenLabs speech API](https://elevenlabs.io/docs/api-reference/text-to-speech/convert)
