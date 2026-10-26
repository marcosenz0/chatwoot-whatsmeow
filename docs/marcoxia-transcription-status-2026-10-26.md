# MarcoXIA transcription selection and quiet inactive badges

The Voice and audio section now separates understanding incoming voice notes from generating voice replies. Each agent may keep its previous provider-dependent transcription or explicitly choose Groq/OpenAI and a supported transcription model. Explicit selection uses an enabled MarcoXIA provider credential, or the already-saved key for the same provider in the account's enabled audio transcription integration. Keys are never copied into the agent config or exposed by the options endpoint. It never silently switches providers. Cached transcripts remain reusable, and the existing process_audio switch applies independently of synthesized voice.

New per-agent config is transcription.provider/model; absent config retains the legacy agent path, including Gemini. Models/provider combinations are validated at the request boundary. Explicit transcription calls record the selected provider/model/credential source and any returned usage without saving audio content in logs. No database migration is needed.

The conversation list hides the inactive badge while general support is off. A manually active conversation retains its normal active indicator. With general support on, an explicit conversation pause displays IA desligada. Mere assignment, global suspension and technical errors do not become that manual-pause label. Existing human-assistance and resolved/snoozed behavior is preserved. The public state adds general_enabled and manually_paused; no state activation is rewritten for this UI change.

Local checks: targeted existing Vue specs and scoped ESLint; full MarcoXIA CI/build and runtime/visual verification are recorded below when completed. Public product copy includes English and Brazilian Portuguese, following the fork's required Portuguese delivery.

Deployment scope remains principal first, then the same image on MX and MD, including their workers. Preserve all inboxes, credentials, voice/Pix/resources/contact memories, pending batches and bridge sessions. Do not send customer messages or execute existing batches for verification.

Initial MD inspection confirmed the existing integration is Groq / whisper-large-v3-turbo / fallback none, with a saved key. MarcoXIA currently has only its OpenAI credential, so the new Groq path must reuse the integration key. The agent stays on gpt-6-luna and voice synthesis stays on ElevenLabs. The MD transcription choice is now saved as Groq / whisper-large-v3-turbo, using that existing integration key.

An explicit individual resume also works while manual-only attendance is suspended. Only that conversation receives an override; existing suspended members remain suspended. A later on-to-off manual-attendance switch clears the overrides so the group pause remains effective. The current MD setting therefore does not require enabling all seven prior manual contacts to activate one person.


## Published verification — October26,2026

Principal first, then MX and MD web/worker pairs were deployed on `fork-0bb96e3d3d35c2199532403b4d5bebc5723552a6`. [Gate40369441831](https://github.com/marcosenz0/chatwoot-whatsmeow/actions/runs/40369441831) passed424 frontend tests and381 Rails examples (805 targeted), lint/build/image. All three health endpoints200 and three published rollback contracts passed, with no external calls or deliveries in those contracts. PR53 is stacked on52.

Before/after audits preserve106conversation states, all data/credentials/voice/resources/memories/Pix/hooks/batches (MD3batches/16items), twelve service configs except six app pins, six bridge container/image identities and all prior session statuses. Only the MD agent transcription selection changed. General remainsOFF, reply model gpt-6-luna, synthesis ElevenLabs. Existing disconnected principal sessions remain as before.

One real Groq/Turbo transcription of neutral synthetic speech passed in0.662s in an isolated candidate process before deployment. No Luna/ElevenLabs generation or customer message; database rolled back. Candidate TranscriptionClient/Assistant normalized source hashes match the published sources; no redundant paid test was made after deployment.

Published MD UI confirmed the quiet list, saved Groq/Turbo, integration credential source and unchanged ElevenLabs. The provider menu supports ArrowDown and Escape restores trigger focus. Synthetic real-component/CSS preview covered five badge cases and390px width without horizontal overflow. No actual customer activation or batch execution was used for visual checks. HOT operational record and Notion Acompanhamento/Ferramentas carry the final evidence; private raw snapshots stay ignored in `.codex`.
