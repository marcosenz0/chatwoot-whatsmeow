<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

import ChannelIcon from 'dashboard/components-next/icon/ChannelIcon.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import DropdownBody from 'dashboard/components-next/dropdown-menu/base/DropdownBody.vue';
import DropdownContainer from 'dashboard/components-next/dropdown-menu/base/DropdownContainer.vue';
import DropdownItem from 'dashboard/components-next/dropdown-menu/base/DropdownItem.vue';
import DropdownSection from 'dashboard/components-next/dropdown-menu/base/DropdownSection.vue';

const props = defineProps({
  modelValue: {
    type: [String, Number],
    default: 'all',
  },
  inboxes: {
    type: Array,
    default: () => [],
  },
});

const emit = defineEmits(['update:modelValue']);

const { t } = useI18n();

const selectedValue = computed(() => String(props.modelValue));
const selectedInbox = computed(() =>
  props.inboxes.find(inbox => String(inbox.id) === selectedValue.value)
);
const isAllSelected = computed(() => selectedValue.value === 'all');

const isConnected = inbox =>
  (inbox.channel?.status || inbox.status) === 'connected';

const connectedCount = computed(() => props.inboxes.filter(isConnected).length);

const selectedLabel = computed(() =>
  isAllSelected.value
    ? t('WHATSAPP_STATUS.ALL_INBOXES')
    : selectedInbox.value?.name || ''
);

const selectedDescription = computed(() => {
  if (isAllSelected.value) {
    return t('WHATSAPP_STATUS.CONNECTED_COUNT', {
      connected: connectedCount.value,
      total: props.inboxes.length,
    });
  }

  return isConnected(selectedInbox.value || {})
    ? t('WHATSAPP_STATUS.CONNECTED')
    : t('WHATSAPP_STATUS.DISCONNECTED');
});

const selectInbox = value => emit('update:modelValue', String(value));
</script>

<template>
  <DropdownContainer class="w-full [&>div]:w-full">
    <template #trigger="{ toggle, isOpen }">
      <button
        type="button"
        class="reset-base flex min-h-12 w-full items-center gap-3 rounded-xl border border-n-weak bg-n-alpha-black2 px-3 text-left outline-none transition-colors hover:bg-n-alpha-1 focus-visible:border-n-brand focus-visible:ring-1 focus-visible:ring-n-brand"
        :class="{ 'border-n-brand bg-n-alpha-1': isOpen }"
        :aria-expanded="isOpen"
        aria-haspopup="listbox"
        @click="toggle"
      >
        <span
          v-if="isAllSelected"
          class="flex size-8 flex-shrink-0 items-center justify-center rounded-lg bg-n-alpha-2 text-n-slate-11"
        >
          <Icon icon="i-lucide-layers-3" class="size-4" />
        </span>
        <span
          v-else-if="selectedInbox"
          class="flex size-8 flex-shrink-0 items-center justify-center rounded-lg bg-n-alpha-2 text-n-slate-11"
        >
          <ChannelIcon :inbox="selectedInbox" use-brand-icon class="size-5" />
        </span>

        <span class="min-w-0 flex-1">
          <span class="block truncate text-sm font-medium text-n-slate-12">
            {{ selectedLabel }}
          </span>
          <span class="mt-0.5 block truncate text-xs text-n-slate-10">
            {{ selectedDescription }}
          </span>
        </span>

        <Icon
          icon="i-lucide-chevron-down"
          class="size-4 flex-shrink-0 text-n-slate-10 transition-transform duration-200 motion-reduce:transition-none"
          :class="{ 'rotate-180': isOpen }"
        />
      </button>
    </template>

    <DropdownBody
      class="left-0 top-[3.25rem] z-50 w-full min-w-[20rem] max-w-[calc(100vw-2rem)] [&>ul]:max-h-80 [&>ul]:overflow-x-hidden [&>ul]:overflow-y-auto"
    >
      <DropdownSection>
        <DropdownItem
          :click="() => selectInbox('all')"
          role="option"
          :aria-selected="isAllSelected"
          :class="{ 'rounded-lg bg-n-alpha-2': isAllSelected }"
        >
          <div class="flex min-h-10 w-full items-center gap-3">
            <span
              class="flex size-8 flex-shrink-0 items-center justify-center rounded-lg bg-n-alpha-2 text-n-slate-11"
            >
              <Icon icon="i-lucide-layers-3" class="size-4" />
            </span>
            <span class="min-w-0 flex-1">
              <span class="block truncate text-sm font-medium text-n-slate-12">
                {{ t('WHATSAPP_STATUS.ALL_INBOXES') }}
              </span>
              <span class="block truncate text-xs text-n-slate-10">
                {{
                  t('WHATSAPP_STATUS.CONNECTED_COUNT', {
                    connected: connectedCount,
                    total: inboxes.length,
                  })
                }}
              </span>
            </span>
            <Icon
              v-if="isAllSelected"
              icon="i-lucide-check"
              class="size-4 flex-shrink-0 text-n-brand"
            />
          </div>
        </DropdownItem>

        <DropdownItem
          v-for="inbox in inboxes"
          :key="inbox.id"
          :click="() => selectInbox(inbox.id)"
          role="option"
          :aria-selected="selectedValue === String(inbox.id)"
          :class="{
            'rounded-lg bg-n-alpha-2': selectedValue === String(inbox.id),
          }"
        >
          <div class="flex min-h-10 w-full items-center gap-3">
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
              v-if="selectedValue === String(inbox.id)"
              icon="i-lucide-check"
              class="size-4 flex-shrink-0 text-n-brand"
            />
          </div>
        </DropdownItem>
      </DropdownSection>
    </DropdownBody>
  </DropdownContainer>
</template>
