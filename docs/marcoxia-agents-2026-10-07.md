# MarcoXIA agents — October 7, 2026

The Captain overview is now a dedicated MarcoXIA workspace with **Agents**, **Connections**, **Test agent** and **Activity**. Each profile owns its model, instructions, inbox selection and conversation behavior. An agent can cover one or many inboxes; an inbox has one agent to prevent competing replies. Existing Whatsmeow, personal Telegram and PDF features are preserved. There is no n8n integration, RAG, clinic tool or scheduling tool.

## Product behavior

- OpenAI, Groq and Gemini connections keep encrypted API keys on the server. Saved keys are never returned to the browser. Model dropdowns load the connection's available models; agent-specific choices override the connection default. OpenAI uses Responses and structured output; reasoning models omit the unsupported temperature parameter.
- Instructions include a starting prompt for warm, factual, natural conversation. Recent public messages retain chronological context, sender, linked replies, reactions, forwarding/deletion markers, filenames and Instagram story metadata. Older public history becomes an incremental factual summary. Private notes and call events are excluded.
- Configurable burst delay groups incoming messages. Message splitting follows ideas and preserves URLs/numbers, with a configurable count and interval. New incoming messages, human replies, manual pauses and agent edits cancel obsolete pending replies. Duplicate delivery jobs cannot send a part twice.
- Public human replies pause the AI permanently by default, or for the configured interval. Private notes do not pause it. The conversation header offers **Start**, **Pause**, **Continue now** and **Hand off** beside the calling control, with live processing/status updates.
- Images and stickers use actual pixels. Voice notes convert through ffmpeg and transcribe through the configured provider. PDF and supported document files use native file input. Locally downloaded Instagram shares/stories use their real media type. Missing/expired external media is identified as unavailable.
- Contextual reactions use the existing WhatsApp Direct reaction service. A suitable reaction can replace a text response. Groups/channels are opt-in. All inbox types use Chatwoot's existing outgoing delivery routing and account/inbox permissions.
- Instagram and Messenger AI replies remain inside the standard 24-hour window and never use the HUMAN_AGENT tag. Other channels retain their existing reply-window checks.
- Provider/conversion failures pause the conversation and leave an internal note/activity event. Technical errors are not sent as customer replies. Activity records operational metadata rather than customer message contents.
- The private test area supports multiple turns and up to three attachments. It uses saved profile settings, creates no conversation messages and purges temporary uploaded blobs.

## Implementation and review

Branch `codex/marcoxia-agents`; PR [34](https://github.com/marcosenz0/chatwoot-whatsmeow/pull/34), based on deployed PDF commit `47a7931dc346640e0e809c04388b7432617acc7d`. PRs 33 and 32 remain unmerged dependencies. Preserve their source and the main checkout's pre-existing changes. Related OSS and Enterprise paths were checked; there is no corresponding MarcosxAi Enterprise override.

The existing MarcosxAi tables are reused. Conversation state binds to the actual top-level Inbox model; its database unique index handles concurrent state creation. Run tokens plus fresh database checks prevent asynchronous listener ordering from sending an obsolete reply. State payloads expose status, agent name and processing without internal memory. Frontend and backend strings include English and Brazilian Portuguese.

ResponseJob and DeliveryJob explicitly use Sidekiq outside the test environment. Principal's existing `ACTIVE_JOB_ADAPTER=async` configuration remains unchanged; delayed AI work survives the end of a producer process. WhatsApp phone/LID conversation merges move AI activity and state to the canonical conversation, preserve the most restrictive pause, invalidate old jobs and rebuild summarized context. Explicit conversation deletion also removes its AI activity, preventing foreign-key errors.

## Validation and deployment

Gate [37700344921](https://github.com/marcosenz0/chatwoot-whatsmeow/actions/runs/37700344921) passed **395 targeted checks**: 201 frontend tests and 194 Rails examples, plus scoped lint and the production frontend build. The gate published `ghcr.io/marcosenz0/chatwoot-whatsmeow:fork-e6ec816b3cf69319dc85236af86c69c5b969f44e`, OCI index digest `sha256:1504e20f24cf5a7fea03c02c7d2b0f0ca0aeac81dee8714ef8a3aa5ea0c50cff`. This scoped gate passed; unrelated generic fork workflows still have pre-existing failures.

Principal was deployed and validated first, followed by MX and MD. All six web/worker containers run that pinned image, actual image ID `sha256:5f146df45cc56a96e1935708f27d848f4f9ebc91e1ed86132a2ec5d13ff93c0c`. All three `/health` endpoints returned 200. Checksums of the 20 preserved service configurations matched their baseline apart from the intended application image source. All six Whatsmeow/personal Telegram bridge container IDs and image IDs were unchanged. Post-deployment session checks confirmed principal's test WhatsApp, MX's personal WhatsApp, MD's two WhatsApp inboxes and MD's personal Telegram remain connected. MX and MD have zero enabled AI profiles; the official instance was not changed.

Live OpenAI validation used the actual ProviderClient, PromptBuilder and reply schema with the encrypted principal credential and `gpt-6.1-sol`. Eight text scenarios covered identity, conversational preferences, missing commercial facts, human requests, refusal, instruction attacks and Instagram story context. Four synthetic attachments covered actual image pixels, Portuguese Opus transcription, PDF facts and sampled video frames. The private UI test retained image facts in a subsequent turn without uploading the file again. Model discovery returned 51 available models, and saved credentials stayed redacted.

Principal's owner-authorized Pocobusinecl test delivered two introductory parts and another two-part response with the configured interval. Incoming bursts for these split tests were simulated in the owner's conversation; the outgoing messages were delivered through the real WhatsApp channel. The owner's actual native reply exposed a pre-existing phone/LID duplicate-conversation merge blocked by AI activity's foreign key. The merge fix preserved messages and the human pause; replaying that original authenticated webhook succeeded. Normal delayed processing then added a native thumbs-up reaction to the original received message with zero additional text parts. The response completed after the producer process exited, verifying persistent AI scheduling and delivery.

Private notes preserved the AI state; a public human response paused it permanently. Header pause/resume, immediate continuation and manual handoff were verified. Felipe is enabled for principal account 2, inbox 27, with automatic start disabled. The owner's canonical test conversation is 2170 and is paused after validation. No other customer conversation was activated for this test. Human handoff pauses the AI and leaves the conversation available to the team; the example name Ricardo is prompt text, not a configured automatic assignment to a real account user.

## Limits and operation

Media analysis is bounded to 25 MB per attachment. Video analysis samples up to six frames at five-second intervals from the beginning; it does not watch the full video or transcribe its audio. Documents support the provider's file formats; archives and arbitrary applications are not executed. Expired or unpersisted external media cannot be recovered by the AI.

Older history is summarized, so it is not a verbatim unlimited-context record. A language model can still misunderstand; prompt adherence and humanization are not guarantees. Business prices, availability and services must be supplied in the profile instructions or confirmed conversation data. The default prompt requests human help when an important fact is missing.

Only WhatsApp Direct currently sends AI reactions. Other providers/channels may lack equivalent support. Groq media capability depends on the selected model. Channel reply windows still apply to manual continuation.

To repeat validation: save a profile, test a multi-turn exchange and synthetic image/audio/PDF in **Test agent**, bind a known test inbox, disable automatic start and enable only the owner's test conversation. Confirm split delivery, contextual reaction, pause after a human reply, manual restart and handoff. Check Activity and the normal channel delivery status. Restore the test conversation to paused afterward. Never store API keys or personal message contents in this handoff.
