<script setup>
import { computed, toRef } from 'vue';
import { useChannelIcon, useChannelBrandIcon } from './provider';
import Icon from 'next/icon/Icon.vue';

const props = defineProps({
  inbox: {
    type: Object,
    required: true,
  },
  // When true, render the full-color brand icon (when one exists for the
  // channel type) and fall back to the monochrome glyph otherwise.
  useBrandIcon: {
    type: Boolean,
    default: false,
  },
});

defineOptions({ inheritAttrs: false });

const inboxRef = toRef(props, 'inbox');

const channelIcon = useChannelIcon(inboxRef);
const brandIcon = useChannelBrandIcon(inboxRef);

const icon = computed(() =>
  props.useBrandIcon && brandIcon.value ? brandIcon.value : channelIcon.value
);

const whatsmeowStatus = computed(
  () => props.inbox.channel?.status || props.inbox.status
);
const isWhatsmeowConnected = computed(
  () => whatsmeowStatus.value === 'connected'
);
</script>

<template>
  <span class="relative inline-flex" v-bind="$attrs">
    <Icon :icon="icon" class="size-full" />
    <span
      v-if="hasVoiceBadge"
      class="absolute top-0 ltr:right-0 rtl:left-0 inline-flex items-center justify-center size-2 rounded-full bg-n-surface-1"
    >
      <Icon icon="i-lucide-audio-lines" class="size-1.5 text-n-slate-12" />
    </span>
    <span
      v-if="inbox.channel_type === 'Channel::Whatsmeow'"
      class="absolute bottom-[-3px] right-[-3px] w-2.5 h-2.5 rounded-full border border-white flex items-center justify-center"
      :class="isWhatsmeowConnected ? 'bg-green-500' : 'bg-red-500'"
    >
      <Icon
        :icon="isWhatsmeowConnected ? 'i-lucide-check' : 'i-lucide-x'"
        class="size-[6px] text-white stroke-[3px]"
      />
    </span>
  </span>
</template>
