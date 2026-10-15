<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import API from 'dashboard/api/marcosxAi';
import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import AiSelect from './AiSelect.vue';
import AiToggleRow from './AiToggleRow.vue';
import AudienceSelector from './AudienceSelector.vue';
import AudienceBadge from './AudienceBadge.vue';
import { defaultAudience, audiencePayload, audienceValid } from './audience';

const props = defineProps({
  agentId: { type: Number, required: true },
  conversationId: { type: Number, default: null },
  globalScope: { type: Boolean, default: true },
  compact: { type: Boolean, default: false },
});
const emit = defineEmits(['saved']);
const { t } = useI18n();
const items = ref([]);
const inboxes = ref([]);
const editor = ref(null);
const deleteDialog = ref(null);
const deleting = ref(null);
const draft = ref({});
const saving = ref(false);
const originalNumber = ref(null);
const error = ref('');
const formError = ref('');
let generation = 0;
const inboxOptions = computed(() =>
  inboxes.value.map(inbox => ({
    value: inbox.id,
    label: inbox.name,
    icon: 'i-lucide-message-circle',
  }))
);
const normalizedNumber = computed(() =>
  (draft.value.number || '').replace(/[\s().-]/g, '')
);
const valid = computed(
  () =>
    /^\+[1-9]\d{7,14}$/.test(normalizedNumber.value) &&
    draft.value.inbox_id &&
    audienceValid(draft.value)
);
const inputClass =
  'reset-base !mb-0 h-10 w-full rounded-lg border border-n-weak bg-n-solid-2 !px-3 text-sm text-n-slate-12 focus:!border-n-blue-9 focus:!ring-0';
const load = async () => {
  generation += 1;
  const current = generation;
  try {
    const [targets, options] = await Promise.all([
      API.getNotificationTargets(props.agentId),
      API.getNotificationOptions(),
    ]);
    if (current !== generation) return;
    items.value = targets.data.notification_targets;
    inboxes.value = options.data.inboxes;
    error.value = '';
  } catch (failure) {
    if (current === generation)
      error.value =
        failure.response?.data?.error ||
        t('MARCOX_AI.NOTIFICATION_TARGETS.ERROR');
  }
};
let initialLoad = Promise.resolve();
watch(
  () => props.agentId,
  () => {
    editor.value?.close();
    items.value = [];
    initialLoad = load();
  },
  { immediate: true }
);
const openEditor = item => {
  draft.value = item
    ? { ...item }
    : {
        title: '',
        number: '',
        inbox_id: inboxes.value[0]?.id || null,
        enabled: true,
        ...defaultAudience(props.globalScope, props.conversationId),
      };
  originalNumber.value = item?.number || null;
  formError.value = error.value;
  editor.value.open();
};
const save = async () => {
  if (!valid.value || saving.value) return;
  saving.value = true;
  try {
    const { id, title, inbox_id: inboxId, enabled } = draft.value;
    const { data } = await API.saveNotificationTarget(props.agentId, id, {
      title,
      number: normalizedNumber.value,
      inbox_id: inboxId,
      enabled,
      ...audiencePayload(draft.value),
    });
    items.value = data.notification_targets;
    editor.value.close();
    emit('saved', originalNumber.value ? [originalNumber.value] : []);
  } catch (failure) {
    formError.value =
      failure.response?.data?.error ||
      t('MARCOX_AI.NOTIFICATION_TARGETS.ERROR');
  } finally {
    saving.value = false;
  }
};
const requestDelete = item => {
  deleting.value = item;
  deleteDialog.value.open();
};
const remove = async () => {
  saving.value = true;
  try {
    const { data } = await API.deleteNotificationTarget(
      props.agentId,
      deleting.value.id
    );
    items.value = data.notification_targets;
    deleteDialog.value.close();
    emit('saved', [deleting.value.number]);
  } catch (failure) {
    error.value =
      failure.response?.data?.error ||
      t('MARCOX_AI.NOTIFICATION_TARGETS.ERROR');
  } finally {
    saving.value = false;
  }
};
defineExpose({
  openCreate: async () => {
    await initialLoad;
    if (editor.value) openEditor();
  },
});
</script>

<template>
  <section>
    <div v-if="!compact" class="space-y-4">
      <header class="flex flex-wrap items-center justify-between gap-3">
        <div>
          <h4
            class="m-0 flex items-center gap-2 text-base font-semibold text-n-slate-12"
          >
            <span class="i-lucide-bell size-5 text-n-ruby-11" />{{
              t('MARCOX_AI.NOTIFICATION_TARGETS.TITLE')
            }}
          </h4>
          <p class="mb-0 mt-1 text-xs leading-5 text-n-slate-11">
            {{ t('MARCOX_AI.NOTIFICATION_TARGETS.HINT') }}
          </p>
        </div>
        <Button
          icon="i-lucide-plus"
          variant="outline"
          :label="t('MARCOX_AI.NOTIFICATION_TARGETS.ADD')"
          @click="openEditor()"
        />
      </header>
      <p v-if="error" role="alert" class="text-sm text-n-ruby-11">
        {{ error }}
      </p>
      <p
        v-if="!items.length"
        class="rounded-xl border border-dashed border-n-weak p-6 text-center text-sm text-n-slate-11"
      >
        {{ t('MARCOX_AI.NOTIFICATION_TARGETS.EMPTY') }}
      </p>
      <div v-else class="grid gap-3 sm:grid-cols-2">
        <article
          v-for="item in items"
          :key="item.id"
          class="min-w-0 space-y-3 rounded-xl border border-n-weak bg-n-solid-2 p-4"
        >
          <div class="flex items-start justify-between gap-2">
            <div class="min-w-0">
              <h5 class="m-0 truncate text-sm font-medium text-n-slate-12">
                {{ item.title || item.number }}
              </h5>
              <p v-if="item.title" class="mb-0 mt-1 text-xs text-n-slate-11">
                {{ item.number }}
              </p>
            </div>
            <span v-if="!item.enabled" class="text-xs text-n-slate-11">{{
              t('MARCOX_AI.RESOURCES.DISABLED')
            }}</span>
          </div>
          <AudienceBadge :item="item" />
          <div class="flex justify-end gap-1 border-t border-n-weak pt-2">
            <Button
              variant="ghost"
              color="slate"
              icon="i-lucide-pencil"
              :aria-label="t('MARCOX_AI.NOTIFICATION_TARGETS.EDIT')"
              @click="openEditor(item)"
            />
            <Button
              variant="ghost"
              color="ruby"
              icon="i-lucide-trash-2"
              :aria-label="t('MARCOX_AI.NOTIFICATION_TARGETS.DELETE')"
              @click="requestDelete(item)"
            />
          </div>
        </article>
      </div>
    </div>
    <Dialog
      ref="editor"
      :title="
        t(
          draft.id
            ? 'MARCOX_AI.NOTIFICATION_TARGETS.EDIT'
            : 'MARCOX_AI.NOTIFICATION_TARGETS.ADD'
        )
      "
      :confirm-button-label="t('MARCOX_AI.SAVE')"
      :disable-confirm-button="!valid || saving"
      :is-loading="saving"
      :prevent-close="saving"
      @confirm="save"
    >
      <div class="max-h-[60vh] space-y-4 overflow-y-auto p-1">
        <label class="block space-y-2 text-sm font-medium text-n-slate-12">
          <span>{{ t('MARCOX_AI.NOTIFICATION_TARGETS.NAME') }}</span>
          <input
            v-model="draft.title"
            type="text"
            :class="inputClass"
            maxlength="120"
          />
        </label>
        <label class="block space-y-2 text-sm font-medium text-n-slate-12">
          <span>{{ t('MARCOX_AI.AUTOMATION.WHATSAPP_NUMBERS') }}</span>
          <input
            v-model="draft.number"
            type="tel"
            :class="inputClass"
            :placeholder="t('MARCOX_AI.WORKSPACE.NUMBER_PLACEHOLDER')"
          />
        </label>
        <div class="space-y-2">
          <p class="m-0 text-sm font-medium text-n-slate-12">
            {{ t('MARCOX_AI.AUTOMATION.SENDER_INBOX') }}
          </p>
          <AiSelect
            v-model="draft.inbox_id"
            :options="inboxOptions"
            :label="t('MARCOX_AI.AUTOMATION.SENDER_INBOX')"
            :teleport="false"
            in-flow
          />
        </div>
        <AudienceSelector
          v-model="draft"
          :agent-id="agentId"
          :conversation-id="conversationId"
        />
        <AiToggleRow
          v-model="draft.enabled"
          :label="t('MARCOX_AI.NOTIFICATION_TARGETS.ENABLED')"
          :description="t('MARCOX_AI.NOTIFICATION_TARGETS.ENABLED_HINT')"
        />
        <p v-if="formError" role="alert" class="m-0 text-sm text-n-ruby-11">
          {{ formError }}
        </p>
      </div>
    </Dialog>
    <Dialog
      ref="deleteDialog"
      :title="t('MARCOX_AI.NOTIFICATION_TARGETS.DELETE')"
      :description="
        t('MARCOX_AI.NOTIFICATION_TARGETS.DELETE_HINT', {
          number: deleting?.number,
        })
      "
      :is-loading="saving"
      :prevent-close="saving"
      @confirm="remove"
    />
  </section>
</template>
