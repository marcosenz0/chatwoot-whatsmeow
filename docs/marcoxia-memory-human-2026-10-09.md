# MarcoXIA memory and human attention — October 9, 2026

## Behavior and controls

Instructions now include an editable editorial field and a view of the saved effective prompt. The view separates the technical system message from editable agent instructions, response guidelines and guardrails. Credentials are not included. Informal, warm and nonexplicit conversation is supported without repetitive AI introductions. Direct identity questions still receive honest answers.

Conversation settings offer persistent previous-summary plus recent messages, selected messages only, and the previous profile behavior for compatibility. The recent count remains controlled by the conversation window. The memory panel shows the summary, processed count, timestamp, stale/rebuild status and a rebuild action. Public history excludes private notes, deleted messages, call records and operational notifications.

Summaries process only messages preceding the recent window, in batches of 150. The cache persists a chronological cursor and a fingerprint of processed message count, maximum update time and ID sum. New messages leaving the window are summarized incrementally. Older edits, deletions, imports and a window overlapping the old cursor invalidate the affected summary. Summaries are isolated by conversation and account.

The existing separate-message delivery remains in use: configured maximum parts and interval, preservation of links/numbers, cancellation when newer incoming messages, human replies, a pause or changed settings invalidate the run. No mandatory character cap was added.

Missed-call controls are shown for WhatsApp Direct agents. A newly ended incoming missed/declined call schedules a text response using editable instructions and conversation context. Persistent processing markers deduplicate call jobs. Connected calls, outbound calls, historical/old events, paused conversations and subsequent human/incoming messages are ignored. This feature neither answers nor rejects calls.

Notifications has panel users, explicit WhatsApp numbers, a connected Direct sender inbox, configurable subject rules, templates and notify/notify-and-pause actions. The model returns only configured rule identifiers; the server resolves recipients and actions. Handoff can also open a human-attention request. The pause happens before delivery and keeps the assignee. An optional one-message acknowledgement is sent once.

One open request exists per conversation/rule; another rule can open a separate request. Delivery ledgers and unique indexes prevent duplicate application deliveries on job reexecution. Panel alerts use the native notification center; native generic cleanup preserves them. WhatsApp notices have a stable operational prefix and include contact, inbox, brief reason and conversation link. History and attachments are not forwarded. Send failures remain visible in alerts and Activity; external delivery failure does not reactivate a paused conversation.

Resolving a request and reactivating AI are separate controls. Manual resumption is the default. Optional timed resumption starts after the last public human reply and resets on each new human reply; a manual pause defeats the timer.

Cross-channel context requires the operator to verify identity and explicitly approve a source conversation from another inbox. The model may request that context only after the contact mentions a previous conversation. A supplied phone number alone does not reveal another conversation. Account and conversation permissions are checked for both conversations and the approving user. Removing approval cancels pending replies carrying the old context.

Test Agent simulates alert identifiers, pause and missed-call context without creating real requests, sending notices or changing real conversations. The separate Test Notification action sends an actual operational notice using saved destinations and an explicitly entered owner conversation.

## Scope

This delivery implements reusable customer-support infrastructure. It does not implement sexual-service negotiation or payment confirmation, pornography routing or identity concealment. Existing manual Pix is preserved. Audio generation, email, webhooks, automatic call answering/rejection and automatic identity matching across channels are outside this version.

Existing profiles use legacy memory and keep missed-call responses, handoff pausing and external recipients disabled until explicitly configured. No new inbox is linked by deployment. The owner pilot uses GPT-6 Luna, general support off, summary plus 20 recent messages, profile default 80, one/two preferred bubbles with maximum three, two-second spacing and eight-second initial delay. Its human assignee remains Marcos.

## Validation and rollout

[Gate 37969352164](https://github.com/marcosenz0/chatwoot-whatsmeow/actions/runs/37969352164) passed 270 Rails examples, 331 frontend tests, scoped Ruby/JS lint and the production Vite build. Ruby lint inspected 51 files without offenses. The 500-message scenario verified 480 earlier messages summarized plus the latest 20, incremental reuse, older decisions and invalidation after edits, deletions, old imports and window changes. Coverage also includes permissions/account isolation, split delivery cancellation, call eligibility/deduplication, open-request deduplication, multiple recipients, delivery failures and manual/timed resumption.

Principal was validated first on the owner's paused conversation 2170: transactional rollback checks verified pause-before-reply, preserved assignment, one pending request, native notification retention and resolution without reactivation. A real GPT-6 Luna structured response was generated without sending or changing that conversation. The same application image was then deployed to MX and MD. The final interface revision was again deployed to principal first, checked healthy, then applied unchanged to MX/MD.

Final image: `ghcr.io/marcosenz0/chatwoot-whatsmeow:fork-3605b2306c94ae890a40157ee961ec15e6594991`; manifest `sha256:af3381a4433d7be6f2e073f72b00a75fd8e308cdb03c0d895d9ac6cf927fe95e`; running amd64 image `sha256:c37805e025cecea3e92d900e928efc6b44e60c403b7b25099361becceb315cde`. All six application containers match. All three health endpoints returned 200; the 29 service configurations differ only in the six authorized application source images. Whatsmeow and Telegram bridge container/image identities and connected sessions were preserved.

MD owner #92 rebuilt persistent memory successfully: 24 previous public messages summarized plus 20 recent messages. One real operational request generated one panel notice and one WhatsApp notice; provider delivery was confirmed. Repeating the request did not duplicate the pending alert. Assignment remained Marcos. Resolving the request left AI waiting; the operator UI reactivated it manually afterward. The resolved test request remains as audit evidence. No customer reply was sent by this request, and no lead was activated or tested.

Test Agent was validated against the real model with a missed-call event and a human request: the first produced a brief text reply; the second displayed simulated pause. Neither created real requests or sent external notices. The native notification center displayed the MarcoXIA attention notice. All 11 existing AI states retain their activation status; the sole context-window change is the authorized MD #92 selection from 10 to 20. General support remains off, principal 2170 remains paused, and MD #92 is individually active.

The generic repository-wide CI remains non-green outside the targeted gate; it is not reported as fully green. This release uses the targeted gate above. Network/provider exactly-once delivery across an external crash boundary is not guaranteed by the application ledger; application job reexecution and duplicate events are deduplicated. The worktree is `codex/marcoxia-memory-human`, based on the current PR 37 revision. [PR 38](https://github.com/marcosenz0/chatwoot-whatsmeow/pull/38) preserves the existing stack above PRs 37/36/35/34/33/32. Do not replace the deployed image with the older primary checkout; its existing changes are preserved.

Private panel snapshots, owner test results, notification destination and screenshots stay in the ignored `.codex` directory.

The effective-prompt preview and notification-rule actions do not submit the agent settings form. Native-click regression tests cover unsaved edits, adding/removing rules and the isolated notification test action. The prompt preview was verified in the deployed UI, without saving the profile.
