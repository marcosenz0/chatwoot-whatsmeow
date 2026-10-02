<script setup>
import { computed, nextTick, ref, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import InboxesAPI from 'dashboard/api/inboxes';
import {
  whatsmeowConversationPath,
  whatsmeowDirectConversationPayload,
} from 'dashboard/helper/whatsmeowConversationHelper';
import Avatar from 'next/avatar/Avatar.vue';
import Button from 'next/button/Button.vue';
import Dialog from 'next/dialog/Dialog.vue';

const props = defineProps({
  member: { type: Object, default: null },
  inboxId: { type: Number, required: true },
  menuTarget: { type: Object, default: null },
});
const emit = defineEmits(['close', 'navigate']);
const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const menu = ref(null);
const dialog = ref(null);
const detailMember = ref(null);
const detailMode = ref('');
const busy = ref(false);
const memberLabel = computed(
  () => props.member?.name || props.member?.phone_number
);
const detailLabel = computed(
  () => detailMember.value?.name || detailMember.value?.phone_number
);

watch(
  () => props.member,
  async member => {
    await nextTick();
    if (member) menu.value.showPopover();
    else menu.value.hidePopover();
  }
);

function menuToggled(event) {
  if (event.newState === 'closed' && !menu.value.matches(':popover-open')) {
    emit('close');
  }
}

function showDetails(mode) {
  detailMember.value = props.member;
  detailMode.value = mode;
  menu.value.hidePopover();
  dialog.value.open();
}

async function converse() {
  if (busy.value) return;
  const { member } = props;
  const { inboxId } = props;
  busy.value = true;
  try {
    const { data } = await InboxesAPI.createWhatsmeowDirectConversation(
      inboxId,
      whatsmeowDirectConversationPayload({
        ...member,
        phoneNumber: member.phone_number,
      })
    );
    menu.value.hidePopover();
    emit('navigate');
    await router.push({
      path: whatsmeowConversationPath({
        route,
        inboxId,
        conversationId: data.conversation_id || data.id,
      }),
    });
  } catch (error) {
    useAlert(
      error.response?.data?.message ||
        t('CONVERSATION.WHATSMEOW_PHONE.OPEN_FAILED')
    );
  } finally {
    busy.value = false;
  }
}
</script>

<template>
  <Teleport :to="menuTarget || 'body'">
    <div
      ref="menu"
      popover="auto"
      role="menu"
      :aria-label="memberLabel"
      class="fixed bottom-auto right-auto m-0 mt-1 w-72 max-w-[calc(100vw-2rem)] rounded-xl border border-n-weak bg-n-solid-2 p-1 text-n-slate-12 shadow-lg [position-anchor:--group-member] [top:anchor(bottom)] [left:anchor(left)] [position-try-fallbacks:flip-block,flip-inline]"
      @toggle="menuToggled"
    >
      <template v-if="member">
        <Button
          role="menuitem"
          icon="i-lucide-info"
          :label="$t('WHATSMEOW_UI.CONTACT_DETAILS')"
          ghost
          slate
          class="w-full justify-start"
          @click="showDetails('contact')"
        />
        <Button
          role="menuitem"
          icon="i-lucide-shield-check"
          :label="$t('WHATSMEOW_UI.SECURITY_CODE')"
          ghost
          slate
          class="w-full justify-start"
          @click="showDetails('security')"
        />
        <Button
          role="menuitem"
          icon="i-lucide-message-square"
          :label="$t('WHATSMEOW_UI.CHAT_WITH_MEMBER', { member: memberLabel })"
          ghost
          slate
          :is-loading="busy"
          :disabled="busy"
          class="w-full justify-start [&>span]:whitespace-normal [&>span]:break-words"
          @click="converse"
        />
      </template>
    </div>
  </Teleport>
  <Dialog
    ref="dialog"
    width="sm"
    :title="
      $t(
        detailMode === 'security'
          ? 'WHATSMEOW_UI.SECURITY_CODE'
          : 'WHATSMEOW_UI.CONTACT_DETAILS'
      )
    "
    :show-confirm-button="false"
    :cancel-button-label="$t('WHATSMEOW_UI.CLOSE')"
  >
    <div
      v-if="detailMember"
      class="flex flex-col items-center gap-3 text-center"
    >
      <Avatar
        :name="detailLabel"
        :src="detailMember.profile_picture_url"
        :size="72"
        hide-offline-status
      />
      <p class="m-0 max-w-full break-words text-lg font-semibold">
        {{ detailLabel }}
      </p>
      <p
        v-if="detailMember.name !== detailMember.phone_number"
        class="m-0 text-sm text-n-slate-11"
      >
        {{ detailMember.phone_number }}
      </p>
      <p v-if="detailMode === 'security'" class="m-0 text-sm text-n-slate-11">
        {{ $t('WHATSMEOW_UI.SECURITY_CODE_HELP') }}
      </p>
      <p
        v-else-if="detailMember.is_admin || detailMember.is_super_admin"
        class="m-0 text-sm text-n-teal-11"
      >
        {{
          $t(
            detailMember.is_super_admin
              ? 'WHATSMEOW_UI.OWNER'
              : 'WHATSMEOW_UI.ADMIN'
          )
        }}
      </p>
    </div>
  </Dialog>
</template>
