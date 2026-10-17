# MarcoXIA — coverage, queue feedback and media continuity

Marco requested these fixes after exercising PR51 on live contacts. PR52 is stacked on PR51. Editorial response quality and the earlier ambiguous audio investigation are outside this implementation.

## Behavior

General support takes precedence over suspension of the manual-only membership list. Coverage is serialized for conversations without a persisted AI state, using the assigned inbox agent and the same reply/group/blocked constraints. Profile updates broadcast refreshed conversation coverage. Explicit inactive and human-assistance states have visible indicators with reasons.

A zero-minute human response interval now means keep AI enabled: a public human reply cancels the in-flight run, without creating a permanent pause. Positive intervals and explicit pauses remain supported, as do configured human handoffs. Existing zero-minute human pauses without human_wait can recover on the next received message; serialization already reflects effective coverage. Permanent operator pauses still use the conversation AI pause control. The listener reloads the profile before applying the current policy.

Technical generation/delivery failures keep their private note and structured error log without turning off subsequent turns. A failed batch delivery marks its item failed and advances the queue. Legacy error states are recoverable. There is no automatic replay of an uncertain outgoing send.

An application-wide, minimizable corner monitor survives route/modal changes. It recovers the signed-in administrator's active batches on reload, tracks each person's phase and outcome, supports stopping future sends, and distinguishes saved outgoing messages from provider confirmation/failure. Missing confirmation is displayed as unknown after five minutes; it is never silently retried. The pending list refreshes after reservation and operations, and a repeated network submission retains the same request identity. Server turn reservations remain authoritative against duplicates.

Photo/video catalogs exclude files already sent successfully in this conversation, comparing checksums across library copies. Links and documents remain reusable. The planner sees the remaining catalog and should explain when no matching alternative exists. Plan parsing rejects repetition by removing the duplicate and replacing misleading announcement text; deferred delivery rechecks. This does not add new media, infer visual similarity between different encodings, or modify the library.

## Validation and rollout

In progress. Local tests cover global coverage without persisted state, manual/global priority, zero-minute versus explicit pause/handoff behavior, native failure recovery, duplicate media bytes, pending reservations/operator isolation, monitor minimization/poll failures and provider delivery reporting. Browser checks use actual components/CSS with synthetic APIs, including 640px selection and progress views. No customer batch is executed or cancelled for testing.

Before rollout, private snapshots captured all profiles/states, full resource/credential/voice/memory/Pix hashes, twelve service configurations and six bridge containers/sessions. Preserve current settings: unlike historical handoffs, the MD general switch is ON and manual-only sessions are OFF. The currently ready customer review batch must remain untouched. No schema migration is needed.

Release image, gate counts, published contracts and final preservation evidence will be added after they are confirmed. HOT operation45 links the local evidence and Notion synchronization status.
