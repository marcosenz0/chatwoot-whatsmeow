<script setup>
import { useI18n } from 'vue-i18n';
import AiToggleRow from './AiToggleRow.vue';

defineProps({ disabled: { type: Boolean, default: false } });
const enabled = defineModel({ type: Boolean, default: true });
const { t } = useI18n();
</script>

<template>
  <AiToggleRow
    v-model="enabled"
    :label="t('MARCOX_AI.RATE_RETRY.TITLE')"
    :description="t('MARCOX_AI.RATE_RETRY.HINT')"
    :disabled="disabled"
  />
</template>
