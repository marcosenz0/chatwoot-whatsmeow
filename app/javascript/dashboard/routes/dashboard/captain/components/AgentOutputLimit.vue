<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  provider: { type: String, required: true },
  disabled: { type: Boolean, default: false },
});
const value = defineModel({ type: Number, default: null });
const { t } = useI18n();
const limit = computed({
  get: () =>
    value.value ?? { groq: 768, openai: 8000, gemini: 8192 }[props.provider],
  set: next => {
    value.value = next === '' ? null : Number(next);
  },
});
</script>

<template>
  <label class="block text-sm font-medium">
    {{ t('MARCOX_AI.OUTPUT_LIMIT.TITLE') }}
    <input
      v-model.number="limit"
      type="number"
      min="128"
      max="32768"
      step="1"
      :disabled="disabled"
      class="reset-base !mb-0 mt-2 h-10 w-full rounded-lg border border-n-weak bg-n-solid-1 px-3 text-sm"
    />
    <span class="mt-2 block text-xs font-normal leading-5 text-n-slate-11">
      {{
        t(
          provider === 'groq'
            ? 'MARCOX_AI.OUTPUT_LIMIT.GROQ_HINT'
            : 'MARCOX_AI.OUTPUT_LIMIT.HINT'
        )
      }}
    </span>
  </label>
</template>
