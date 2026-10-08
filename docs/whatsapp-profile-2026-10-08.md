# WhatsApp connected profiles and full photos — October 8, 2026

## Product behavior

WhatsApp Direct inbox settings now have a **Perfil** tab in Brazilian Portuguese. It loads the actual connected WhatsApp account on entry and refresh, including its full photo, name, about, phone and Business details. The existing inbox avatar remains a separate Chatwoot setting.

The photo has a camera overlay and the native **Mostrar foto**, **Tirar foto**, **Carregar foto** and **Remover foto** menu. A file or camera frame opens a drag/zoom crop with a circular preview. Only **Salvar foto** publishes the square JPEG; zoom, reset, drag and cancel do not publish. Removal requires the native confirmation dialog. Camera tracks and object URLs are released when their dialogs close, including delayed camera permissions.

Name and about edit independently. The current WhatsApp About uses an expiring text status: the editor offers 1 hour, 8 hours, 24 hours, 3 days and 7 days, retains an existing positive duration and preserves the current emoji. An empty About sends the provider's null/zero-duration clearing request. Business profiles additionally expose address, email, description, up to two websites, timezone and weekly hours, including closed, defined hours, open 24 hours and appointments. Changing commercial text preserves the existing hours unless the hours themselves are edited.

Contact avatars in the conversation header, contact sidebar and voice notes open a full-screen photo viewer with the person's name. WhatsApp requests the provider's current full image rather than stretching Chatwoot's thumbnail. Outgoing voice-note photos use the connected WhatsApp account. Provider privacy/no-photo states do not expose an old cached avatar; network failures offer retry.

## Implementation and access

Branch `codex/whatsapp-profile`; PR [35](https://github.com/marcosenz0/chatwoot-whatsmeow/pull/35), above unmerged MarcoXIA PR 34 and the existing PDF/Telegram stack. Preserve that stack and the main checkout's existing changes. Related OSS and Enterprise paths were checked; there are no corresponding profile overrides.

New bridge profile endpoints require the existing internal token and always edit the connected session identity. They use the pinned hypermeow profile, push-name app-state, text-status and Business APIs. Full-photo reads explicitly request `Preview: false`. Uploads are square JPEGs, 192–2048 pixels, under 2 MB; the browser exports a 640-pixel JPEG after preview.

The pinned dependency has a small, tested patch to query and parse the modern `text_status` user-info node, including emoji, duration and the explicitly cleared state. It keeps this metadata separate from legacy status text, so clearing About cannot redisplay old text. The patch is applied in both the bridge validation job and Docker build; the dependency version and existing session database remain unchanged.

Rails limits profile editing to inbox administrators. Assigned agents can view allowed photos; trusted account-scoped contact/inbox identities determine contact photo queries. Caller-supplied JIDs are ignored, and account/inbox access is checked before calling the bridge. Other channels retain the original stored avatar viewer. UI components use the existing dialogs, menus, buttons, avatars and Tailwind colors.

## Validation and deployment

Gate [37845790207](https://github.com/marcosenz0/chatwoot-whatsmeow/actions/runs/37845790207) passed **512 targeted frontend/Rails checks** (279 frontend tests, 233 Rails examples), scoped lint, the production frontend build, the complete bridge and meowcaller suites, the pinned About parser test and Go vet. It published the final app and bridge images from `57b0bf6685237dc737246c47c00f997435b7d19b`:

- App: `ghcr.io/marcosenz0/chatwoot-whatsmeow:fork-57b0bf6685237dc737246c47c00f997435b7d19b`, OCI index digest `sha256:64ce7f33eda6c273c589cba2c90ceae0573fb533ae3617c2798f4fef9c5a1ed2`, image ID `sha256:02f2a732458dc3907248a3f31277cb87d17e818749dbdb2ff06e346d60309eb3`.
- Bridge: `ghcr.io/marcosenz0/chatwoot-whatsmeow:whatsmeow-57b0bf6685237dc737246c47c00f997435b7d19b`, OCI index digest `sha256:c40594b8c23f4a401770c29a567b241d4a9d713f87c5301065530c2e8054180e`, image ID `sha256:b3c4fdc7431cc7d0daf7b1441b6efbbc7cf9736ed2033d831ff7843008d8be4f`.

Principal was validated first; its native profile page loaded the actual connected profile, saved the existing name through the UI and displayed the current 640×640 photo. Account-scoped profile and contact-photo HTTP reads returned 200. The owner conversation's header and contact sidebar both opened the provider's loaded 640×640 photo, with the IA still paused. The same exact app image is now on all six principal/MX/MD web and worker services, and the same bridge image is on all three Whatsmeow services. All three app health endpoints returned 200. MD's indicated conversation also opened the full 640×640 photo directly from its voice note.

All **29 existing service configurations** compared equal after excluding only the intended image tags and the deployment URL: environments, secrets, domains, mounts and other source fields were retained. Telegram container and image identities remained unchanged. Principal inboxes 27/28, the personal MX inbox 1, and MD inboxes 6/8 recovered connected without QR; MD personal Telegram inbox 7 remained connected. Previously disconnected inboxes stayed disconnected. Globally enabled AI-profile counts remained zero in all targets; Felipe's general support/automatic start remains off and owner conversation 2170 remains paused. The official Chatwoot instance was outside the rollout.

The first principal app deployment request exceeded the panel HTTP response timeout while pulling the image. Its running container was inspected before continuing; the web image was not redeployed, and only the remaining worker step was completed. Transient unavailable pages during normal startup cleared, followed by successful health, API and native-browser checks.

The principal Poco inbox preserving tests passed for the existing name and commercial details, with hours retained. Its exact existing photo was republished and loaded successfully; WhatsApp recompresses the image, so returned bytes differ. The full-photo endpoint returned the owner contact's current image. The first live About test exposed the provider's rejection of empty-string/zero-duration requests; the modern null/zero-duration fix and parser were added, validated and successfully tested on the principal without changing its existing empty About, name, emoji or Business details. Previously connected principal sessions recovered without QR.

## Limits

The pinned WhatsApp library can read Business categories but does not expose category edits; the profile displays the category and instructs the user to change it in WhatsApp Business. Verified business identity/number changes, catalogs, payment information and profile privacy settings remain in the WhatsApp application. Photo visibility and the maximum resolution follow WhatsApp's provider response.

Camera access uses the browser's explicit permission and requires HTTPS (or localhost). Camera denial, capture and delayed-close cleanup are tested with simulated streams; physical camera output is not part of the automated test. File upload and crop were manually verified in Chrome at desktop, notebook and narrow widths. Tests do not require replacing real profiles with synthetic photos or deleting existing photos.

Native Chrome screenshots confirmed the published profile/menu and contact viewer. Their private local proof files are intentionally not committed because they contain personal profile images and account details. PR 35 is ready for review, mergeable and remains unmerged above PR 34.

## Repeat guide

Open a connected WhatsApp Direct inbox's **Perfil** tab, refresh its current details, and save name/about separately. Upload a disposable image in a local test, drag/zoom/reset, cancel and confirm; verify only confirmation changes the photo. Test removal only on a disposable profile. For a real preserving test, republish the exact existing photo and save the same existing text values. Never store private profile contents, photo URLs, images, API keys or session secrets in this handoff.

Click the contact avatar at the header, sidebar and voice note; check the full-image dimensions, retry and private/no-photo states. Validate principal first, then use the same pinned app and bridge images on MX and MD. Preserve each target's environment, mounts, data and sessions; check Telegram container/image identities are unchanged and previously connected WhatsApp sessions recover without QR. The official instance is outside this rollout.
