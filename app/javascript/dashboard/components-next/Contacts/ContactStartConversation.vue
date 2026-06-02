<script setup>
import { computed, ref } from 'vue';
import { useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import ConversationAPI from 'dashboard/api/conversations';
import {
  buildContactableInboxesList,
  fetchContactableInboxes,
  mergeInboxDetails,
} from 'dashboard/components-next/NewConversation/helpers/composeConversationHelper';

import Popover from 'dashboard/components-next/popover/Popover.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';

const props = defineProps({
  contactId: {
    type: Number,
    required: true,
  },
  align: {
    type: String,
    default: 'end',
  },
});

const router = useRouter();
const { t } = useI18n();
const inboxesList = useMapGetter('inboxes/getInboxes');
const currentUser = useMapGetter('getCurrentUser');

const popoverRef = ref(null);
const contactableInboxes = ref([]);
const isFetching = ref(false);
const isCreating = ref(false);

const inboxOptions = computed(() =>
  buildContactableInboxesList(contactableInboxes.value)
);

const loadInboxes = async () => {
  if (contactableInboxes.value.length || isFetching.value) return;

  isFetching.value = true;
  try {
    const processedInboxes = await fetchContactableInboxes(props.contactId);
    contactableInboxes.value = mergeInboxDetails(
      processedInboxes,
      inboxesList.value
    );
  } catch {
    useAlert(t('COMPOSE_NEW_CONVERSATION.CONTACT_SEARCH.ERROR_MESSAGE'));
  } finally {
    isFetching.value = false;
  }
};

const conversationPayload = inbox => {
  const payload = new FormData();
  payload.append('inbox_id', inbox.id);
  payload.append('contact_id', props.contactId);
  payload.append('source_id', inbox.sourceId);
  if (currentUser.value?.id) {
    payload.append('assignee_id', currentUser.value.id);
  }
  return payload;
};

const openConversation = async inbox => {
  if (isCreating.value) return;

  isCreating.value = true;
  try {
    const { data } = await ConversationAPI.create(conversationPayload(inbox));
    popoverRef.value?.hide();
    await router.push(
      `/app/accounts/${data.account_id}/conversations/${data.id}`
    );
  } catch {
    useAlert(t('COMPOSE_NEW_CONVERSATION.FORM.ERROR_MESSAGE'));
  } finally {
    isCreating.value = false;
  }
};
</script>

<template>
  <Popover
    ref="popoverRef"
    :align="align"
    :show-content-border="false"
    @show="loadInboxes"
  >
    <template #default="{ isOpen }">
      <slot name="trigger" :is-open="isOpen">
        <Button
          :label="t('CONTACTS_LAYOUT.HEADER.SEND_MESSAGE')"
          icon="i-lucide-message-circle"
          variant="ghost"
          color="slate"
          size="xs"
        />
      </slot>
    </template>

    <template #content>
      <div
        class="w-72 overflow-hidden rounded-xl border border-n-strong bg-n-alpha-3 shadow-xl backdrop-blur-[100px]"
      >
        <div class="border-b border-n-strong px-3 py-2">
          <p class="text-xs font-medium uppercase text-n-slate-11">
            {{ t('COMPOSE_NEW_CONVERSATION.FORM.INBOX_SELECTOR.LABEL') }}
          </p>
        </div>

        <div
          v-if="isFetching"
          class="flex items-center justify-center gap-2 px-3 py-5 text-sm text-n-slate-11"
        >
          <Spinner :size="16" />
          {{ t('COMPOSE_NEW_CONVERSATION.FORM.INBOX_SELECTOR.BUTTON') }}
        </div>

        <div
          v-else-if="!inboxOptions.length"
          class="px-3 py-3 text-sm text-n-amber-11 bg-n-amber-3 dark:bg-n-amber-11/15"
        >
          {{ t('COMPOSE_NEW_CONVERSATION.FORM.NO_INBOX_ALERT') }}
        </div>

        <div v-else class="max-h-72 overflow-y-auto p-1">
          <button
            v-for="inbox in inboxOptions"
            :key="inbox.id"
            type="button"
            class="flex w-full items-center gap-2 rounded-lg px-2 py-2 text-left text-sm text-n-slate-12 hover:bg-n-alpha-2 disabled:cursor-wait disabled:opacity-60"
            :disabled="isCreating"
            @click="openConversation(inbox)"
          >
            <span :class="inbox.icon" class="size-4 shrink-0 text-n-slate-11" />
            <span class="min-w-0 flex-1 truncate">{{ inbox.label }}</span>
          </button>
        </div>
      </div>
    </template>
  </Popover>
</template>
