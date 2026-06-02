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

- Chatwoot staging returned HTTP 200.
- Whatsmeow API health returned healthy.
- Inbox 12 returned Whatsmeow status connected.
- A synthetic media-only Whatsmeow webhook created a Chatwoot message with one image attachment, proving that non-text media payloads are no longer dropped before Rails.
- The synthetic validation conversation was resolved after the check to avoid leaving a test conversation open.

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

## Product Decisions

- Do not add NATS until message correctness is stable. The current media loss was caused by the Go event handler discarding non-text messages before Rails, not by queue backpressure.
- Chatwoot already uses its own realtime/websocket pipeline after messages are created. The right first fix is to create proper messages and attachments; a separate websocket layer inside whatsmeow can be considered later only if realtime delivery remains unreliable.
- Keep groups enabled when `ignore_groups` is off. If group messages should be hidden, use the inbox setting instead of hardcoding the behavior.
- Keep newsletters filtered when `ignore_newsletters` is on.

## Validation Checklist

- Send and receive direct text messages.
- Send and receive group text messages.
- Receive stickers, images, audio/voice notes, videos, and documents.
- Send an image/file/audio from Chatwoot and confirm it arrives in WhatsApp.
- Confirm group media lands in the group conversation, not in a separate per-participant conversation.
- Confirm the composer shows emoji, attach, audio recorder, signature, and send controls when the account feature flags allow them.
- Confirm Whatsmeow conversations no longer show the missing signature warning.
- Confirm receipts move outgoing messages from sent to delivered/read when WhatsApp emits those events.

## Known Operational Notes

- Local Ruby may not be installed on every workstation; Ruby validation may need CI or the container.
- Local Docker may not be available; use GitHub Actions and staging deploy for end-to-end checks when needed.
- Portable Go can be used from `.codex/tools/go/bin/go.exe` if system Go is missing.
- Do not commit generated binaries such as `whatsmeow-service.exe`.
