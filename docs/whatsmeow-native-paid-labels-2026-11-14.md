# Native WhatsApp Business Pago label

**Live checkpoint, November14 at19:46 GMT-3:** implementation commit
`08c66ddf81f0c9af9a9de9136aa8021f98cc7bec` passed GitHub run43648792032
(including race/vet/Docker) and is running on the existing Alice service/session.
The amd64 manifest is `sha256:9f6da303a8f914c040d1360f536a4d139872d43cceffc9cf48b60a28d48bf4bc`;
runtime ImageID matches GHCR config `sha256:8da4789cc1cfdb170cee55fc9750337e68ea10c2e618876e93d7cf013bc20b89`.
Read-only catalogue observed Pago ID4/preset4; one owner-only test returned202,
readback observed the association and the user confirmed it visually in WhatsApp.
No ledger payment or CAPI event was created. Other labels were preserved.
The test mode/key/target were disabled/cleared and a new process was verified
connected; production writes remain disabled at this checkpoint. Automatic
payment integration is still being installed/reviewed separately.

The existing bridge's `:channel_id` parameter is the **inbox ID**: Alice session
scope15, while the Chatwoot database channel ID is7. Keep those scopes separate.
The real-test evidence is in the Low Ticket project at
`implementacao/etiqueta-whatsapp-poc-2026-11-14/prova-real-pessoal.json`.

Work is isolated on `codex/whatsmeow-native-paid-labels`, based on the exact
production service source `0632806ba01bdc63e6dd8ddc10af2d9466f0b60f`.
It preserves the profile, status, call and native Pix dependency patches.
This document describes prepared code, not proof of a deployed label.

The historical n8n flow used Evo Go `/label/chat` with a numeric label ID.
Current n8n originals still contain that request but are inactive; the current
VPS has no Evo Go service and its former public endpoint returns 404. That
historical ID is not a verified catalogue for Alice's present Whatsmeow session.

## Private routes and rollout

All routes require the existing internal token. Only the explicitly configured
`NATIVE_PAID_ALLOWED_CHANNEL` can read the catalogue or an exact association.

- `GET /sessions/:channel_id/native-labels`: obtains a MAC-validated complete
  regular app-state snapshot on the existing client, decoded into scratch state.
- `POST /sessions/:channel_id/native-labels/check`: reads an exact individual
  target from the JSON body. A missing observation is not proof of failure,
  including when PN and LID aliases differ. It never sends an association.
- `POST /sessions/:channel_id/native-labels/identity`: returns private PN/LID
  aliases only after checking the current session's reversible mapping, and a
  stable SHA256 session fingerprint. Missing aliases fail closed. The payment
  resolver must independently bind the actual Chatwoot account/inbox/contact.
- `POST /sessions/:channel_id/native-labels/paid`: also requires a dedicated,
  short-lived HMAC over account, channel, conversation, payment UUID, amount,
  exact target and label, nonce and expiry. The signing authority must independently
  validate payment and identity; this service does not validate bank receipts.

Start with `NATIVE_PAID_WRITE_ENABLED=false`. No receipt DDL is run in this mode.
Read and verify the real catalogue and the corresponding label on Alice's phone
before configuring `NATIVE_PAID_LABEL_ID` and `NATIVE_PAID_PREDEFINED_ID`.
No enum value has been guessed. A positive preset marker and name alone are not
independent proof that Meta receives a purchase event.

For write mode, provision a dedicated `NATIVE_PAID_SIGNING_SECRET` of at least32
bytes and the correct `NATIVE_PAID_ALLOWED_ACCOUNT`. Keep these in protected
configuration, never exports, source or workflow execution output. The current
offer is restricted to1490 cents. Enabling writes initializes only the receipt
table embedded from `whatsmeow-service/migrations/native_paid_receipts.sql`.
An initialization error stops startup rather than continuing without replay
protection. No customer JID or bank proof is stored in that table.

Both write and reconciliation require `NATIVE_PAID_EXPECTED_SESSION_IDENTITY`
to match the currently connected device fingerprint. A replacement pairing on
the same channel therefore cannot silently receive an old authorization.
Both PN and LID associations are read from one validated snapshot; a positive
association on either alias blocks another write. Missing or contradictory
mapping never means the label is absent.

The owner-authorized smoke test uses `/native-labels/paid-test`, a separate
`NATIVE_PAID_TEST_SIGNING_SECRET`, `test-v1` signature domain, an exact
`NATIVE_PAID_TEST_JID` contact scope and `NATIVE_PAID_TEST_WRITE_ENABLED`.
It creates only a purpose-tagged technical receipt, never a payment/ledger row.
Production payment signing stays disabled for this test. Turn test writes off
after the single observation. No CAPI or synthetic purchase event is sent by
the service; WhatsApp's own activity sharing is a separate app setting.

Before a write the catalogue and exact association are read again. An existing
association returns `observed_on_target` without any IQ. A new association only
adds the confirmed label; it does not replace or remove other labels. A durable
unique order reservation commits before one IQ; nonce/order deduplication survives
restarts. The library explicitly avoids automatic409 retry. Timeout, result
persistence failure, crash or post-submission sync failure remain uncertain.
`202 submitted` is not evidence of delivery. A repeated order returns409 and its
known state, never another IQ, even with a renewed nonce. Reconciliation reads
must use the same frozen target and label; do not replace an uncertain order.

## Build, deployment and rollback

The existing GitHub workflow builds and publishes only the isolated branch plus
its existing allowed branches. It patches the exact dependency version, runs
service tests/vet/race, targeted dependency tests and the Docker build, and
publishes `ghcr.io/marcosenz0/chatwoot-whatsmeow:whatsmeow-<commit>`.
No develop merge is required. Never ship local test.mod replaces.

Deployment target is Alice's existing `marcos-apps/whatsmeow-staging`, using the
same DATABASE_URL and current session, one replica and no parallel second client.
Read live queue/backlog and ensure no sending/uncertain jobs before the short
single-replica restart. Preserve campaigns, consent, inboxes and all other service
configuration. Monitor reconnect/health and the queue after deployment.

The current rollback image is the immutable manifest
`ghcr.io/marcosenz0/chatwoot-whatsmeow@sha256:ef1df1b8d17c3df386c94d7d912394375b80da3b25d0e2166159047df2da79f3`.
Rollback changes software only, preserving all database/session data and receipt
reservations. Never overwrite the live database with a pre-deployment backup
after new messages arrived. A fresh logical backup was restored into a separate
stopped sandbox by the backup task; no sandbox WhatsApp client was started.

## Validation and remaining evidence

Local service tests and vet pass, including signature tampering, disabled scope,
MAC tampering, incomplete/paginated catalogue, session isolation, exact association,
uncertain completion, one concurrent send and prior observed labels. Linux CGO0
compilation passed. Lower transport-boundary tests cover success,409, timeout,
missing response and nil response with exactly one send. Ten assertions execute
the exact embedded SQL/Go query strings in local PostgreSQL WASM, including disk
close/reopen deduplication. This is not a real multi-backend PostgreSQL stress test
or proof of a phone/Meta action. GitHub CI adds race and clean Docker verification.

Still required before claiming end-to-end completion: successful published-image
CI, verified runtime digest and reconnect, real catalogue/target identity, trusted
signer/outbox provisioning, actual label observation, and separate Meta attribution
verification. No label was applied by local tests.
