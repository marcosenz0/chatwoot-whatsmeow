export const fallbackDefaults = {
  enabled: false,
  provider: 'openai',
  connection_id: null,
  model: 'gpt-6-luna',
};
export const transcriptionFallbackDefaults = {
  ...fallbackDefaults,
  model: 'gpt-4o-transcribe',
};
export const providerChoices = [
  { value: 'openai', label: 'OpenAI', icon: 'i-lucide-sparkles' },
  { value: 'groq', label: 'Groq', icon: 'i-lucide-zap' },
  { value: 'gemini', label: 'Google Gemini', icon: 'i-lucide-sparkle' },
];

export const connectionActive = (status, credential, provider, role) =>
  status?.active_role === role &&
  status.active_key ===
    (credential?.id
      ? `credential:${credential.id}`
      : `integration:${provider}`);
