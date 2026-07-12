<script setup>
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';

import Button from 'dashboard/components-next/button/Button.vue';
import ChannelIcon from 'dashboard/components-next/icon/ChannelIcon.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import DropdownBody from 'dashboard/components-next/dropdown-menu/base/DropdownBody.vue';
import DropdownContainer from 'dashboard/components-next/dropdown-menu/base/DropdownContainer.vue';
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

const emit = defineEmits(['toggle', 'toggleViews']);

const { t } = useI18n();
const expandedInboxId = ref(null);

const isConnected = inbox =>
  (inbox.channel?.status || inbox.status) === 'connected';
const isStatusEnabled = inbox => !inbox.ignore_status;
const isStatusViewsEnabled = inbox =>
  !(inbox.channel?.hide_status_views ?? inbox.hide_status_views);
const isUpdating = inbox => props.updatingInboxIds.includes(inbox.id);
const isExpanded = inbox => expandedInboxId.value === inbox.id;

const toggleExpanded = inbox => {
  expandedInboxId.value = isExpanded(inbox) ? null : inbox.id;
};

const toggleInbox = inbox => {
  if (isUpdating(inbox)) return;
  emit('toggle', { inbox, enabled: !isStatusEnabled(inbox) });
};

const toggleStatusViews = inbox => {
  if (isUpdating(inbox)) return;
  emit('toggleViews', { inbox, enabled: !isStatusViewsEnabled(inbox) });
};
</script>

<template>
  <DropdownContainer class="!space-y-0">
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
      class="right-0 top-0 z-[60] w-[22rem] max-w-[calc(100vw-2rem)] [&>ul]:!overflow-hidden [&>ul]:!bg-n-solid-2 [&>ul]:!backdrop-blur-none"
    >
      <DropdownSection
        :title="t('WHATSAPP_STATUS.STATUS_SETTINGS_TITLE')"
        height="max-h-[min(34rem,calc(100dvh-8rem))]"
      >
        <li
          v-for="inbox in inboxes"
          :key="inbox.id"
          class="overflow-hidden rounded-xl border border-n-weak bg-n-alpha-1"
        >
          <button
            type="button"
            class="reset-base flex min-h-14 w-full items-center gap-3 px-3 py-2 text-left transition-colors hover:bg-n-alpha-2 focus-visible:outline focus-visible:outline-2 focus-visible:-outline-offset-2 focus-visible:outline-n-brand"
            :aria-expanded="isExpanded(inbox)"
            :aria-controls="`status-inbox-settings-${inbox.id}`"
            @click="toggleExpanded(inbox)"
          >
            <span
              class="flex size-9 flex-shrink-0 items-center justify-center rounded-lg bg-n-alpha-2 text-n-slate-11"
            >
              <ChannelIcon :inbox="inbox" class="size-5" />
            </span>
            <span class="min-w-0 flex-1">
              <span
                class="block truncate text-sm font-semibold text-n-slate-12"
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
              class="size-2 flex-shrink-0 rounded-full"
              :class="isStatusEnabled(inbox) ? 'bg-n-teal-9' : 'bg-n-slate-7'"
              aria-hidden="true"
            />
            <Icon
              icon="i-lucide-chevron-down"
              class="size-4 flex-shrink-0 text-n-slate-10 transition-transform duration-200 motion-reduce:transition-none"
              :class="{ 'rotate-180': isExpanded(inbox) }"
            />
          </button>

          <div
            v-if="isExpanded(inbox)"
            :id="`status-inbox-settings-${inbox.id}`"
            class="border-t border-n-weak bg-n-alpha-black2 p-2"
          >
            <button
              type="button"
              role="switch"
              class="reset-base flex min-h-12 w-full items-center gap-3 rounded-lg px-2 py-2 text-left transition-colors hover:bg-n-alpha-2 focus-visible:outline focus-visible:outline-2 focus-visible:-outline-offset-2 focus-visible:outline-n-brand disabled:cursor-not-allowed disabled:opacity-60"
              :aria-checked="isStatusEnabled(inbox)"
              :aria-label="
                t('WHATSAPP_STATUS.STATUS_TOGGLE_LABEL', { inbox: inbox.name })
              "
              :disabled="isUpdating(inbox)"
              @click="toggleInbox(inbox)"
            >
              <span
                class="flex size-8 flex-shrink-0 items-center justify-center rounded-lg bg-n-alpha-2 text-n-slate-11"
              >
                <Icon icon="i-lucide-circle-dashed" class="size-4" />
              </span>
              <span class="min-w-0 flex-1">
                <span
                  class="block truncate text-sm font-medium text-n-slate-12"
                >
                  {{ t('WHATSAPP_STATUS.TITLE') }}
                </span>
                <span class="block truncate text-xs text-n-slate-10">
                  {{
                    isStatusEnabled(inbox)
                      ? t('WHATSAPP_STATUS.STATUS_ENABLED', {
                          inbox: inbox.name,
                        })
                      : t('WHATSAPP_STATUS.STATUS_DISABLED', {
                          inbox: inbox.name,
                        })
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
            </button>

            <button
              type="button"
              role="switch"
              class="reset-base mt-1 flex min-h-12 w-full items-center gap-3 rounded-lg px-2 py-2 text-left transition-colors hover:bg-n-alpha-2 focus-visible:outline focus-visible:outline-2 focus-visible:-outline-offset-2 focus-visible:outline-n-brand disabled:cursor-not-allowed disabled:opacity-60"
              :aria-checked="isStatusViewsEnabled(inbox)"
              :aria-label="
                t('WHATSAPP_STATUS.STATUS_VIEWS_TOGGLE_LABEL', {
                  inbox: inbox.name,
                })
              "
              :disabled="isUpdating(inbox)"
              @click="toggleStatusViews(inbox)"
            >
              <span
                class="flex size-8 flex-shrink-0 items-center justify-center rounded-lg bg-n-alpha-2 text-n-slate-11"
              >
                <Icon icon="i-lucide-eye" class="size-4" />
              </span>
              <span class="min-w-0 flex-1">
                <span
                  class="block truncate text-sm font-medium text-n-slate-12"
                >
                  {{
                    t('WHATSAPP_STATUS.STATUS_VIEWS_TOGGLE_LABEL', {
                      inbox: inbox.name,
                    })
                  }}
                </span>
                <span class="block truncate text-xs text-n-slate-10">
                  {{
                    isStatusViewsEnabled(inbox)
                      ? t('WHATSAPP_STATUS.STATUS_VIEWS_ACTIVE')
                      : t('WHATSAPP_STATUS.STATUS_VIEWS_HIDDEN')
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
                :class="
                  isStatusViewsEnabled(inbox) ? 'bg-n-brand' : 'bg-n-slate-6'
                "
                aria-hidden="true"
              >
                <span
                  class="absolute top-0.5 size-4 rounded-full bg-white shadow-sm transition-transform duration-200 motion-reduce:transition-none ltr:left-0.5 rtl:right-0.5"
                  :class="{
                    'ltr:translate-x-4 rtl:-translate-x-4':
                      isStatusViewsEnabled(inbox),
                  }"
                />
              </span>
            </button>
          </div>
        </li>
      </DropdownSection>
    </DropdownBody>
  </DropdownContainer>
</template>
