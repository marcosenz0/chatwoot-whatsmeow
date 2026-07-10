<script setup>
import { useI18n } from 'vue-i18n';

import Button from 'dashboard/components-next/button/Button.vue';
import ChannelIcon from 'dashboard/components-next/icon/ChannelIcon.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import DropdownBody from 'dashboard/components-next/dropdown-menu/base/DropdownBody.vue';
import DropdownContainer from 'dashboard/components-next/dropdown-menu/base/DropdownContainer.vue';
import DropdownItem from 'dashboard/components-next/dropdown-menu/base/DropdownItem.vue';
import DropdownSection from 'dashboard/components-next/dropdown-menu/base/DropdownSection.vue';

const props = defineProps({
  inboxes: {
    type: Array,
    default: () => [],
  },
  updatingInboxIds: {
    type: Array,
    default: () => [],
  },
});

const emit = defineEmits(['toggle']);

const { t } = useI18n();

const isConnected = inbox =>
  (inbox.channel?.status || inbox.status) === 'connected';
const isStatusEnabled = inbox => !inbox.ignore_status;
const isUpdating = inbox => props.updatingInboxIds.includes(inbox.id);

const toggleInbox = inbox => {
  if (isUpdating(inbox)) return;
  emit('toggle', { inbox, enabled: !isStatusEnabled(inbox) });
};
</script>

<template>
  <DropdownContainer>
    <template #trigger="{ toggle, isOpen }">
      <Button
        v-tooltip.top="t('WHATSAPP_STATUS.STATUS_SETTINGS')"
        icon="i-lucide-ellipsis-vertical"
        color="slate"
        variant="ghost"
        size="lg"
        :class="{ 'bg-n-alpha-2': isOpen }"
        :aria-label="t('WHATSAPP_STATUS.STATUS_SETTINGS')"
        @click="toggle"
      />
    </template>

    <DropdownBody
      class="right-0 top-11 z-50 w-80 max-w-[calc(100vw-2rem)] [&>ul]:max-h-96"
    >
      <DropdownSection
        :title="t('WHATSAPP_STATUS.STATUS_SETTINGS_TITLE')"
        height="max-h-80"
      >
        <DropdownItem
          v-for="inbox in inboxes"
          :key="inbox.id"
          preserve-open
          :click="() => toggleInbox(inbox)"
          role="switch"
          :aria-checked="isStatusEnabled(inbox)"
          :aria-label="
            t('WHATSAPP_STATUS.STATUS_TOGGLE_LABEL', { inbox: inbox.name })
          "
          :disabled="isUpdating(inbox)"
          class="rounded-lg hover:bg-n-alpha-2"
        >
          <div class="flex min-h-11 w-full items-center gap-3">
            <span
              class="flex size-8 flex-shrink-0 items-center justify-center rounded-lg bg-n-alpha-2 text-n-slate-11"
            >
              <ChannelIcon :inbox="inbox" use-brand-icon class="size-5" />
            </span>
            <span class="min-w-0 flex-1">
              <span class="block truncate text-sm font-medium text-n-slate-12">
                {{ inbox.name }}
              </span>
              <span class="block truncate text-xs text-n-slate-10">
                {{
                  isConnected(inbox)
                    ? t('WHATSAPP_STATUS.CONNECTED')
                    : t('WHATSAPP_STATUS.DISCONNECTED')
                }}
              </span>
            </span>

            <Icon
              v-if="isUpdating(inbox)"
              icon="i-lucide-loader-circle"
              class="size-4 flex-shrink-0 animate-spin text-n-slate-10 motion-reduce:animate-none"
            />
            <span
              v-else
              class="relative h-5 w-9 flex-shrink-0 rounded-full transition-colors duration-200 motion-reduce:transition-none"
              :class="isStatusEnabled(inbox) ? 'bg-n-brand' : 'bg-n-slate-6'"
              aria-hidden="true"
            >
              <span
                class="absolute top-0.5 size-4 rounded-full bg-white shadow-sm transition-transform duration-200 motion-reduce:transition-none ltr:left-0.5 rtl:right-0.5"
                :class="{
                  'ltr:translate-x-4 rtl:-translate-x-4':
                    isStatusEnabled(inbox),
                }"
              />
            </span>
          </div>
        </DropdownItem>
      </DropdownSection>
    </DropdownBody>
  </DropdownContainer>
</template>
