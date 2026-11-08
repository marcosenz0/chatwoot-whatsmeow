# Video preview and gallery sizing — November 7, 2026

Clicking or using the keyboard on a conversation video preview opens the gallery and requests playback there. The message preview renders a muted frame with a play affordance and keeps the caption and timestamp in the existing card.

The player measures the gallery's available media area and reads the video's aspect ratio from its metadata. It scales up smaller files and scales down larger ones to the available width and height. The playback controls stay on the video frame. The photo viewer and sticker rendering use their existing paths.

Chrome validation used the actual Chatwoot components and styles. The check exercised a click near the edge of the preview, keyboard opening and gallery navigation, opening a photo, the compact sticker, and seeking, playback speed, vertical volume drag and mute restoration. At a 1680 × 950 viewport the landscape sample grew from 640 × 360 to 1388 × 781. The portrait sample grew from 360 × 640 to 439 × 780. The 160 × 124 sample fitted at 452 × 350 in the short desktop layout and at 326 × 253 in the 390 px layout. The local focused suite passed 301 tests.

Gate [42397395848](https://github.com/marcosenz0/chatwoot-whatsmeow/actions/runs/42397395848) passed 505 frontend tests and 556 Rails examples, lint, Vite compilation and image publication. Principal was validated first, then MX and MD. All six web and worker containers run `fork-e6beec7abc846fadf8e2a23713268b5e24d9f9b1`, image ID `sha256:31b0ed2ffe3eef5d97a41bb7c47de7c1dcd6b3fb6fa25f482af48ef4088adfc8`. All three public health endpoints returned HTTP 200. Eleven source hashes and three public JS/CSS samples matched per host.

The audit compared 31 service configurations. It found the six app pin changes and matched the six bridge containers and session statuses. The 157 AI conversation states, profiles, preferences and stored-data hashes matched the pre-release baseline. Browser interaction used synthetic fixtures. The public rollout was verified by the installed image and served assets. The correction is included in [PR #63](https://github.com/marcosenz0/chatwoot-whatsmeow/pull/63).
