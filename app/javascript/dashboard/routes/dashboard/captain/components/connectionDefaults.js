export const fallbackDefaults = {
  enabled: false,
  retry_primary: true,
  provider: 'openai',
  connection_id: null,
  max_output_tokens: null,
  reasoning_effort: null,
  retry_rate_limits: true,
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

export const invertConnections = (primary, fallback, inherited = {}) => {
  const fields = [
    'provider',
    'model',
    'connection_id',
    'max_output_tokens',
    'reasoning_effort',
    'retry_rate_limits',
  ];
  const defaults = {
    retry_rate_limits: true,
    reasoning_effort:
      inherited.reasoning_effort || primary.reasoning_effort || 'medium',
  };
  const route = source =>
    Object.fromEntries(
      fields.map(field => [field, source[field] ?? defaults[field] ?? null])
    );
  const previous = route(primary.provider === 'agent' ? inherited : primary);
  const next = route(fallback);
  Object.assign(primary, next);
  Object.assign(fallback, previous);
};
