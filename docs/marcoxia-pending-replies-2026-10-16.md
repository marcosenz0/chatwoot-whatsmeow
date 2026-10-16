# MarcoXIA — pending replies and manual sessions

Marco authorized this implementation on October 16, 2026, after an initial read-only analysis. PR51 is stacked on PR50; no merge is required for the custom image rollout.

## Product behavior

- Each agent card offers Pending replies with an eligible count, search, paginated contacts, a checkbox per conversation and an on-demand history preview. Nothing starts selected. Selection persists across pages, with no arbitrary batch-size cap.
- Analyze selected prepares every selected reply without sending. A second native dialog opens above the selection dialog and shows text, spoken text/audio, file/Pix references and any handoff decision. Trash removes only that person from this batch. Back or Escape returns to selection; reviews remain available.
- Send reviewed queues the remaining ready replies. Reply directly skips review. Processing is sequential and durable in Sidekiq; closing the panel does not stop it. Stop batch cancels future parts, including already queued delivery tokens. A delivery already committed cannot be recalled by this button.
- Manual sessions is separate from general support. OFF suspends people whose metadata retains manual_activation=true, even if general support is ON. ON restores the same membership without resuming an individual pause. General support retains its event-driven behavior and never scans the old backlog merely when enabled.
- A one-shot selected reply may run while general support or the individual AI is off. It does not enable either setting or erase an individual pause. Human handoffs, blocked/closed/group restrictions and channel reply windows remain excluded.

## Runtime

The additive migration creates reply batches and items. Each item reserves one conversation/observed incoming message; a partial unique index prevents concurrent or repeated batches for that same turn. Discarded, skipped or failed items release the reservation. Requests also carry an operator-scoped idempotency key.

Candidate SQL normalizes both object and serialized JSON content attributes, excludes imported/deleted/unsupported/operational/private/call messages, and requires the latest meaningful public turn to be incoming. It filters account/user permissions, assigned inboxes or the selected agent's conversation override, conversation state and reply window. Unread counters are not used as evidence of an unanswered message.

The planner reuses the configured agent's prompt, current request, conversation context, voice policy and scoped catalogs. Review uses a copied state and does not persist generated memory. Cross-channel recall requests are surfaced as needing individual review. Reviewed audio is stored once and reused byte-for-byte by DeliveryJob.

The runner serializes each batch with a PostgreSQL advisory lock. It rechecks operator administration, assistant version and the current unanswered message before generation/delivery. All deferred parts share the existing current_run? guard, extended with batch status/item token/operator checks. A new incoming message supersedes the old batch token and continues through the ordinary live response scheduler; discarding the old item cannot clear that new run. Cancellations and handoffs keep the batch pointer attached until completion so deferred parts remain cancellable.

## Validation and rollout record

Gate38952991835 passed 784 targeted examples: 413 Vue and 371 Rails, plus ESLint, Ruby Lint/Layout/Security (89 files) and Vite production build. Coverage includes stale history, answered turns, idempotency, direct mode with general off, paused state preservation, cancellation, discard during generation, live response supersession, manual membership suspension/restoration and exact reviewed audio reuse.

Native browser checks used the actual component and Chatwoot stylesheet with synthetic data: two reviews, removal of one, Escape returning to selection, on-demand history preview, and 640px selection/review layouts. The fixture uses fake APIs and cannot send channel messages. Screenshots live in HOT op40's evidence folder.

The repository-wide CE workflow is not green: it reports failures outside the changed pending-replies paths, including status-publication job expectations, AttachmentsPreview and WhatsApp Cloud tests. AttachmentsPreview's three failures were also reproduced on the unchanged PR50 base; that base's CE workflow38753605999 already failed. The 784-example MarcoXIA validation is the passing release gate; do not describe it as the entire repository suite passing.

All six principal/MX/MD web/workers were verified running `fork-e346b33e1392c39fcd002cd5673530396aae1104`. All three health endpoints and published Rails API contracts passed. Contracts used synthetic conversations, a stubbed neutral provider and rollback; no external channel delivery occurred. All78states/2profiles, full MD data hashes (four resources and the disabled Pix key),12service configurations except six app pins, and six bridge container/image identities plus sessions were preserved. General support stays OFF and MD92 remains manually active/context20. The local preview server was stopped. HOT op40 contains the published UI capture and private audit references.
