# Conversation voice recordings — November 9, 2026

The composer discards a recording through either the microphone toggle or the red X beside MarcoXIA. The X is available while the microphone is starting, while recording, and while the recording is being prepared or previewed. The square stops for preview. Enviar can also stop, prepare and submit the active recording in one click.

The previous reset removed attachments with the WhatsApp Cloud voice flag. A Whatsmeow recording could remain in the composer as a recorded attachment without that flag. Conversion, direct upload and the FileReader preview could also finish after the operator had moved on. The recorder now discards callbacks after cancellation and releases late microphone permissions. The composer stages one attachment for the current recording, waits for the configured upload path, and invalidates pending work on discard, navigation and unmount. Manually attached files keep the existing flow.

Chromium used its real MediaRecorder and the Chatwoot stylesheet with a fake microphone and isolated send action. The tests covered repeated discards, the X by keyboard, stop and playback, sending during capture, double clicks, late microphone permission, route changes and a 640 px viewport. A mocked Active Storage request covered an upload completing during the next recording and upload failure followed by another recording. Payload checks covered Whatsmeow MP3, WhatsApp Cloud OGG voice, Telegram Personal MP3 voice and web widget WAV. No channel message was sent for verification.

A synthetic PNG selected through the normal file picker remained attached after recording and discarding audio.

## Validation and release

The local scoped suite passed 108 tests. The [fork gate](https://github.com/marcosenz0/chatwoot-whatsmeow/actions/runs/42623567982) passed 515 frontend tests and 556 Rails examples, scoped lint, the frontend build and image publication. The complete local frontend suite had 4,974 passes and 19 failures. Rerunning the four failing suites on the prior release source reproduced the same 19 failures. The generic [CE workflow](https://github.com/marcosenz0/chatwoot-whatsmeow/actions/runs/42623578795) could not start its Rails suites because Ruby 3.4.4 was unavailable on its Ubuntu 26.04 runner.

Principal was validated first, then MX and MD. The image tag is `fork-10f60eae29b81d26ee9eb4cd8938ccbfce50bff1` and the registry index digest is `sha256:b5b719d110d4c9d2714775820cc3b38e3b87b7796894e1c8b37c0742ef470d4d`. The published checks match five source hashes and four served JS and CSS samples per domain, including the recorder, composer, cancel control and X icon stylesheet. The review branch is stacked above PR #63. [PR #64](https://github.com/marcosenz0/chatwoot-whatsmeow/pull/64)

All six web and worker containers run image ID `sha256:e881e7b3c5efe6924d929d0f3083c554a576494774d2fb627fd7d7a51aaa5ae7`. All three health endpoints returned HTTP 200. The audit compared 31 service configurations and found six app pin changes. Six bridge containers and their session statuses, all 171 AI conversation states, both profiles, user preferences and the stored-data hashes matched the baseline.
