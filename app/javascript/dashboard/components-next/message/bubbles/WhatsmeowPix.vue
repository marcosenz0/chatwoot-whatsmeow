<script setup>
import { computed } from 'vue';
import { useMessageContext } from '../provider.js';
import BaseBubble from './Base.vue';
import MessageMeta from '../MessageMeta.vue';
import WhatsmeowPixCard from '../WhatsmeowPixCard.vue';

const { contentAttributes } = useMessageContext();

const pix = computed(
  () =>
    contentAttributes.value?.whatsmeowPix ||
    contentAttributes.value?.whatsmeow_pix ||
    {}
);
</script>

<template>
  <BaseBubble
    hide-meta
    class="w-80 max-w-[min(20rem,calc(100vw-5rem))] overflow-hidden"
    data-bubble-name="whatsmeow-pix"
  >
    <WhatsmeowPixCard :pix="pix" />
    <div class="flex px-3 pb-2 pt-1">
      <MessageMeta class="text-n-slate-11" />
    </div>
  </BaseBubble>
</template>
