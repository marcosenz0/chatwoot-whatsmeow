<script setup>
import { useI18n } from 'vue-i18n';

defineProps({ item: { type: Object, required: true } });
const { t } = useI18n();
</script>

<template>
  <span
    class="inline-flex min-w-0 items-center gap-1.5 rounded-md bg-n-alpha-2 px-2 py-1 text-xs text-n-slate-11"
  >
    <span
      class="size-3.5 shrink-0"
      :class="
        item.audience === 'global' || !item.audience
          ? 'i-lucide-globe'
          : 'i-lucide-lock-keyhole'
      "
    />
    {{
      t(
        `MARCOX_AI.AUDIENCE.BADGE_${(item.audience || 'global').toUpperCase()}`,
        {
          count: item.contact_ids?.length || 0,
          id: item.conversation_id,
        }
      )
    }}
  </span>
</template>
