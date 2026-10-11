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

Linux gate, publication and live validation are pending. No key was obtained or purchased, no synthesis API was called, and no customer message was sent.

## Provider references

- [MiniMax synchronous speech API](https://platform.minimax.io/docs/api-reference/speech-t2a-http)
- [ElevenLabs speech API](https://elevenlabs.io/docs/api-reference/text-to-speech/convert)
