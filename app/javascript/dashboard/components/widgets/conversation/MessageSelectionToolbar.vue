<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import NextButton from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  selectedCount: {
    type: Number,
    required: true,
  },
  canForward: {
    type: Boolean,
    default: false,
  },
  isDeleting: {
    type: Boolean,
    default: false,
  },
  isForwarding: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['clear', 'copy', 'delete', 'forward']);
const { t, locale } = useI18n();

const isPortugueseLocale = computed(() =>
  String(locale.value || '')
    .toLowerCase()
    .startsWith('pt')
);

const selectionText = key => {
  if (isPortugueseLocale.value) {
    if (key === 'COPY') return 'Copiar';
    if (key === 'DELETE') return 'Apagar';
    if (key === 'FORWARD') return 'Encaminhar';
  }

  if (key === 'COPY') return t('CONVERSATION.MESSAGE_SELECTION.COPY');
  if (key === 'DELETE') return t('CONVERSATION.MESSAGE_SELECTION.DELETE');
  return t('CONVERSATION.MESSAGE_SELECTION.FORWARD');
};

const selectedLabel = computed(() => {
  if (isPortugueseLocale.value) {
    return props.selectedCount === 1
      ? '1 selecionada'
      : `${props.selectedCount} selecionadas`;
  }

  return t('CONVERSATION.MESSAGE_SELECTION.SELECTED_COUNT', {
    count: props.selectedCount,
  });
});
</script>

<template>
  <div
    class="absolute inset-x-0 bottom-0 z-40 flex h-16 items-center justify-between border-t border-n-weak bg-n-solid-1 px-4 shadow-lg"
  >
    <div class="flex min-w-0 items-center gap-3">
      <NextButton
        ghost
        slate
        md
        icon="i-lucide-x"
        :disabled="isDeleting || isForwarding"
        @click="emit('clear')"
      />
      <span class="truncate text-sm font-medium text-n-slate-12">
        {{ selectedLabel }}
      </span>
    </div>

    <div class="flex items-center gap-3 pr-8 sm:pr-14 lg:pr-24">
      <NextButton
        v-tooltip.top="selectionText('COPY')"
        ghost
        slate
        md
        icon="i-lucide-copy"
        :disabled="isDeleting || isForwarding"
        @click="emit('copy')"
      />
      <NextButton
        v-tooltip.top="selectionText('DELETE')"
        ghost
        slate
        md
        icon="i-lucide-trash-2"
        :is-loading="isDeleting"
        :disabled="isForwarding"
        @click="emit('delete')"
      />
      <NextButton
        v-tooltip.top="selectionText('FORWARD')"
        ghost
        slate
        md
        icon="i-lucide-forward"
        :is-loading="isForwarding"
        :disabled="!canForward || isDeleting"
        @click="emit('forward')"
      />
    </div>
  </div>
</template>
