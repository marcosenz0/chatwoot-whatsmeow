# MarcoXIA transcription selection and quiet inactive badges

The Voice and audio section now separates understanding incoming voice notes from generating voice replies. Each agent may keep its previous provider-dependent transcription or explicitly choose Groq/OpenAI and a supported transcription model. Explicit selection uses an enabled MarcoXIA provider credential, or the already-saved key for the same provider in the account's enabled audio transcription integration. Keys are never copied into the agent config or exposed by the options endpoint. It never silently switches providers. Cached transcripts remain reusable, and the existing process_audio switch applies independently of synthesized voice.

New per-agent config is transcription.provider/model; absent config retains the legacy agent path, including Gemini. Models/provider combinations are validated at the request boundary. Explicit transcription calls record the selected provider/model/credential source and any returned usage without saving audio content in logs. No database migration is needed.

The conversation list hides the inactive badge while general support is off. A manually active conversation retains its normal active indicator. With general support on, an explicit conversation pause displays IA desligada. Mere assignment, global suspension and technical errors do not become that manual-pause label. Existing human-assistance and resolved/snoozed behavior is preserved. The public state adds general_enabled and manually_paused; no state activation is rewritten for this UI change.

Local checks: targeted existing Vue specs and scoped ESLint; full MarcoXIA CI/build and runtime/visual verification are recorded below when completed. Public product copy includes English and Brazilian Portuguese, following the fork's required Portuguese delivery.

Deployment scope remains principal first, then the same image on MX and MD, including their workers. Preserve all inboxes, credentials, voice/Pix/resources/contact memories, pending batches and bridge sessions. Do not send customer messages or execute existing batches for verification.

Initial MD inspection confirmed the existing integration is Groq / whisper-large-v3-turbo / fallback none, with a saved key. MarcoXIA currently has only its OpenAI credential, so the new Groq path must reuse the integration key. The agent stays on gpt-6-luna and voice synthesis stays on ElevenLabs. Production validation and the selected MD transcription setting will be recorded after publication.
