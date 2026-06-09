<script setup>
import { computed } from 'vue';
import BaseBubble from './Base.vue';
import StickerChip from '../chips/Sticker.vue';
import MessageMeta from '../MessageMeta.vue';
import { useMessageContext } from '../provider.js';

const { attachments, orientation, shouldGroupWithNext } = useMessageContext();

const attachment = computed(() => attachments.value[0]);
const shouldShowMeta = computed(() => !shouldGroupWithNext.value);
const metaClass = computed(() =>
  orientation.value === 'right' ? 'justify-end' : 'justify-start'
);
</script>

<template>
  <BaseBubble
    hide-meta
    class="bg-transparent p-0 shadow-none"
    data-bubble-name="sticker"
  >
    <StickerChip v-if="attachment" :attachment="attachment" />
    <MessageMeta
      v-if="shouldShowMeta"
      class="mt-1 px-1 text-n-slate-11"
      :class="metaClass"
    />
  </BaseBubble>
</template>
