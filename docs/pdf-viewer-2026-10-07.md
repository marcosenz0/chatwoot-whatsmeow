# PDF viewer — October 7, 2026

PDF attachments offer **Ver** beside the existing **Baixar** action in message bubbles, including favorites and message previews. The files panels also open PDFs inside Chatwoot. Other file types retain their existing download behavior.

The corrected full-screen viewer follows the WhatsApp reference: one compact header with the sender's avatar, sender/file name, date and actions, a charcoal document background, and a small vertical page/total/previous/next/zoom control at the bottom right. The reader's blue toolbars and permanent editing tabs are removed. The document initially occupies about 70% of the desktop viewer width; narrower screens fit the document to the available width.

**Editar PDF** contains drawing, highlighting, underlining, strikeout and adding text. **Mais ferramentas** contains shapes, image/signature insertion, forms, redaction, annotation style, selection and undo/redo. The options menu contains thumbnails, comments, fit width/page, printing, copying the message link, opening the original in another tab and saving a copy with annotations. Optional panels appear only when requested; the floating navigation moves aside for right-hand panels.

The header and options menu return to the original message using the existing conversation anchor/highlight. Files opened from the contact's media panel use the attachment's original conversation ID. Forwarding, favorites and reactions reuse the existing message actions where supported; read-only previews retain their existing eligibility rules.

## Implementation

Branch `codex/pdf-viewer`, PR [33](https://github.com/marcosenz0/chatwoot-whatsmeow/pull/33), based on `58563a8a78` from the personal Telegram branch. Preserve the existing Telegram/Whatsmeow integrations; the older `develop` branch is not the deployed source.

The reader uses EmbedPDF 2.15.1 and PDFium. The heavy reader code loads only after opening a PDF. The engine WASM is bundled locally, and its URL is resolved absolutely for the worker. Remote font/stamp libraries are disabled. Document processing happens in the browser through existing attachment URLs and access controls. No new Rails endpoint or database migration was introduced, and no corresponding Enterprise component override exists.

An explicit EmbedPDF UI schema has empty toolbars, menus and overlays, while retaining the optional sidebars, dialogs and text/annotation context menus. Chatwoot owns the visible header and page controls rather than hiding library controls with CSS or manipulating their DOM. Plugin events synchronize page numbers, undo/redo availability and panel position; subscriptions are released when the viewer unmounts. Product styling uses Tailwind utilities and existing theme colors.

Annotations are exported to a downloaded copy; the original conversation attachment is preserved. Editing existing document text/images with Acrobat, OS-specific “Open with”, WhatsApp reporting and private-reply actions are not reproduced. Use the ordinary conversation actions for replies.

English and Brazilian Portuguese interface strings are included. Optional library panels and advanced command labels use the library's Portuguese locale with English fallback. The header date uses the active Chatwoot locale.

## Validation

[Final gate 37673535975](https://github.com/marcosenz0/chatwoot-whatsmeow/actions/runs/37673535975), for source `47a7931dc346640e0e809c04388b7432617acc7d`, passed: 195 existing frontend tests in 13 files, 106 Rails examples, scoped ESLint and production Vite build. ESLint has zero errors and two existing warnings in BaseAttachment/shared Files; the PDF menu's former dynamic-key warning is resolved. Local Git hooks could not run because the checkout lacks `.husky/_/husky.sh`; checks ran directly and in the Linux gate instead. General repository CI has existing unrelated failures; this is not a claim that every repository suite passes.

Manual Chrome validation used the user's primary profile, the real Vue components and a synthetic three-page PDF. Confirmed the clean layout at 1324 × 860 and 960 × 860, page advancement, direct page entry with Enter, zoom, three search results, right-panel navigation offset, thumbnails, Portuguese edit/advanced menus, drawing, undo/redo and copy export. The latest exported copy was structurally checked: three pages, one Ink annotation and 2,905 bytes. The initial delivery also verified PDF-only **Ver**, unchanged non-PDF download, favorites and contact-file navigation. No test message or reaction was sent to another person.

Live MX validation after this correction opened the user's existing ten-page PDF. Confirmed the single header, sender avatar, clean background, floating navigation, page 1 → 2 → 1, **Editar PDF**, the advanced tool groups and options menu. **Ir para a mensagem** closed the viewer, highlighted the original attachment and scrolled it into view while already on the same message URL. Forwarding opened the existing dialog with zero recipients selected; it was closed without sending. Principal and MD applications loaded after deployment. Dashboard/reader JS and local WASM assets returned 200 on all three domains; WASM retained the correct MIME type. An in-flight MX request returned 502 during service startup and recovered after reload; no PDF reader error was observed after loading.

## Deployment

Published image: `ghcr.io/marcosenz0/chatwoot-whatsmeow:fork-47a7931dc346640e0e809c04388b7432617acc7d`.

Manifest digest: `sha256:07f58688d273c3dfaba396f25d36f73690cfa219a447ed24fb78088ad22f47ca`.

All six custom web/Sidekiq services run this exact image and share the same Docker image ID. Principal was validated first, then MX, then MD. All three `/health` endpoints returned 200.

| Target | Domain | Web service | Worker service |
| --- | --- | --- | --- |
| Principal | `chatwoot.marcoswt.com.br` | `chatwoot-staging` | `chatwoot-staging-sidekiq` |
| MX | `chatwootmx.marcoswt.com.br` | `chatwoot-mx` | `chatwoot-mx-sidekiq` |
| MD | `chatwootmd.marcoswt.com.br` | `chatwoot-md` | `chatwoot-md-sidekiq` |

Compared against the private pre-deployment snapshot: per-instance environments, mounts, ports, domains, deployment commands and resource limits are unchanged. All Whatsmeow and personal Telegram bridge image/container IDs are unchanged; their sessions were preserved. Official Chatwoot remains untouched. Main-checkout pre-existing local changes were preserved; only this handoff and the short active-memory entry were added there.

The final deployed dashboard asset is `dashboard-B9Kf5tbF.js`; the reader is `PdfDocument-C6T3ZPwn.js` and engine `pdfium-BJ2Yip8Q.wasm`. Current screenshots of the clean MX viewer and its Portuguese edit menu are saved locally at `C:/Users/marco/.codex/visualizations/2026/10/07/01a1175d-c223-7300-9b2f-b3f71f6f6f2b/pdf-viewer-mx-clean.jpg` and `pdf-viewer-mx-clean-menu.jpg` in the same directory. The earlier `pdf-viewer-mx-final.jpg` depicts the superseded toolbar layout. Do not commit screenshots containing personal messages.
