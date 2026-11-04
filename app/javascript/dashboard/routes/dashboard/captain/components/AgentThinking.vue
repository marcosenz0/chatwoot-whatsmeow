<script setup>
import { computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import AiSelect from './AiSelect.vue';

const props = defineProps({
  model: { type: Object, default: null },
  disabled: { type: Boolean, default: false },
  inheritedEffort: { type: String, default: 'medium' },
});
const effort = defineModel({ type: String, default: null });
const { t } = useI18n();
const levels = computed(() => props.model?.reasoning_levels || []);
const selected = computed(() => {
  const value = effort.value || props.inheritedEffort;
  return levels.value.includes(value)
    ? value
    : props.model?.reasoning_default || levels.value[0];
});
// Preserve a draft while the catalog loads; normalize unsupported levels only
// once the selected model's documented capabilities are available.
watch(
  () => [props.model?.id, props.model?.reasoning_levels, effort.value],
  () => {
    if (
      effort.value &&
      levels.value.length &&
      !levels.value.includes(effort.value)
    )
      effort.value = selected.value;
  }
);
</script>

<template>
  <div data-thinking-control class="space-y-2">
    <label
      v-if="levels.length"
      class="block text-sm font-medium text-n-slate-12"
    >
      <span class="flex items-center gap-2">
        <span class="i-lucide-brain size-4 shrink-0 text-n-slate-11" />
        {{ t('MARCOX_AI.THINKING.TITLE') }}
      </span>
      <AiSelect
        :model-value="selected"
        :options="
          levels.map(value => ({
            value,
            label: t(`MARCOX_AI.THINKING.LEVELS.${value.toUpperCase()}`),
          }))
        "
        :label="t('MARCOX_AI.THINKING.TITLE')"
        :disabled="disabled"
        class="mt-2"
        @update:model-value="effort = $event"
      />
    </label>
    <p
      v-if="!levels.length"
      role="status"
      class="m-0 flex items-center gap-2 text-sm text-n-slate-11"
    >
      <span class="i-lucide-brain size-4 shrink-0" />
      {{
        t(
          model?.reasoning === false
            ? 'MARCOX_AI.THINKING.UNSUPPORTED'
            : 'MARCOX_AI.THINKING.UNKNOWN'
        )
      }}
    </p>
    <p v-else class="m-0 text-xs leading-5 text-n-slate-11">
      {{
        t(
          levels.includes('none')
            ? 'MARCOX_AI.THINKING.HINT'
            : 'MARCOX_AI.THINKING.REQUIRED'
        )
      }}
    </p>
  </div>
</template>
