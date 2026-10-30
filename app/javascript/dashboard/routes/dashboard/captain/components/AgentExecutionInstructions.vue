<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import API from 'dashboard/api/marcosxAi';
import AiSelect from './AiSelect.vue';
import AgentSection from './AgentSection.vue';

const props = defineProps({
  assistant: { type: Object, required: true },
  canEdit: { type: Boolean, default: false },
});
const rules = defineModel({ type: Object, required: true });
const presets = defineModel('presets', { type: Array, required: true });
const presetId = defineModel('presetId', { type: String, required: true });
const { t } = useI18n();
const defaults = ref({});
const placeholders = ref([]);
const loading = ref(false);
const error = ref('');
const name = ref('');
const fields = [
  { key: 'platform', id: 'ai-platform-prompt', limit: 30000, rows: 16 },
  {
    key: 'current_request',
    id: 'ai-current-request-prompt',
    limit: 8000,
    rows: 5,
  },
  { key: 'memory', id: 'ai-memory-prompt', limit: 8000, rows: 5 },
];
const resolved = key => rules.value[key] ?? defaults.value[key] ?? '';
const snapshot = () =>
  Object.fromEntries(fields.map(({ key }) => [key, resolved(key)]));
const options = computed(() => [
  {
    value: 'system',
    label: t('MARCOX_AI.PROMPT_RULES.SYSTEM'),
    icon: 'i-lucide-shield-check',
  },
  ...(presetId.value === 'custom'
    ? [
        {
          value: 'custom',
          label: t('MARCOX_AI.PROMPT_RULES.CUSTOM'),
          icon: 'i-lucide-pencil',
        },
      ]
    : []),
  ...presets.value.map(preset => ({
    value: preset.id,
    label: preset.name,
    icon: 'i-lucide-notebook-text',
  })),
]);
const selected = computed(() =>
  presets.value.find(preset => preset.id === presetId.value)
);
const loadDefaults = async () => {
  loading.value = true;
  error.value = '';
  try {
    const assistant = {
      ...props.assistant,
      config: {
        ...props.assistant.config,
        prompt_rules: { platform: null, current_request: null, memory: null },
        prompt_presets: [],
        prompt_preset_id: 'system',
      },
    };
    const { data } = await API.getEffectivePrompt(
      props.assistant.id,
      assistant
    );
    defaults.value = data.rules_defaults || {};
    placeholders.value = data.placeholders || [];
  } catch (e) {
    error.value = e.response?.data?.error || t('MARCOX_AI.CONVERSATION.ERROR');
  } finally {
    loading.value = false;
  }
};
const choose = id => {
  if (id === 'system')
    rules.value = Object.fromEntries(fields.map(({ key }) => [key, null]));
  else if (id !== 'custom')
    rules.value = { ...presets.value.find(preset => preset.id === id).rules };
  presetId.value = id;
};
const restore = async () => {
  await loadDefaults();
  if (!error.value) choose('system');
};
const updateField = (key, value) => {
  rules.value = { ...rules.value, [key]: value };
  if (presetId.value === 'system') presetId.value = 'custom';
};
const add = () => {
  if (!name.value.trim() || presets.value.length >= 20) return;
  const preset = {
    id: crypto.randomUUID(),
    name: name.value.trim(),
    rules: snapshot(),
  };
  presets.value = [...presets.value, preset];
  presetId.value = preset.id;
  name.value = '';
};
const update = () => {
  presets.value = presets.value.map(preset =>
    preset.id === presetId.value
      ? { ...preset, rules: snapshot(), name: name.value.trim() || preset.name }
      : preset
  );
  name.value = '';
};
const remove = () => {
  presets.value = presets.value.filter(preset => preset.id !== presetId.value);
  presetId.value = 'custom';
};
const formatPlaceholder = placeholder => `{{${placeholder}}}`;
onMounted(loadDefaults);
</script>

<template>
  <AgentSection
    :title="t('MARCOX_AI.PROMPT_RULES.TITLE')"
    icon="i-lucide-sliders-horizontal"
  >
    <p class="m-0 text-sm leading-6 text-n-slate-11">
      {{ t('MARCOX_AI.PROMPT_RULES.HINT') }}
    </p>
    <p v-if="error" role="alert" class="text-sm text-n-ruby-11">{{ error }}</p>
    <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
      <label class="min-w-0 text-sm font-medium">
        {{ t('MARCOX_AI.PROMPT_RULES.PRESET') }}
        <AiSelect
          :model-value="presetId"
          :options="options"
          :label="t('MARCOX_AI.PROMPT_RULES.PRESET')"
          :disabled="!canEdit || loading"
          class="mt-2"
          @update:model-value="choose"
        />
      </label>
      <div class="flex flex-wrap items-end gap-2">
        <Button
          type="button"
          variant="outline"
          color="slate"
          icon="i-lucide-rotate-ccw"
          :label="t('MARCOX_AI.PROMPT_RULES.RESTORE')"
          :disabled="!canEdit || loading"
          @click="restore"
        />
        <Button
          v-if="error"
          type="button"
          variant="link"
          :label="t('MARCOX_AI.CONVERSATION.RETRY')"
          @click="loadDefaults"
        />
      </div>
    </div>
    <div class="flex flex-wrap items-end gap-2 border-b border-n-weak pb-4">
      <label class="min-w-0 flex-1 text-sm font-medium">
        {{ t('MARCOX_AI.PROMPT_RULES.NAME') }}
        <input
          v-model="name"
          maxlength="80"
          class="reset-base !mb-0 mt-2 h-10 w-full rounded-lg border border-n-weak bg-n-background px-3 text-sm"
          :disabled="!canEdit || loading"
          @keydown.enter.prevent="add"
        />
      </label>
      <Button
        type="button"
        icon="i-lucide-plus"
        :label="t('MARCOX_AI.PROMPT_RULES.ADD')"
        :disabled="!canEdit || loading || !name.trim() || presets.length >= 20"
        @click="add"
      />
      <Button
        v-if="selected"
        type="button"
        variant="outline"
        color="slate"
        :label="t('MARCOX_AI.PROMPT_RULES.UPDATE')"
        :disabled="!canEdit || loading"
        @click="update"
      />
      <Button
        v-if="selected"
        type="button"
        variant="ghost"
        color="ruby"
        icon="i-lucide-trash-2"
        :label="t('MARCOX_AI.PROMPT_RULES.DELETE')"
        :disabled="!canEdit || loading"
        @click="remove"
      />
    </div>
    <p class="m-0 text-xs leading-5 text-n-slate-11">
      {{ t('MARCOX_AI.PROMPT_RULES.SAVE_HINT') }}
    </p>
    <div v-for="field in fields" :key="field.key" class="space-y-2">
      <label :for="field.id" class="text-sm font-semibold">{{
        t(`MARCOX_AI.PROMPT_RULES.FIELDS.${field.key.toUpperCase()}`)
      }}</label>
      <textarea
        :id="field.id"
        :value="resolved(field.key)"
        :rows="field.rows"
        :maxlength="field.limit"
        :disabled="!canEdit || loading || !defaults.platform"
        class="reset-base !mb-0 w-full rounded-xl border border-n-weak bg-n-background p-3 font-mono text-xs leading-5"
        @input="updateField(field.key, $event.target.value)"
      />
      <p class="m-0 text-xs text-n-slate-10">
        {{
          t('MARCOX_AI.PROMPT_RULES.CHARACTERS', {
            count: resolved(field.key).length,
          })
        }}
      </p>
    </div>
    <details class="border-t border-n-weak pt-3">
      <summary class="cursor-pointer text-sm font-medium">
        {{ t('MARCOX_AI.PROMPT_RULES.PLACEHOLDERS') }}
      </summary>
      <p class="text-xs leading-5 text-n-slate-11">
        {{ t('MARCOX_AI.PROMPT_RULES.PLACEHOLDERS_HINT') }}
      </p>
      <div class="flex flex-wrap gap-2">
        <code
          v-for="placeholder in placeholders"
          :key="placeholder"
          class="break-all rounded bg-n-alpha-2 px-2 py-1 text-xs"
          >{{ formatPlaceholder(placeholder) }}</code
        >
      </div>
    </details>
  </AgentSection>
</template>
