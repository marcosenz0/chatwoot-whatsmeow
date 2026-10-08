<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import AiSelect from './AiSelect.vue';

const props = defineProps({
  modelValue: { type: String, default: '' },
  models: { type: Array, default: () => [] },
  disabled: { type: Boolean, default: false },
});
const emit = defineEmits(['update:modelValue']);
const { t } = useI18n();
const options = computed(() => {
  if (
    !props.modelValue ||
    props.models.some(model => model.id === props.modelValue)
  )
    return props.models;
  return [{ id: props.modelValue, name: props.modelValue }, ...props.models];
});
</script>

<template>
  <AiSelect
    :model-value="modelValue"
    :disabled="disabled"
    :label="t('MARCOX_AI.EDITOR.MODEL')"
    searchable
    :options="
      options.map(model => ({
        value: model.id,
        label: model.name,
        description: model.recommended
          ? t('MARCOX_AI.PROVIDERS.RECOMMENDED')
          : model.id,
        icon: model.vision ? 'i-lucide-scan-eye' : 'i-lucide-brain',
      }))
    "
    @update:model-value="emit('update:modelValue', $event)"
  />
</template>
