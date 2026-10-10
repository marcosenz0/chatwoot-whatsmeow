# MarcoXIA workspace and contact memory — October 10, 2026

The interrupted `codex/marcoxia-ui-voice` worktree was resumed after the former chat encountered an internal output-filter error. This release completes the independently authorized agent workspace, saved test chats, notification layout and contact-memory controls. Voice integration remains pending after automatic review blocked that implementation step; no working voice feature is claimed or enabled.

## Behavior

Selecting an agent opens a full-width editor. A top breadcrumb returns to the agent list; sections use horizontal tabs and preserve their selection in the URL. Existing unsaved-change confirmation remains. Alert recipients have individual number cards; input validates country-code format without inventing digits. Subject rules expand separately. Pending requests are opened through a button instead of a permanent side column.

Test chats are stored on the server and isolated by account, assistant and user. Returning to the test tab reloads the most recent saved chat; Chats de teste opens the paginated archive. Starting a new chat retains the old one. In-flight replies are polled when reopening a chat. A locked turn token rejects concurrent submissions and prevents an expired generation from overwriting a replacement turn. Tests remain separate from actual conversations and external notifications.

Administrators can open Memórias inside an agent or Ver memórias from a conversation's right-click menu, including contacts whose AI is disabled. They can edit a previous summary, exclude or restore individual context messages and reset all AI memory for that contact across the account's inboxes. These actions preserve actual Chatwoot messages and AI activation states.

A reset records both a message-ID cutoff and a timestamp: existing history and later imports of old messages remain outside context. Summaries, pending replies, analyses, rebuilds and drafts are invalidated. Approved cross-channel links to the forgotten source are revoked; unrelated approvals remain. Exclusions invalidate dependent summaries and pending context. Edited summaries retain the configured recent window and allow future incremental updates. Existing selected-only context behavior remains applicable.

## Validation and rollout

Local focused UI checks: 25 tests passed. Scoped ESLint passed with existing warnings; Ruby syntax and scoped Lint/Layout/Security passed (Windows-native newline style was excluded locally and remains checked by the Linux gate). Production build and the full targeted GitHub gate are pending at this checkpoint.

Base is PR 38 / `1989c69331`, deployed application pin `fork-3605b2306c94ae890a40157ee961ec15e6594991`. Deploy only a gate-approved shared application image, principal first, then the same image on MX and MD. Preserve each instance's environments, volumes, databases, secrets, bridge identities and connected sessions. General support and all existing per-conversation activation states must remain unchanged. No lead is used for verification.

The previous voice scaffolding was removed from the release graph and kept only in ignored local notes. Existing text handling, inbound media and manual Pix remain unchanged. No provider key was created, exposed or purchased and no synthesis request was made.
