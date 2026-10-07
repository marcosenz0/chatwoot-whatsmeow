# PDF viewer — October 7, 2026

PDF attachments offer **Ver** beside the existing **Baixar** action in message bubbles, including favorites and message previews. The files panels also open PDFs inside Chatwoot. Other file types retain their existing download behavior.

The full-screen viewer includes page navigation, zoom, document search, selection, drawing, highlighting, underlining, strikeout and adding text. **Editar PDF** exposes the annotation tools. The header and options menu can return to the original message; the existing conversation anchor/highlight is reused. Files opened from the contact's media panel use the attachment's original conversation ID. The menu also copies the message link, opens the original file in another tab and saves a PDF copy containing annotations. Forwarding uses the existing message forwarding flow where supported.

## Implementation

Branch `codex/pdf-viewer`, PR [33](https://github.com/marcosenz0/chatwoot-whatsmeow/pull/33), based on `58563a8a78` from the personal Telegram branch. Preserve the existing Telegram/Whatsmeow integrations; the older `develop` branch is not the deployed source.

The reader uses EmbedPDF 2.15.1 and PDFium. The heavy reader code loads only after opening a PDF. The engine WASM is bundled locally, and its URL is resolved absolutely for the worker. Remote font/stamp libraries are disabled. Document processing happens in the browser through existing attachment URLs and access controls. No new Rails endpoint or database migration was introduced, and no corresponding Enterprise component override exists.

Annotations are exported to a downloaded copy; the original conversation attachment is preserved. Editing existing document text/images with Acrobat, OS-specific “Open with”, WhatsApp reporting and private-reply actions are not reproduced. Use the ordinary conversation actions for replies.

English and Brazilian Portuguese interface strings are included. Reader toolbar translations use the library's Portuguese locale with English fallback.

## Validation

[Final gate 37665237948](https://github.com/marcosenz0/chatwoot-whatsmeow/actions/runs/37665237948) passed: 195 existing frontend tests in 13 files, 106 Rails examples, scoped ESLint and production Vite build. Three non-blocking localization warnings remain (two existing and the annotation menu's dynamic translation key). Local Git hooks could not run because the checkout lacks `.husky/_/husky.sh`; checks ran directly and in the Linux gate instead. General repository CI has existing unrelated failures; this is not a claim that every repository suite passes.

Manual Chrome validation used the user's primary profile, an actual file bubble, the shared-files component and a synthetic three-page PDF. Confirmed PDF-only **Ver**, unchanged non-PDF download, rendered pages, zoom, page navigation, three search results, drawing, highlighting and copy export. The exported PDF was structurally checked: three pages and one Ink annotation. A PDF opened from the contact files returned to the correct account/conversation/message URL. No test message was sent to another person.

Live MX validation opened an existing ten-page PDF from a conversation and from favorites. **Ir para a mensagem** closed the viewer, located the original attachment and visibly applied the existing highlight ring, including when already on that same message URL. No browser error appeared during document loading. Principal's application loaded after deployment; the new reader JS and local WASM assets returned 200 with correct MIME types.

## Deployment

Published image: `ghcr.io/marcosenz0/chatwoot-whatsmeow:fork-c4bdb5175329e484de9063a9337c9fc4648782b0`.

Manifest digest: `sha256:0f20ce3c123eedff2220cb3d6e1a2974e71ae1dbe95b025d0ed9bb6b4c3d8561`.

All six custom web/Sidekiq services run this exact image and share the same Docker image ID. Principal was validated first, then MX, then MD. All three `/health` endpoints returned 200.

| Target | Domain | Web service | Worker service |
| --- | --- | --- | --- |
| Principal | `chatwoot.marcoswt.com.br` | `chatwoot-staging` | `chatwoot-staging-sidekiq` |
| MX | `chatwootmx.marcoswt.com.br` | `chatwoot-mx` | `chatwoot-mx-sidekiq` |
| MD | `chatwootmd.marcoswt.com.br` | `chatwoot-md` | `chatwoot-md-sidekiq` |

Compared against the private pre-deployment snapshot: per-instance environments, mounts, ports, domains, deployment commands and resource limits are unchanged. All Whatsmeow and personal Telegram bridge image/container IDs are unchanged; their sessions were preserved. Official Chatwoot remains untouched. Main-checkout pre-existing local changes were preserved; only this handoff and the short active-memory entry were added there.

The final deployed dashboard asset is `dashboard-CTPqlamT.js`; the reader is `PdfDocument-BiLlfltn.js` and engine `pdfium-BJ2Yip8Q.wasm`. A screenshot of the final MX viewer and its Portuguese edit menu is saved locally at `C:/Users/marco/.codex/visualizations/2026/10/07/01a1175d-c223-7300-9b2f-b3f71f6f6f2b/pdf-viewer-mx-final.jpg`. Do not commit screenshots containing personal messages.
