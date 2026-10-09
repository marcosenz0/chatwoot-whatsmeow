# MarcoXIA presence and composer — October 8, 2026

## User-visible behavior

The conversation header animates the loader while MarcoXIA is processing. The operator can still pause the conversation during generation.

Conversa settings offer Mostrar digitando no WhatsApp and Mostrar gravando áudio no WhatsApp. Both default to enabled and respect the inbox's existing typing switch. Automatic generation and approved delivery send text presence, renew it every eight seconds while the current run remains valid, and clear it on completion, pause, cancellation or failure. Review-only analysis and editor drafts do not advertise typing to the contact.

Recording presence starts on actual microphone recording progress, renews during long recordings, and stops on finish/cancel/error/navigation. Opening the recorder alone does not announce recording. MarcoXIA currently sends text replies; this change does not introduce speech synthesis or automatic audio replies.

The native purple composer button now uses the selected MarcoXIA agent for response suggestions, summaries, rewrites and operator refinement. It uses that agent's system prompt, provider/model, temporal context and selected public-message window. The old Ask Copilot action is removed from that menu. Generated content remains a preview until accepted into the editable composer; generation itself never sends or changes individual activation. New public messages or changed agent instructions invalidate obsolete drafts; changing conversations aborts or discards old requests.

The review panel uses a blue Analyze button, an outlined blue Take over button, a visible Close action and a compact blue context slider. Existing Chatwoot components and design tokens are reused, with Brazilian Portuguese labels.

## Implementation and validation

The typing renewal job checks the current run token under the conversation-state lock. State cancellation clears old presence, and obsolete jobs do not switch off a newer run. The bridge's existing authenticated typing endpoint is reused; no Whatsmeow or Telegram bridge changes are required.

A scoped composer endpoint authorizes access to the requested account/conversation and invokes the configured provider. It excludes private notes and calls, honors the saved rolling context window and keeps generation separate from scheduling/delivery. It neither creates a saved conversation state nor mutates an existing run.

The draft schema requires at least one nonempty message, including when the latest public message has already been answered. Accept becomes available when generation completes, independently of the editor animation. Real-provider checks caught both the previous empty-plan behavior and the animation-dependent Accept state before final delivery.

Validation gate [37875660115](https://github.com/marcosenz0/chatwoot-whatsmeow/actions/runs/37875660115) covers 326 frontend tests and 248 Rails examples, scoped JavaScript/Vue lint, Ruby Lint/Layout/Security checks and a production Vite build. The three draft-composable tests also passed locally, including accepting a completed draft without relying on a transition event. Earlier gate 37874533465 passed the same 574 targeted checks. A duplicate manual run was cancelled; it is not the delivery gate.

The generic repository-wide CE workflow is not green: an inspected backend shard failed on a Portuguese/English portal-mailer expectation; global lint reports 240 offenses, including complexity/style offenses in the new composer/presence files; dependency/security checks report existing dependency and application findings. The scoped delivery gate is therefore not evidence that every repository-wide check passes. No dependency upgrade or unrelated global lint cleanup was included in this request.

## Live verification and rollout

The principal was validated before MX and MD. Its real authenticated draft endpoint returned HTTP 200 with a nonempty reply from the configured agent. Generating a preview did not enable AI or send a message; the principal owner's conversation stayed paused. The bridge accepted composing/text and paused/text presence commands through its existing session endpoint.

The owner completed the live MD test: **“Vi digitando”**, then **“Apareceu e terminou ao cancelar”** for microphone recording presence. The MD header's loader had the native `spin` animation and a changing transform during generation, then returned to IA ligada. The inbound owner test went through the normal WhatsApp path and received an AI reply acknowledged by the provider and marked read. The conversation remained individually active with general support off and its saved 10-message context window preserved. No synthetic inbound messages were added in this task.

Final web/worker pin: `ghcr.io/marcosenz0/chatwoot-whatsmeow:fork-c36b72e22554ccea25acc91380992b7e99daf572` for principal, MX and MD. Gate 37875660115 completed successfully, including publication. OCI index digest: `sha256:2e2baa0ff07bb3d0cd380e79fbb02b0f3d30b770520a613cd8eb21b9370dffe3`; all six running app containers use image ID `sha256:d2b57e7e30197c5b1bca155df3d4da41d4a331d0c48924aff7c97bb7593d99a4`.

Final principal browser verification covered generating a draft, requesting a shorter version, accepting it into the editable composer and clearing the unsent test draft. Accept was enabled after both generations. The principal owner remained paused; no test reply was sent there. MD was reloaded on the final image, retaining IA ligada.

The final audit compared all 29 service configurations: only the six app image sources changed. Existing environments, mounts, domains and service configuration fields matched. All six Whatsmeow/Telegram bridge container and image identities matched the baseline. All three health endpoints returned HTTP 200. WhatsApp/Telegram session statuses matched their starting values, including the connected personal MX session and connected MD personal Telegram. Both agents' stored settings and all 11 original conversation activation/context states matched, with no new saved AI states and general support disabled. Principal owner conversation 2170 stays paused; MD owner conversation 92 stays individually active with a 10-message window.

Whatsmeow remains `whatsmeow-57b0bf6685237dc737246c47c00f997435b7d19b`; personal Telegram remains `telegram-f78d26565c6a638e3639cbecf91f8e5347d5fdb4`. No bridge deployments are needed. Official Chatwoot is outside this rollout.

Private runtime/configuration comparisons, provider responses and screenshots stay in the ignored worktree `.codex` directory. Do not commit credentials, private message contents or full panel configurations. PR [37](https://github.com/marcosenz0/chatwoot-whatsmeow/pull/37) is stacked above unmerged PRs 36/35/34/33/32. The primary checkout's existing changes are preserved.

## Repeating the owner test

Open MD conversation 92, confirm individual activation and the saved context window, and leave general support off. In the owner's WhatsApp conversation with the connected inbox, send a normal message and watch for digitando before the answer. Confirm the header returns to IA ligada. For audio, start a real microphone recording from Chatwoot, observe gravando áudio on WhatsApp, then cancel and verify the presence stops. Opening the recorder without starting capture should not announce recording.

In the composer, choose Sugerir uma resposta, request an adjustment if desired, and accept the result into the editable message field. Acceptance must not send the reply. Clear the unsent test draft after verification.

## Limits

Recording presence describes real microphone capture; MarcoXIA does not synthesize or automatically send voice messages. Text presence is sent during automatic generation/approved delivery, not while the operator privately reviews an analysis or generates an editor draft. WhatsApp's visibility still depends on its client behavior and the inbox typing switch; the owner verified both statuses on this deployment.
