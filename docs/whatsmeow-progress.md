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
