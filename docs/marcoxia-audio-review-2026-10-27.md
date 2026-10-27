# MarcoXIA reviewed audio — 2026-10-27

Prepare a voice reply defaults to a text-only review. The operator edits the spoken text, selects Generate audio, listens, then sends that exact recording. The existing shared review dialog also applies the preference when Reply now resolves to a voice review.

Generate audio automatically is a native switch above the text. It persists an explicit boolean in the authenticated user's server-side ui_settings; absent means false. Updating the switch never synthesizes or sends the current review. Future openings use the last saved choice, across conversations and browsers in that Chatwoot installation. The preference neither changes the agent version nor activates paused AI. Updates lock and merge the user settings, preserve unrelated keys, and authorize access to the conversation. Invalid value types return 422. Save failures preserve the previous visible choice.

## Multiline upload correction

The preview endpoint accepts JSON with LF line endings, while browser multipart text fields are normalized to CRLF. ReviewedReplyService compared that transported field directly with the signed spoken text, rejecting a valid recording with multiple paragraphs as an invalid model response. The published c8410cf runtime reproduced this in a rollback transaction with no provider or delivery call.

Token creation and upload verification now normalize CRLF to LF. All other validation remains: audio digest, MIME and size, spoken text, conversation, selected agent/version, public-history snapshot, expiry, availability and idempotency. Regenerating after actual text changes remains required. Sending does not call the model or synthesize a second recording.

## Validation

Six existing component tests passed locally. The existing service example now exercises two paragraphs and CRLF multipart transport. Targeted CI covers 429 frontend tests and 393 Rails examples, scoped lint and the production build. A missing presence stub in the preexisting batch cancellation example was repaired in that example; production cancellation behavior did not change.

Rollback-only HTTP contracts in an isolated candidate exercised default false, true/false/true persistence, rereading the preference, preservation of another user setting, malformed-value rejection, explicit synthesis, rejected transcript/file changes, identical attachment size/checksum, a preserved pause, and retry deduplication. A second candidate contract used 42,674 bytes from a real neutral ElevenLabs synthesis with the saved HOT1 voice configuration. No synthetic account, user, message or attachment remained; no channel delivery.

The real component and stylesheet were inspected at 1440 and 390 px. Mouse and keyboard switching, Escape/focus, manual generation, next-opening automation, simulated save/send failures and return to manual mode worked. The browser preview used synthetic data and a local fixture, independently of the backend contracts.

## Intermittent internal-error limitation

The retained MD log excerpt had timestamps between 13:01 and 18:47 UTC on October 27 and no draft-controller requests or HTTP500 responses. Two routing errors involved only favicon.ico. Activity contained no recorded failure/error events in the two days queried. This does not cover discarded or earlier logs and does not identify the cause of the reported intermittent internal error. Do not describe that error as fixed merely because the multipart failure was corrected.

## Release

Principal, MX and MD and all three workers run `fork-3b694b9fa5386d7b2c5e162cc4ac5e0c9f7628fa`. Gate40564378388 passed all 822 targeted tests, scoped lint/build and image publication. PR55 is stacked on PR54, open and unmerged. Principal passed first; all three published rollback-only HTTP contracts passed. A transient panel404 interrupted the MD rollout after its web update; inspection confirmed only the worker remained old, and only that worker was then updated.

On published MD the actual voice endpoint made one further ElevenLabs request with a neutral two-paragraph test: 41,003 bytes. Its CRLF multipart upload matched the preview checksum/size and a retry returned the same message. The owner92 state remained active and the transaction fully rolled back, including auth-token writes. No test channel delivery or customer content sent to the provider. Across the task there were two real neutral-speech TTS calls. This verifies the native preview/upload contract, not a WhatsApp delivery receipt.

All three public hosts serve matching dashboard/locale JS chunks containing the new endpoint and Portuguese label. Initial login-only asset discovery missed the lazy dashboard chunks; the final check downloaded the actual deployed chunks and matched their hashes. UI inspection itself used the local real component/CSS and synthetic data, not a live customer conversation.

Final audit: twelve configs changed only by the six app image pins; all six bridge containers/images and session states remained unchanged. User settings, assistant profiles, credentials/integrations and stored resources/memory/Pix/batches matched. MD generalOFF, Luna/cache and Groq/Turbo transcription remained selected. Of 112 conversation states, 111 matched exactly. The one changed row is state93/conversation112: normal production traffic last updated it at19:20UTC before MD's image pin update at19:26UTC. That conversation is different from the owner92 test; its newer real state was preserved rather than overwritten by a stale snapshot. The unchanged targeted suite is not a claim that repository-wide checks or inherited dependency advisories are resolved.

HOT ULTRA operational record: operacao/marcoxia-audio-revisao-27-10-2026/REGISTRO.md. Private probes and raw logs remain under .codex and must not be published with tokens, keys or customer content.

Notion Acompanhamento do Codex and Ferramentas were updated in the confirmed MARCOS ENZO workspace; readback included the complete previous body of each page. Local HOT memory/README and project instructions record the new manual-review default.
