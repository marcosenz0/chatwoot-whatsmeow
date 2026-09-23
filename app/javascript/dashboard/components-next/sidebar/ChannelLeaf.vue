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

const historyState = computed(
  () => props.inbox.history_sync_state || props.inbox.historySyncState || {}
);
const historyActive = computed(() =>
  ['syncing', 'waiting'].includes(historyState.value.phase)
);

const reauthorizationRequired = computed(() => {
  return props.inbox.reauthorization_required;
});
</script>

<template>
  <span class="size-4 grid place-content-center rounded-full relative">
    <ChannelIcon :inbox="inbox" class="size-4" />
  </span>
  <div class="flex-1 truncate min-w-0">
    <span>{{ label }}</span>
    <span
      v-if="historyActive"
      class="flex items-center gap-1 text-xs text-n-blue-11"
      role="status"
    >
      <span class="i-lucide-loader-circle size-3 animate-spin" />
      {{
        historyState.phase === 'waiting'
          ? $t('INBOX_MGMT.SETTINGS_POPUP.WHATSMEOW.HISTORY.SIDEBAR_WAITING')
          : $t('INBOX_MGMT.SETTINGS_POPUP.WHATSMEOW.HISTORY.SIDEBAR', {
              count: historyState.stored || 0,
            })
      }}
    </span>
  </div>
  <SidebarUnreadBadge :count="badgeCount" />
  <div
    v-if="reauthorizationRequired"
    v-tooltip.top-end="$t('SIDEBAR.REAUTHORIZE')"
    class="grid place-content-center size-5 bg-n-ruby-5/60 rounded-full"
  >
    <Icon icon="i-woot-alert" class="size-3 text-n-ruby-9" />
  </div>
</template>
