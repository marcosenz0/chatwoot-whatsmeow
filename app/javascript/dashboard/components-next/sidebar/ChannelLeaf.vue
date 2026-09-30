<script setup>
import { computed } from 'vue';
import Icon from 'next/icon/Icon.vue';
import ChannelIcon from 'next/icon/ChannelIcon.vue';
import { getInboxIdentifier } from 'dashboard/helper/inbox';
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
const IDENTIFIER_SEPARATOR = '·';

const reauthorizationRequired = computed(
  () => props.inbox.reauthorization_required
);

const channelIdentifier = computed(() => getInboxIdentifier(props.inbox));

const rowTitle = computed(() =>
  channelIdentifier.value
    ? `${props.label} ${IDENTIFIER_SEPARATOR} ${channelIdentifier.value}`
    : props.label
);
</script>

<template>
  <span class="size-4 grid place-content-center rounded-full relative">
    <ChannelIcon :inbox="inbox" class="size-4" />
  </span>
  <div
    :title="rowTitle"
    class="flex-1 truncate min-w-0"
    data-test-id="channel-leaf-label"
  >
    {{ label }}
    <template v-if="channelIdentifier">
      <span aria-hidden="true" class="text-n-slate-9 mx-0.5">
        {{ IDENTIFIER_SEPARATOR }}
      </span>
      <bdi dir="auto" class="text-n-slate-9" data-test-id="channel-identifier">
        {{ channelIdentifier }}
      </bdi>
    </template>
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
