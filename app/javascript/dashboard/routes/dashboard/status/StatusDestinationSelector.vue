<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

import ChannelIcon from 'dashboard/components-next/icon/ChannelIcon.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import DropdownBody from 'dashboard/components-next/dropdown-menu/base/DropdownBody.vue';
import DropdownContainer from 'dashboard/components-next/dropdown-menu/base/DropdownContainer.vue';
import DropdownItem from 'dashboard/components-next/dropdown-menu/base/DropdownItem.vue';
import DropdownSection from 'dashboard/components-next/dropdown-menu/base/DropdownSection.vue';
import DropdownSeparator from 'dashboard/components-next/dropdown-menu/base/DropdownSeparator.vue';

const props = defineProps({
  modelValue: {
    type: Array,
    default: () => [],
  },
  inboxes: {
    type: Array,
    default: () => [],
  },
});

const emit = defineEmits(['update:modelValue']);

const { t } = useI18n();

const isConnected = inbox =>
  (inbox.channel?.status || inbox.status) === 'connected';

const connectedInboxes = computed(() => props.inboxes.filter(isConnected));
const selectedIds = computed(() => props.modelValue.map(Number));
const selectedInboxes = computed(() =>
  connectedInboxes.value.filter(inbox => selectedIds.value.includes(inbox.id))
);
const allConnectedSelected = computed(
  () =>
    connectedInboxes.value.length > 0 &&
    selectedInboxes.value.length === connectedInboxes.value.length
);

const summaryLabel = computed(() => {
  if (!selectedInboxes.value.length) {
    return t('WHATSAPP_STATUS.COMPOSER.SELECT_DESTINATIONS');
  }
  if (allConnectedSelected.value) {
    return t('WHATSAPP_STATUS.COMPOSER.ALL_CONNECTED_INBOXES');
  }
  if (selectedInboxes.value.length === 1) {
    return selectedInboxes.value[0].name;
  }
  return t('WHATSAPP_STATUS.COMPOSER.SELECTED_INBOXES', {
    count: selectedInboxes.value.length,
  });
});

const emitSelection = ids => emit('update:modelValue', ids.map(Number));

const toggleAll = () => {
  emitSelection(
    allConnectedSelected.value
      ? []
      : connectedInboxes.value.map(inbox => inbox.id)
  );
};

const toggleInbox = inbox => {
  if (!isConnected(inbox)) return;

  const nextIds = new Set(selectedIds.value);
  if (nextIds.has(inbox.id)) nextIds.delete(inbox.id);
  else nextIds.add(inbox.id);
  emitSelection(Array.from(nextIds));
};
</script>

<template>
  <div class="flex flex-col gap-2">
    <span class="text-sm font-medium text-n-slate-12">
      {{ t('WHATSAPP_STATUS.COMPOSER.PUBLISH_TO') }}
    </span>

    <DropdownContainer class="w-full !space-y-0 [&>div]:w-full">
      <template #trigger="{ toggle, isOpen }">
        <button
          type="button"
          class="reset-base flex min-h-11 w-full items-center gap-3 rounded-lg border border-n-weak bg-n-alpha-black2 px-3 text-left outline-none transition-colors hover:bg-n-alpha-1 focus-visible:border-n-brand focus-visible:ring-1 focus-visible:ring-n-brand"
          :class="{ 'border-n-brand bg-n-alpha-1': isOpen }"
          :aria-expanded="isOpen"
          aria-haspopup="listbox"
          @click="toggle"
        >
          <span
            class="flex size-7 flex-shrink-0 items-center justify-center rounded-lg bg-n-alpha-2 text-n-slate-11"
          >
            <Icon icon="i-lucide-send" class="size-3.5" />
          </span>
          <span class="min-w-0 flex-1 truncate text-sm text-n-slate-12">
            {{ summaryLabel }}
          </span>
          <span class="text-xs tabular-nums text-n-slate-10">
            {{
              t('WHATSAPP_STATUS.COMPOSER.DESTINATION_COUNT', {
                selected: selectedInboxes.length,
                total: connectedInboxes.length,
              })
            }}
          </span>
          <Icon
            icon="i-lucide-chevron-down"
            class="size-4 flex-shrink-0 text-n-slate-10 transition-transform duration-200 motion-reduce:transition-none"
            :class="{ 'rotate-180': isOpen }"
          />
        </button>
      </template>

      <DropdownBody
        class="left-0 top-0 z-[60] w-full min-w-[20rem] max-w-[calc(100vw-3rem)] [&>ul]:!bg-n-solid-2 [&>ul]:!backdrop-blur-none"
      >
        <DropdownSection height="max-h-72">
          <DropdownItem
            type="button"
            preserve-open
            :click="toggleAll"
            role="checkbox"
            :aria-checked="allConnectedSelected"
            :disabled="!connectedInboxes.length"
            class="rounded-lg hover:bg-n-alpha-2"
          >
            <div class="flex min-h-10 w-full items-center gap-3">
              <span
                class="flex size-8 flex-shrink-0 items-center justify-center rounded-lg bg-n-alpha-2 text-n-slate-11"
              >
                <Icon icon="i-lucide-layers-3" class="size-4" />
              </span>
              <span class="min-w-0 flex-1">
                <span
                  class="block truncate text-sm font-medium text-n-slate-12"
                >
                  {{ t('WHATSAPP_STATUS.COMPOSER.ALL_CONNECTED_INBOXES') }}
                </span>
                <span class="block truncate text-xs text-n-slate-10">
                  {{
                    t('WHATSAPP_STATUS.COMPOSER.CONNECTED_DESTINATIONS', {
                      count: connectedInboxes.length,
                    })
                  }}
                </span>
              </span>
              <span
                class="flex size-5 flex-shrink-0 items-center justify-center rounded border"
                :class="
                  allConnectedSelected
                    ? 'border-n-brand bg-n-brand text-white'
                    : 'border-n-strong text-transparent'
                "
                aria-hidden="true"
              >
                <Icon icon="i-lucide-check" class="size-3.5" />
              </span>
            </div>
          </DropdownItem>

          <DropdownSeparator />

          <DropdownItem
            v-for="inbox in inboxes"
            :key="inbox.id"
            type="button"
            preserve-open
            :click="() => toggleInbox(inbox)"
            role="checkbox"
            :aria-checked="selectedIds.includes(inbox.id)"
            :disabled="!isConnected(inbox)"
            class="rounded-lg hover:bg-n-alpha-2"
          >
            <div class="flex min-h-10 w-full items-center gap-3">
              <span
                class="flex size-8 flex-shrink-0 items-center justify-center text-n-slate-11"
              >
                <ChannelIcon :inbox="inbox" class="size-5" />
              </span>
              <span class="min-w-0 flex-1">
                <span
                  class="block truncate text-sm font-medium text-n-slate-12"
                >
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
              <span
                class="flex size-5 flex-shrink-0 items-center justify-center rounded border"
                :class="
                  selectedIds.includes(inbox.id)
                    ? 'border-n-brand bg-n-brand text-white'
                    : 'border-n-strong text-transparent'
                "
                aria-hidden="true"
              >
                <Icon icon="i-lucide-check" class="size-3.5" />
              </span>
            </div>
          </DropdownItem>
        </DropdownSection>
      </DropdownBody>
    </DropdownContainer>

    <p
      v-if="!connectedInboxes.length"
      class="mb-0 text-xs leading-5 text-n-ruby-11"
      role="status"
    >
      {{ t('WHATSAPP_STATUS.COMPOSER.NO_CONNECTED_INBOXES') }}
    </p>
  </div>
</template>
