<script setup>
import ChannelIcon from 'dashboard/components-next/icon/ChannelIcon.vue';

defineProps({
  inbox: {
    type: Object,
    default: () => {},
  },
});
</script>

<template>
  <div :title="inbox.name" class="flex items-center gap-0.5 min-w-0">
    <div class="relative flex items-center">
      <ChannelIcon :inbox="inbox" class="size-4 flex-shrink-0 text-n-slate-11" />
      <span
        v-if="inbox.channel_type === 'Channel::Whatsmeow'"
        class="absolute bottom-[-2px] right-[-2px] w-2 h-2 rounded-full border border-white"
        :class="inbox.channel?.status === 'connected' ? 'bg-green-500' : 'bg-red-500'"
      ></span>
    </div>
    <span class="truncate text-label-small text-n-slate-11">
      {{ inbox.name }}
    </span>
  </div>
</template>
