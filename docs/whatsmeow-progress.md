# Whatsmeow Fork Progress

This file records the important project context for future sessions. Do not add tokens, passwords, personal access keys, customer PII, or private phone/message contents here.

## Current Goal

Make the Chatwoot fork behave like official Chatwoot in the conversation UI while keeping the direct WhatsApp connection through `whatsmeow-service`.

## Implemented Integration

- `Channel::Whatsmeow` exists as a Chatwoot inbox type and is routed through `SendReplyJob`.
- The Go `whatsmeow-service` owns the WhatsApp session, QR pairing, status checks, disconnects, incoming events, outgoing sends, receipts, group metadata, and profile picture lookup.
- The inbox configuration tab exposes connection status, QR generation, disconnect/connect controls, and persistence for Whatsmeow settings.
- Read/delivered receipts are synced from WhatsApp into Chatwoot message status where available.
- Groups are represented as one Chatwoot conversation per WhatsApp group JID, with the group participant stored on each message through `content_attributes`.
- Contact and group profile pictures are fetched from WhatsApp and synced into Chatwoot contacts when available.

## Latest Fixes Implemented

- Incoming WhatsApp media should no longer be discarded when there is no text caption.
- Stickers, images, videos, audio, and documents are downloaded by `whatsmeow-service`, sent to Rails as base64 attachments, and saved as real Chatwoot `Attachment` records.
- Outgoing Chatwoot attachments are sent from Rails to `whatsmeow-service`, uploaded to WhatsApp, and dispatched as media messages.
- The conversation composer treats `Channel::Whatsmeow` as WhatsApp-compatible, so the official file upload and audio recorder controls can appear.
- The missing message signature warning is hidden for Whatsmeow conversations, since the operator does not want to configure a profile signature for this channel.

## Latest Staging Validation

- Chatwoot fork primary URL `https://chatwoot.marcoswt.com.br` returned HTTP 200.
- Legacy alias `https://staging-crm.marcoswt.com.br` returned HTTP 200 and remains attached as a safe fallback.
- Whatsmeow API health returned healthy.
- Inbox 12 returned Whatsmeow status connected.
- A synthetic media-only Whatsmeow webhook created a Chatwoot message with one image attachment, proving that non-text media payloads are no longer dropped before Rails.
- The synthetic validation conversation was resolved after the check to avoid leaving a test conversation open.

## June 2026 Domain Migration

- The Chatwoot fork/staging web service is now the primary app at `https://chatwoot.marcoswt.com.br`.
- The official upstream Chatwoot instance was moved to `https://chatwootoficial.marcoswt.com.br`.
- Easypanel domains were moved so `chatwoot.marcoswt.com.br` and `www.chatwoot.marcoswt.com.br` route to `chatwoot-staging`, while `chatwootoficial.marcoswt.com.br` and `www.chatwootoficial.marcoswt.com.br` route to the official `chatwoot` service.
- The old staging domain `staging-crm.marcoswt.com.br` remains on `chatwoot-staging` as an alias.
- `FRONTEND_URL` was updated for `chatwoot`, `chatwoot-sidekiq`, and `chatwoot-staging`; all affected services were redeployed.
- The official `chatwoot` web app needed an explicit Rails server command in Easypanel after redeploy because an empty command produced HTTP 502 on the new domain.

## June 2026 Regression Fix

- The Whatsmeow configuration page briefly rendered blank because `Channel::Whatsmeow` was added to the generic WhatsApp helper and the settings page matched the official WhatsApp Cloud block first. The Whatsmeow configuration block now renders before the official WhatsApp block.
- Outgoing Chatwoot messages were failing with `Net::ReadTimeout` while waiting for `whatsmeow-service`; the Rails session client timeout was increased and can be overridden with `WHATSMEOW_SERVICE_TIMEOUT`.
- The Go send endpoint now wraps upload/send work in a 60 second context so slow WhatsApp acknowledgements do not leave HTTP requests hanging indefinitely.
- Chatwoot-recorded MP3 audio is no longer sent as WhatsApp push-to-talk. Only OGG/Opus audio is marked as PTT; MP3 is sent as normal audio so WhatsApp clients can play it correctly.
- Staging validation after deploy: Chatwoot returned HTTP 200, Whatsmeow API returned healthy, inbox 12 returned connected, a real API-created outbound text message in conversation 13 reached `delivered` with no external error, and a real MP3 audio attachment message also reached `delivered` with no external error.

## June 2026 Group / Voice Note Hardening

- `SendOnWhatsmeowService` now sends only real outgoing agent messages. Activity/system messages such as assignment notices must not be delivered to WhatsApp.
- Group conversations are isolated by `contact_inbox_id`, not just `contact_id`, so a contact that appears in a group and in a direct chat cannot route private replies into the group conversation.
- Group sends prefer the WhatsApp group JID (`@g.us`) from `contact_inbox.source_id`; the contact phone/name is no longer allowed to override the group target.
- Group contacts are kept phone-less and group participant metadata is removed from group profiles when future group events refresh them.
- Chatwoot-recorded audio is marked with `whatsmeow_recorded_audio`; `whatsmeow-service` transcodes recorded audio to OGG/Opus via `ffmpeg` and sends it as WhatsApp PTT/voice note. Uploaded audio files remain normal audio attachments.
- Voice notes must include the exact `audio/ogg; codecs=opus` mimetype, a duration, and a 64-byte waveform. Some WhatsApp clients acknowledge PTT media without rendering it when those fields are missing.
- Outgoing text bodies are stripped before sending to WhatsApp to avoid oversized WhatsApp bubbles caused by trailing newlines.
- Incoming display names prefer the names cached in the connected WhatsApp account through whatsmeow's contact store, then fall back to push name or phone.

## June 2026 Group Member Actions

- Group participant names in Whatsmeow group messages now open a compact click menu with actions to start/open a private WhatsApp conversation or copy the participant contact. The action only creates/opens the internal Chatwoot conversation; it must not send a WhatsApp message by itself.
- Rails exposes `whatsmeow_direct_conversation` to find or create a direct conversation for a group participant inside the same Whatsmeow inbox, while keeping the group `contact_inbox_id` isolated. It returns the Chatwoot `display_id` because the frontend conversation route uses display IDs, not database IDs.
- Direct conversation creation now isolates any mistakenly reused group contact before opening the private chat, clears the stale phone from the group profile, and moves empty direct conversations to the cleaned direct contact.
- `whatsmeow-service` exposes group members for a connected session through `GetGroupInfo`, sorted with owners/admins first, then saved contacts, then the remaining members by name.
- The contact sidebar shows a group members button for Whatsmeow group contacts. The modal lists members with avatars, total member/admin counts, concise owner/admin badges, search, refresh, and a private-message action.

## June 2026 Group Member Polish / Sticker Fallback

- Group member actions now carry the participant LID JID when WhatsApp provides one. Rails stores that alternate JID on the direct contact and `SendOnWhatsmeowService` can retry a 403 send against the alternate participant JID instead of only the phone JID.
- The group members button no longer depends only on contact-level attributes. It can infer the Whatsmeow group JID from the selected conversation's recent message attributes, which keeps the button visible across group conversations whose contact panel payload is stale.
- The group members modal resets its state when switching groups, keeps the refresh control away from the modal close button, and uses logical input padding so the search icon does not overlap the placeholder.
- Group member profile pictures are fetched live only for smaller groups; larger groups use cached pictures to avoid timing out while listing hundreds of members.
- Incoming stickers still try the full media download first. If WhatsApp refuses or expires the download but includes a PNG thumbnail, the service now sends that thumbnail to Chatwoot as an image attachment instead of dropping the sticker entirely.

## June 2026 QR Pairing / Inbox Creation Fix

- New Whatsmeow inbox creation sends `force_new` to the Rails session endpoint, and Rails forwards it to `whatsmeow-service`.
- `whatsmeow-service` no longer uses `GetFirstDevice()` when starting a QR pairing session. A newly created inbox gets a fresh device store, so it cannot inherit a previously paired phone from another inbox.
- The session creation endpoint now reports `connected` only when whatsmeow is both connected and logged in. A websocket connection waiting for QR scan returns `pairing` or `connecting` instead of prematurely advancing the Chatwoot setup wizard.
- The Whatsmeow channel card is first in the inbox channel picker, and the pt-BR inbox creation strings now include the WhatsApp Direct form, QR state, Brazilian phone placeholder, and channel labels.

## June 2026 Multi-Inbox Pairing / Disconnect Fix

- Whatsmeow inbox creation no longer asks for a manual WhatsApp number. The setup form only collects the inbox name and then generates a QR Code.
- `Channel::Whatsmeow#phone_number` is now optional during creation; after pairing, the real phone is saved from the connected device JID returned by `whatsmeow-service`.
- The Whatsmeow settings title no longer appends the phone number, avoiding stale or manually typed values in the inbox header.
- Disconnect now removes client mappings and calls whatsmeow outside the global client mutex, then marks the matching phone channels disconnected. This prevents the UI from timing out while disconnecting.
- Group conversation creation now runs under a contact lock and reuses the open group conversation by group contact, avoiding duplicate open conversations when history/webhook events arrive in parallel.

## June 2026 Contacts / Group Audio Fix

- Incoming Whatsmeow audio MIME values are normalized before saving attachments. `audio/opus` becomes `audio/ogg`, filenames use `.ogg`, and codec parameters are stripped so group voice notes can render in the browser like direct voice notes.
- Group participant resolution now compares the event sender against group metadata. It prefers saved/contact display names, then push names or real phone numbers, and only falls back to technical JIDs such as `@lid` when no friendlier value is available.
- `Contacts::ContactableInboxesService` includes connected `Channel::Whatsmeow` inboxes, allowing the Contacts page "send message" flow to start a private conversation through a selected Whatsmeow instance.
- The Contacts list default name sort now ranks human names first, then phone numbers, then technical WhatsApp identifiers, keeping `@lid` contacts lower in the list.
- Contact cards include a per-contact send action that opens a Whatsmeow-compatible inbox selector and creates/opens an empty Chatwoot conversation without sending a WhatsApp message automatically.
- Whatsmeow inbox list labels now use the localized channel name (`WhatsApp Direto` in pt-BR) instead of the missing `INBOX_MGMT.CHANNELS.undefined` key.

## June 2026 Profile Picture Refresh

- `whatsmeow-service` exposes `GET /sessions/:channel_id/profile_picture` to fetch a profile picture URL for a WhatsApp JID on demand, with optional forced refresh to bypass the in-memory cache.
- Rails uses `Whatsmeow::ProfilePictureSyncJob` to refresh missing or stale WhatsApp avatars asynchronously. The job prefers real phone JIDs and group JIDs before falling back to alternate/LID identifiers.
- Incoming messages and private conversations opened from group participants now enqueue profile picture refresh when the webhook payload does not already include an avatar URL.
- Group contacts without avatars can retry profile picture lookup on new group activity instead of being blocked by the 24-hour Rails check; blank WhatsApp lookups remain throttled by the Go service cache.
- `Avatar::AvatarFromUrlJob` accepts `force: true` for Whatsmeow refreshes so a changed WhatsApp photo can replace a previously attached avatar instead of being blocked by URL hash/rate-limit metadata.
- `bundle exec rails whatsmeow:sync_profile_pictures FORCE=true` backfills all Whatsmeow inbox contacts so old conversations and the Contacts page can receive updated profile photos too. In staging, where the ActiveJob adapter is `async`, the task runs inline; use `INLINE=true` to force the same behavior elsewhere.

## June 2026 Groups Directory

- The Contacts area now has a Groups tab for Whatsmeow inboxes. It lists groups directly from the connected WhatsApp session via `GetJoinedGroups`, instead of only showing group conversations Chatwoot already knows.
- The Groups tab can show a specific Whatsmeow inbox or all Whatsmeow inboxes together, supports group search, and can open/create the Chatwoot group conversation without sending any WhatsApp message automatically.
- The same `ignore_groups` inbox setting is exposed as a quick toggle in the Groups tab when a specific instance is selected, so group receiving can be enabled or disabled without opening the inbox configuration page.

## July 2026 Group Invite Links

- Whatsmeow message bubbles intercept `chat.whatsapp.com/...` links and open an in-Chatwoot invite preview modal instead of navigating to WhatsApp Web/Desktop.
- Rails exposes `whatsmeow_group_invite` for invite preview/join, and `whatsmeow-service` maps it to whatsmeow's `GetGroupInfoFromLink` and `JoinGroupWithLink`.
- After a successful join, Rails immediately creates/opens the Chatwoot group conversation through `Whatsmeow::GroupConversationBuilder`, so the group can appear in Chatwoot without waiting for the first incoming message.

## June 2026 WhatsApp Reactions

- `whatsmeow-service` now exposes `POST /messages/reaction`, using `Client.BuildReaction` to send real WhatsApp emoji reactions against an existing WhatsApp message ID.
- Incoming WhatsApp reaction events are forwarded to Rails as `event: reaction`, then persisted on the original Chatwoot message through `content_attributes.whatsmeow_reactions`.
- Chatwoot message bubbles for `Channel::Whatsmeow` show a hover reaction button, a compact quick-reaction picker, a small expanded emoji grid, and a reaction row in the right-click context menu.
- Reacted messages render the selected emoji below the message bubble in the conversation view. Blank WhatsApp reaction events remove the stored reaction instead of showing an empty marker.

## June 2026 Reactions / Quoted Replies Hardening

- The hover emoji button and right-click context menu now share the same reaction flow. Context-menu reactions fire on mouse down so the menu close/blur does not swallow the selected emoji.
- Clicking the same emoji already used by the current Chatwoot user sends `emoji: ""`, which removes that reaction locally and through WhatsApp. Rails and `whatsmeow-service` both preserve the empty emoji value for this removal contract.
- Reaction badges below message bubbles now open a compact popover showing who reacted. The current user's row shows a removal hint and can remove the reaction directly.
- Chatwoot replies sent through Whatsmeow now include a `quoted` payload. The Go service converts it into WhatsApp `ContextInfo`, so WhatsApp renders the real reply box instead of receiving a plain message.
- Incoming WhatsApp quoted replies now forward the quoted message ID, participant, content, and file type to Rails. Rails stores `in_reply_to_external_id` plus `content_attributes.whatsmeow_quoted_message`, and the message bubble shows a fallback preview even when the original message is not loaded in the current Chatwoot page.
- `Messages::InReplyToMessageBuilder` preserves external quoted message IDs when the original local message cannot be found, keeping old or unloaded WhatsApp replies linkable for future processing.

## June 2026 Message Deletes

- Incoming WhatsApp revoke/delete events are now forwarded by `whatsmeow-service` as `event: delete` and mark the matching Chatwoot message by `source_id`.
- Chatwoot keeps the original message content and attachments visible when a message is marked deleted, then shows a compact deleted indicator inside the bubble instead of replacing the text with a deleted-message placeholder.
- The message context menu exposes "Delete for everyone" for sent Whatsmeow messages that already have a WhatsApp `source_id`. Rails sends the revoke request to `whatsmeow-service`, which uses whatsmeow's native `BuildRevoke`.
- The existing local "Delete" action now only marks the message as deleted in Chatwoot and preserves the content, matching the operator's preference to keep a local audit trail.
- Local deletes are labelled "deleted by me" in the bubble so they are visually distinct from WhatsApp revoke/delete events initiated by the contact. A second context-menu action can permanently remove that locally deleted message from Chatwoot.

## June 2026 Message Edits

- Incoming WhatsApp edit events from whatsmeow are intercepted before normal message import and forwarded to Rails as `event: edit`, preserving the original WhatsApp `message_id`.
- Realtime WhatsApp Web edits can arrive as a normal message stanza with `Info.Edit = "1"` and the original message ID instead of the edited protocol wrapper, so `whatsmeow-service` treats that flag as an edit before the duplicate-message guard runs.
- Protocol edit events must prefer `ProtocolMessage.key.id` over the outer event ID when selecting the Chatwoot `source_id`; otherwise Rails can receive a valid edit webhook but look up the wrong message.
- Rails also treats an incoming Whatsmeow message with an already imported `source_id` and different text content as an edit fallback, which covers WhatsApp edit stanzas that arrive looking like ordinary duplicate messages.
- Rails updates the matching Chatwoot message by `source_id`, stores the first message body in `content_attributes.whatsmeow_original_content`, stores the latest edited body in `whatsmeow_edited_content`, and keeps the message content synced to the latest version for previews/search.
- The Chatwoot text bubble renders edited Whatsmeow messages as one message with the original version and the edited version together. Long edited histories are collapsed behind "show more/show less" controls.

## July 2026 Clickable Phone Numbers

- Whatsmeow text bubbles linkify phone-like numbers inside received/sent message text and open a compact action menu.
- The menu checks the connected Whatsmeow session through `GET /sessions/:channel_id/check_number`.
- WhatsApp-registered numbers can open a direct Chatwoot conversation, while all detected numbers can be copied.
- Brazilian local DDD numbers without country code are normalized to `+55` before the check and before direct-conversation creation.

## July 2026 LID Contact Reconciliation

- Direct messages and history sync now resolve WhatsApp LID identities through whatsmeow's persisted PN/LID mapping before creating Chatwoot contacts.
- Phone and LID source IDs are attached to one canonical contact. Existing duplicate contacts are merged while human names are preserved and technical names are replaced by the confirmed E.164 phone number.
- Duplicate non-resolved conversations for the same identity and Whatsmeow inbox are consolidated into the phone-backed conversation. Resolved conversations remain available in the previous-conversations panel.
- `bundle exec rails whatsmeow:reconcile_contact_identities ACCOUNT_ID=<id>` previews existing LID reconciliation; add `APPLY=true` to persist it.
- Opening the contact sidebar or its accordion sections no longer resets and reloads the full conversation list.

## July 2026 Direct-Message Identity Incident Hotfix

- Direct-message identity is now resolved as the external peer by direction. Incoming events use sender addresses; outgoing echoes use recipient/chat addresses and `DeviceSentMeta.DestinationJID`. The connected account's own PN/LID is never published as a contact alias.
- The Go webhook exposes explicit `contact_jid`, `contact_alt_jid`, `contact_phone`, and peer-only `contact_lid_jid` fields. Rails uses this contract instead of mixing raw sender, chat, and recipient fields.
- Rails only permits the canonical PN and an explicit peer LID from the new contract to participate in contact reconciliation. Raw legacy LIDs, unknown JID servers, conflicting phones, and the connected account's identity are rejected.
- Every direct send, reaction, edit, and revoke uses the selected conversation's `contact_inbox.source_id` as its authoritative destination. Contact-level phone/name/participant attributes cannot override it; invalid sources fail closed.
- The whatsmeow dependency is pinned at `v0.0.0-20260525144132-563bcaa0f632`, which removes stale inverse PN/LID cache entries when mappings change.
- The incident repair task is dry-run by default and splits an explicitly selected corrupted root contact across all account Whatsmeow inboxes. It preserves conversations/messages, realigns incoming senders, quarantines unverified aliases, refreshes names/avatars, and writes a restricted JSON snapshot before applying.
- Click-to-WhatsApp ad metadata is stored separately in `content_attributes.whatsmeow_ad`; it never participates in contact identity. The first attributed lead message renders a compact ad card with source, image/video thumbnail, copy, and an external details link when WhatsApp provides them.
- Session mutations and sensitive whatsmeow routes require the configured internal token and fail closed when it is absent. `/health`, session status, number checks, and profile-picture lookup stay public for existing monitoring and documented automations.

## July 2026 WhatsApp Status

- The conversation sidebar now has a Status workspace for each connected `Channel::Whatsmeow` inbox, with own Status publishing and the active updates WhatsApp delivers for that session.
- The Status workspace defaults to an all-inboxes view, shows each session's connection badge, and offers a Chatwoot-style inbox picker plus quick per-inbox Status toggles in the three-dot menu.
- Publishing from the all-inboxes view can target every connected inbox or a selected subset. The browser uploads once, receives `202 Accepted`, closes the composer, and leaves the durable publication sequence to Sidekiq.
- Incoming Status payloads are rejected by the normal message importer even if a webhook arrives with a generic message event, preventing `status@broadcast` from creating contacts or conversations outside the Status workspace.
- Text Status supports the WhatsApp background/font metadata; image, video, and recorded-audio Status use Active Storage and expire after 24 hours. An hourly housekeeping job removes expired records and media.
- The full-screen viewer advances text/images after five seconds, follows the real video duration, and continues through every update and contact with keyboard and pointer navigation.
- Opening an incoming Status creates a per-agent local view immediately and sends the WhatsApp read receipt asynchronously, so a disconnected whatsmeow service does not block the viewer.
- Realtime `status@broadcast` messages and `StatusV3Messages` history snapshots bypass normal conversation/group creation. Status revokes delete the matching Status record.
- Status recipients are scoped to the contacts associated with the publishing inbox. Account-wide contact synchronization was removed because whatsmeow derives Status broadcast participants from its local contact store, making a global sync expand every inbox's broadcast unexpectedly.
- Before each Status publish, account-managed contact names are cleared from that session in one local batch and only the selected inbox's audience is restored. This prevents contacts injected by an older global sync from remaining eligible recipients.
- Multi-inbox Status publishing is persisted per destination as `queued`, `processing`, `published`, or `failed`. Distributed Redis mutexes cover the full remote request, enforce a 15-second account interval and a 60-second cooldown per physical WhatsApp session, and deduplicate inbox aliases that share the same phone.
- Every physical delivery receives a stable WhatsApp message ID before it is sent. Automatic and manual retries reuse that ID, and the Rails client never retries a mutation through another service alias after a response or ambiguous read failure.
- A minute-level recovery job resumes due queued deliveries and safely retries processing records abandoned beyond the full Status timeout, so a web restart, enqueue interruption, or worker crash cannot leave a publication permanently stuck.
- Contact storage influences outgoing Status recipients only. It cannot force another account to send its Status to this session; incoming visibility remains controlled by WhatsApp delivery and the other person's privacy/contact relationship.
- Set the same `WHATSMEOW_SHARED_SECRET` on Chatwoot and whatsmeow-service to authenticate Status API calls and callback webhooks.
- Status updates now separate unseen updates from the `Vistos`/Seen section. The permanent action beside `Meu status` keeps publishing additional updates available after the first one.
- The Status viewer supports text replies, emoji reactions, saved stickers, audio mute/unmute, and the native WhatsApp Status context needed for the reply to appear in the contact's direct chat.
- Read/played receipts for Status published from this account are stored as per-contact viewers and exposed through the viewer count/list in the Status viewer. Outgoing rows and stable source IDs exist before the send, preventing a fast receipt from being discarded before persistence. A status viewer never creates a Chatwoot conversation.
- Status receipt classification now accepts both read and played protocol variants, resolves LID participants, and confirms the Status source ID belongs to the inbox before recording a viewer. This avoids counting this account's own reads of somebody else's Status while keeping valid external views.
- Live read/played receipts are checked against persisted outgoing Status IDs even when WhatsApp does not label the receipt chat as `status@broadcast`; Rails remains the final inbox/source-ID authority before a viewer is stored.
- The pinned whatsmeow module receives a build-time compatibility patch for Status receipts addressed from the account's own JID to `status@broadcast`: the real viewer in the `participant` attribute is preserved instead of being mistaken for the current account.
- `StatusV3Messages` history sync now restores viewers from WhatsApp's embedded `UserReceipt` records for own Status updates, so views already visible on the phone can be recovered idempotently after reconnect/history sync.
- Whatsmeow callback delivery retries transient connection, timeout, rate-limit, and server failures with a short exponential backoff, preventing a brief Chatwoot restart from permanently losing a Status view event.
- The Status three-dot menu can independently hide or show this inbox's outgoing view confirmations. It defaults to showing them; when hidden, Chatwoot still records the operator's local view but does not ask WhatsApp to send the receipt.
- WhatsApp replies to an active own Status now retain a Status reference in the direct conversation. The message bubble displays a clickable media/text preview that reopens the original Status context instead of showing an ambiguous generic quoted message.
- Received video Status media now keeps normalized video MIME metadata and a compact JPEG thumbnail. The viewer uses that thumbnail (or one lightweight frame capture for older records) for the stronger blurred media backdrop without starting a second foreground video decode.
- The Status settings menu groups each WhatsApp inbox in its own expandable card. Status reception and outgoing view-confirmation controls stay inside that inbox instead of rendering as overlapping flat rows.
- Multi-inbox publications now share a publication identifier. The own-Status viewer totals views across the matching publication, shows the originating inbox on every viewer row, and offers an inbox filter from the viewer panel's three-dot menu.
- Viewer identity storage and API counts collapse matching contact, phone, PN-JID, and LID receipts for the same Status, preventing multi-device identity variants from inflating the count.
- The own-Status view counter and viewer panel use an opaque high-contrast surface, keeping the controls and names readable over white or otherwise bright Status media.
- Each own-Status viewer row displays the viewer's phone number beside their name, using the linked contact phone as a fallback when the receipt does not carry one.
- Own Status publications are grouped by publication instead of mixing every inbox copy into the viewer sequence. The viewer exposes inbox chips to switch copies without leaving the screen.
- `Meu status` opens a Portuguese publication manager with previews, live per-inbox queue states, view totals, retry controls for failed destinations, open controls, and two-step remote deletion. Closing a Status opened from this manager returns to the manager instead of the empty Status workspace.
- The `Meu status` card always opens the publication manager; only its separate blue plus button opens the composer. Statuses from another connected inbox owned by the same account are recovered as own publications when the original local outgoing record is unavailable, with duplicate mirrors collapsed by WhatsApp source ID.
- Brazilian viewer phone numbers are formatted as `+55 DD XXXX-XXXX` or `+55 DD XXXXX-XXXX` for easier reading.

## July 2026 Conversation Search

- Conversation list headers now include a search action before filter, sort, and layout controls. It performs a debounced server-side lookup across accessible conversations by partial contact name, email, phone number, or identifier, including old and resolved conversations that are not loaded in the current list page.

## July 2026 Official WhatsApp Cloud Studio

- The official `Channel::Whatsapp` Cloud API inbox has a Portuguese Studio for synchronized Meta templates, visual customer journeys, consent-based broadcasts, delivery summaries, and Brazilian cost estimates. The interface filters strictly to `provider: whatsapp_cloud`; Whatsmeow inboxes and services are unchanged.
- Template creation supports text headers, numbered body variables with Meta review examples, footers, quick replies, static website buttons, and phone buttons. Specialized authentication/native Meta Flow templates remain visible but disabled where the Studio cannot build their required payload safely.
- Journeys can be saved while incomplete, but publication validates the graph, trigger, customer-service window mode, approved synchronized template, media header, named or numbered values, URL/copy-code/quick-reply parameters, branches, reachability, and cycles.
- Outgoing journey and campaign processing now waits for a provider message ID or delivery status instead of treating local message creation as Meta acceptance. Failed sends remain failed, and paused or replaced journeys cancel unfinished runs.
- Official Cloud media webhook failures that are safe to retry now roll back message deduplication and retry instead of permanently creating an attachment-less message. Cloud webhooks fail closed on missing or invalid Meta signatures; 360dialog behavior is unchanged.
- Composer recordings for official Cloud inboxes are remuxed to OGG/Opus and sent with Meta's voice-note flag. Uploaded audio remains a regular audio attachment.

## August 2026 Typing Indicators

- Agent `conversation.typing_on` and `conversation.typing_off` events are forwarded asynchronously to the internal whatsmeow service, which sends WhatsApp `composing` and `paused` chat presence without blocking the Chatwoot composer.
- Incoming WhatsApp `ChatPresence` events are mapped to the existing Chatwoot conversation and contact, then broadcast through Chatwoot's native typing websocket events. Contact events are never echoed back to WhatsApp.
- The Whatsmeow instance behavior settings include `typing_enabled`, enabled by default. Disabling it stops both outgoing and incoming typing indicators for that inbox.
- WhatsApp requires the linked session to advertise available presence before it delivers chat-state events. The service maintains that presence while typing indicators are enabled, and the configuration description makes this behavior explicit.
- Successful outgoing messages explicitly send `paused`, ensuring the WhatsApp typing indicator disappears as soon as the message is delivered to the service.
- Incoming presence resolution includes the canonical phone JID from the whatsmeow contact contract. This keeps PN/LID aliases from returning a successful webhook without locating the matching Chatwoot conversation.
- Text and audio presence are transported separately. WhatsApp audio presence renders as `gravando áudio` in the open conversation and conversation list, while the Chatwoot recorder sends WhatsApp's native audio composing/paused presence.
- Conversation cards react to the same realtime presence store as the open conversation, so `digitando` and `gravando áudio` are visible even before the operator opens that chat. Existing presence records update when a contact switches from text to audio.
- The internal `/typing` route is protected by `WHATSMEOW_SHARED_SECRET`. Future n8n typing simulation should call Chatwoot's authenticated conversation typing endpoint rather than exposing this internal route.

## Product Decisions

- Do not add NATS until message correctness is stable. The current media loss was caused by the Go event handler discarding non-text messages before Rails, not by queue backpressure.
- Chatwoot already uses its own realtime/websocket pipeline after messages are created. The right first fix is to create proper messages and attachments; a separate websocket layer inside whatsmeow can be considered later only if realtime delivery remains unreliable.
- Keep groups enabled when `ignore_groups` is off. If group messages should be hidden, use the inbox setting instead of hardcoding the behavior.
- Keep newsletters filtered when `ignore_newsletters` is on.

## Validation Checklist

- Audio message UI now uses a WhatsApp-like compact player. Recorded/voice-note audio shows sender avatar, waveform bars, and a playback speed pill only while playing; uploaded audio files show a headphones icon and a flat progress line.
- Incoming WhatsApp audio metadata now preserves PTT, duration, and waveform from `whatsmeow-service`, allowing received voice notes to render differently from normal audio files.
- Incoming audio downloads now reject partial file-length/hash warning payloads instead of saving truncated clips; complete audio files are probed with `ffprobe` so Chatwoot stores the real duration from the downloaded media.
- The audio player preloads browser metadata, falls back to stored duration when needed, and keeps the waveform row visually aligned with the play control.
- Audio bubbles render the message timestamp/status inside the player chip, resample low-detail waveforms to a consistent visual width, and hint OGG/Opus sources as `audio/ogg; codecs=opus` for better playback of older saved attachments.
- Audio playback now uses the attachment URL directly on the `<audio>` element again, avoiding strict MIME hints that can block browser playback when saved audio metadata does not exactly match the file. Voice-note waveforms are regenerated client-side from the decoded audio buffer when possible, so visible bars better reflect speech/silence instead of using a generic pattern.

- Send and receive direct text messages.
- Send and receive group text messages.
- Receive stickers, images, audio/voice notes, videos, and documents.
- Send an image/file/audio from Chatwoot and confirm it arrives in WhatsApp.
- Confirm group media lands in the group conversation, not in a separate per-participant conversation.
- Confirm the composer shows emoji, attach, audio recorder, signature, and send controls when the account feature flags allow them.
- Confirm Whatsmeow conversations no longer show the missing signature warning.
- Confirm receipts move outgoing messages from sent to delivered/read when WhatsApp emits those events.

## Known Operational Notes

- For functional Chatwoot/Whatsmeow changes, do not stop at local edits. The expected delivery loop is: validate what can be validated locally, commit and push to `develop`, wait for the `ghcr.io/marcosenz0/chatwoot-whatsmeow:develop` image to publish, redeploy Chatwoot web and Sidekiq in Easypanel, then verify the staging UI and health endpoints.
- When validating audio transcription after a deploy, old ActiveStorage audio URLs can return 404. Create or receive a fresh audio attachment in staging before testing the Transcribe/Summarize actions, and verify both OpenAI primary and Groq fallback/provider paths without storing API keys in docs.
- Local Ruby may not be installed on every workstation; Ruby validation may need CI or the container.
- Local Docker may not be available; use GitHub Actions and staging deploy for end-to-end checks when needed.
- Portable Go can be used from `.codex/tools/go/bin/go.exe` if system Go is missing.
- Do not commit generated binaries such as `whatsmeow-service.exe`.
