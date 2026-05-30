<script setup>
import { computed } from 'vue';
import Icon from 'next/icon/Icon.vue';
import ChannelIcon from 'next/icon/ChannelIcon.vue';
import SidebarUnreadBadge from './SidebarUnreadBadge.vue';

const props = defineProps({
  label: {
    type: String,
    required: true,
  },
  // eslint-disable-next-line vue/no-unused-properties
  active: {
    type: Boolean,
    default: false,
  },
  inbox: {
    type: Object,
    required: true,
  },
  badgeCount: {
    type: [Number, String],
    default: 0,
  },
});

const reauthorizationRequired = computed(() => {
  return props.inbox.reauthorization_required;
});
</script>

<template>
  <span class="size-4 grid place-content-center rounded-full relative">
    <ChannelIcon :inbox="inbox" class="size-4" />
    <span
      v-if="inbox.channel_type === 'Channel::Whatsmeow'"
      class="absolute bottom-[-3px] right-[-3px] w-2.5 h-2.5 rounded-full border border-white"
      :class="inbox.channel?.status === 'connected' ? 'bg-green-500' : 'bg-red-500'"
    ></span>
  </span>
  <div class="flex-1 truncate min-w-0">{{ label }}</div>
  <SidebarUnreadBadge :count="badgeCount" />
  <div
    v-if="reauthorizationRequired"
    v-tooltip.top-end="$t('SIDEBAR.REAUTHORIZE')"
    class="grid place-content-center size-5 bg-n-ruby-5/60 rounded-full"
  >
    <Icon icon="i-woot-alert" class="size-3 text-n-ruby-9" />
  </div>
</template>
