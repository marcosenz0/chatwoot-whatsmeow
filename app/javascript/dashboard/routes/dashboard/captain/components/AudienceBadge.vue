<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  item: { type: Object, required: true },
  iconOnly: { type: Boolean, default: false },
});
const { t } = useI18n();
const label = computed(() =>
  t(
    `MARCOX_AI.AUDIENCE.BADGE_${(props.item.audience || 'global').toUpperCase()}`,
    {
      count: props.item.contact_ids?.length || 0,
      id: props.item.conversation_id,
    }
  )
);
</script>

<template>
  <span
    class="inline-flex min-w-0 items-center rounded-md text-xs"
    :class="
      iconOnly
        ? 'bg-n-solid-2 p-1 text-n-blue-11 shadow-sm'
        : 'gap-1.5 bg-n-alpha-2 px-2 py-1 text-n-slate-11'
    "
    :title="label"
    :aria-label="iconOnly ? label : undefined"
  >
    <span
      class="size-3.5 shrink-0"
      :class="
        item.audience === 'global' || !item.audience
          ? 'i-lucide-globe'
          : 'i-lucide-lock-keyhole'
      "
    />
    <span v-if="!iconOnly">{{ label }}</span>
  </span>
</template>
