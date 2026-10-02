<script setup>
import { computed, onMounted, ref } from 'vue';
import { useStore } from 'vuex';
import { useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { conversationUrl, frontendURL } from 'dashboard/helper/URLHelper';
import GroupsAPI from 'dashboard/api/whatsmeowGroups';
import Dialog from 'next/dialog/Dialog.vue';
import Button from 'next/button/Button.vue';
import { useAlert } from 'dashboard/composables';
import GroupContactPicker from './GroupContactPicker.vue';
import GroupSettings from './GroupSettings.vue';

const props = defineProps({
  inboxId: { type: Number, default: null },
  participants: { type: Array, default: () => [] },
});
const emit = defineEmits(['close']);
const store = useStore();
const router = useRouter();
const { t } = useI18n();
const dialog = ref(null);
const inboxes = computed(() =>
  store.getters['inboxes/getInboxes'].filter(
    i => i.channel_type === 'Channel::Whatsmeow'
  )
);
const selectedInbox = ref(props.inboxId || inboxes.value[0]?.id);
const selected = ref([...props.participants]);
const step = ref(0);
const saving = ref(false);
const error = ref('');
const settings = ref({
  name: '',
  topic: '',
  allow_member_edit: true,
  allow_member_send: true,
  allow_member_add: true,
  require_approval: false,
  disappearing_timer: 0,
});
const confirmDisabled = computed(
  () =>
    !selectedInbox.value ||
    !selected.value.length ||
    (step.value === 1 && !settings.value.name.trim())
);
async function confirm() {
  if (!step.value) {
    step.value = 1;
    return;
  }
  saving.value = true;
  error.value = '';
  try {
    const { data } = await GroupsAPI.create(selectedInbox.value, {
      ...settings.value,
      participants: selected.value.map(p => p.jid),
    });
    await store.dispatch('getConversation', data.conversation_id);
    await router.push(
      frontendURL(
        conversationUrl({
          accountId: store.getters.getCurrentAccountId,
          id: data.conversation_id,
        })
      )
    );
    useAlert(
      data.warnings?.length
        ? t('WHATSMEOW_UI.CREATED_WITH_WARNINGS', {
            details: data.warnings.join('; '),
          })
        : t('WHATSMEOW_UI.GROUP_CREATED')
    );
    dialog.value.close();
  } catch (e) {
    error.value = e.response?.data?.message || t('WHATSMEOW_UI.SAVE_ERROR');
  } finally {
    saving.value = false;
  }
}
onMounted(() => dialog.value.open());
</script>

<template>
  <Dialog
    ref="dialog"
    :title="$t(step ? 'WHATSMEOW_UI.NEW_GROUP' : 'WHATSMEOW_UI.ADD_PEOPLE')"
    :confirm-button-label="
      $t(step ? 'WHATSMEOW_UI.CREATE_GROUP' : 'WHATSMEOW_UI.CONTINUE')
    "
    :disable-confirm-button="confirmDisabled"
    :is-loading="saving"
    :prevent-close="saving"
    @confirm="confirm"
    @close="emit('close')"
  >
    <div class="max-h-[65vh] overflow-y-auto flex flex-col gap-4">
      <label v-if="!step" class="text-sm flex flex-col gap-2">
        {{ $t('WHATSMEOW_UI.INBOX') }}
        <select
          v-model="selectedInbox"
          class="reset-base rounded-lg bg-n-surface-1 border border-n-weak p-2"
        >
          <option v-for="inbox in inboxes" :key="inbox.id" :value="inbox.id">
            {{ inbox.name }}
          </option>
        </select>
      </label>
      <GroupContactPicker
        v-if="!step && selectedInbox"
        v-model="selected"
        :inbox-id="selectedInbox"
      />
      <template v-if="step">
        <Button
          ghost
          slate
          xs
          icon="i-lucide-arrow-left"
          :label="
            $t('WHATSMEOW_UI.MEMBERS_SELECTED', { count: selected.length })
          "
          @click="step = 0"
        />
        <GroupSettings v-model="settings" />
      </template>
      <p v-if="error" role="alert" class="m-0 text-sm text-n-ruby-11">
        {{ error }}
      </p>
    </div>
  </Dialog>
</template>
