# Video loading and message selection — November 7, 2026

The expanded video shows a centered loading indicator until the first frame is available, then displays the frame and playback controls. If the video fails to load, the gallery shows the media-unavailable state. The expanded player requests media immediately. When the gallery opens on a video, requests for its video thumbnails wait for the selected video to show a frame or report an error. Image thumbnails use lazy loading and low fetch priority.

The time required to hold a selectable message decreased from 900 ms to 500 ms. The visual progress bar uses the same duration.

Browser validation delayed the selected video response and verified the centered indicator, the hidden controls, the deferred thumbnail sources and the transition to playback. It also covered a failed media request and timed a real mouse hold at 502 ms. Releasing early canceled selection. The local focused suite passed 301 tests.

Gate [42431221511](https://github.com/marcosenz0/chatwoot-whatsmeow/actions/runs/42431221511) passed 505 frontend tests and 556 Rails examples, lint, Vite compilation and image publication. Principal was validated first, then MX and MD. All six web and worker containers run `fork-01750c07364fdfdd1c3efac0e13fb4be35e453bd` with image ID `sha256:e9cb5da1b52aad93efa49fe5ba5ea6c5c13034f26f199e88b77fbf9cdd308490`. All public health endpoints returned HTTP 200. Twelve source hashes and three public JS and CSS samples matched per host.

The audit compared 31 service configurations. It found the six app pin changes and matched the six bridge containers and session statuses. The 157 AI conversation states, profiles, preferences and stored-data hashes matched the pre-release baseline. Browser tests used synthetic videos and a delayed response. The rollout was verified through the installed image and served assets. [PR #63](https://github.com/marcosenz0/chatwoot-whatsmeow/pull/63)
