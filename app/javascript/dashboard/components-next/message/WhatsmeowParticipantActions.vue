<script setup>
import { computed, ref } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import InboxesAPI from 'dashboard/api/inboxes';
import {
  whatsmeowConversationPath,
  whatsmeowDirectConversationPayload,
} from 'dashboard/helper/whatsmeowConversationHelper';

import Avatar from 'next/avatar/Avatar.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  inboxId: { type: [Number, String], required: true },
  name: { type: String, default: '' },
  phoneNumber: { type: String, default: '' },
  jid: { type: String, default: '' },
  avatarUrl: { type: String, default: '' },
});

const route = useRoute();
const router = useRouter();
const { t } = useI18n();

const isOpen = ref(false);
const isOpeningConversation = ref(false);

const hasTarget = computed(() => !!(props.phoneNumber || props.jid));
const secondaryLabel = computed(() => props.phoneNumber || props.jid);

const closeMenu = () => {
  isOpen.value = false;
};

const toggleMenu = () => {
  if (hasTarget.value) {
    isOpen.value = !isOpen.value;
  }
};

const openPrivateConversation = async () => {
  if (!hasTarget.value || isOpeningConversation.value) return;

  isOpeningConversation.value = true;
  try {
    const { data } = await InboxesAPI.createWhatsmeowDirectConversation(
      props.inboxId,
      whatsmeowDirectConversationPayload({
        jid: props.jid,
        phoneNumber: props.phoneNumber,
        name: props.name,
        profilePictureUrl: props.avatarUrl,
      })
    );
    const conversationId = data.conversation_id || data.id;
    await router.push({
      path: whatsmeowConversationPath({
        route,
        inboxId: props.inboxId,
        conversationId,
      }),
    });
  } catch (error) {
    useAlert(
      error?.response?.data?.message ||
        t('CONVERSATION.WHATSMEOW_GROUP.OPEN_PRIVATE_CHAT_FAILED')
    );
  } finally {
    isOpeningConversation.value = false;
    closeMenu();
  }
};

const copyPhoneNumber = async () => {
  const value = props.phoneNumber || props.jid;
  if (!value) return;

  await navigator.clipboard.writeText(value);
  useAlert(t('CONVERSATION.WHATSMEOW_GROUP.COPIED'));
  closeMenu();
};
</script>

<template>
  <div v-on-clickaway="closeMenu" class="relative inline-flex max-w-full">
    <button
      type="button"
      class="flex min-w-0 items-center gap-1.5 rounded-md px-1 py-0.5 text-left text-xs font-medium text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-slate-12"
      :disabled="!hasTarget"
      @click.stop="toggleMenu"
    >
      <Avatar :name="name" :src="avatarUrl" :size="16" />
      <span class="truncate">{{ name }}</span>
      <span v-if="hasTarget" class="i-lucide-chevron-down size-3 shrink-0" />
    </button>

    <div
      v-if="isOpen"
      class="absolute left-0 top-full z-[60] mt-1 w-64 rounded-lg border border-n-weak bg-n-alpha-3 p-2 shadow-lg backdrop-blur-[100px]"
      @click.stop
    >
      <div class="flex items-center gap-2 px-2 py-2">
        <Avatar :name="name" :src="avatarUrl" :size="28" />
        <div class="min-w-0">
          <p class="m-0 truncate text-sm font-medium text-n-slate-12">
            {{ name }}
          </p>
          <p class="m-0 truncate text-xs text-n-slate-10">
            {{ secondaryLabel }}
          </p>
        </div>
      </div>
      <div class="mt-1 flex flex-col gap-1">
        <NextButton
          ghost
          slate
          sm
          start
          icon="i-ph-chat-circle-dots"
          :label="$t('CONVERSATION.WHATSMEOW_GROUP.OPEN_PRIVATE_CHAT')"
          :is-loading="isOpeningConversation"
          @click="openPrivateConversation"
        />
        <NextButton
          ghost
          slate
          sm
          start
          icon="i-lucide-copy"
          :label="$t('CONVERSATION.WHATSMEOW_GROUP.COPY_CONTACT')"
          @click="copyPhoneNumber"
        />
      </div>
    </div>
  </div>
</template>
