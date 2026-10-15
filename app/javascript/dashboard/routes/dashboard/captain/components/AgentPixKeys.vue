<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import API from 'dashboard/api/marcosxAi';
import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import WhatsmeowPixCard from 'next/message/WhatsmeowPixCard.vue';
import PixIcon from 'next/icon/PixIcon.vue';
import AiToggleRow from './AiToggleRow.vue';
import AudienceSelector from './AudienceSelector.vue';
import AudienceBadge from './AudienceBadge.vue';
import { defaultAudience, audiencePayload, audienceValid } from './audience';
import AiSelect from './AiSelect.vue';

const props = defineProps({
  agentId: { type: Number, required: true },
  conversationId: { type: Number, default: null },
  globalScope: { type: Boolean, default: true },
  compact: { type: Boolean, default: false },
});
const emit = defineEmits(['saved']);
const { t } = useI18n();
const items = ref([]);
const busy = ref(false);
const saving = ref(false);
const error = ref('');
const formError = ref('');
const editor = ref(null);
const deleteDialog = ref(null);
const deleting = ref(null);
const draft = ref({});
const activeCount = computed(
  () => items.value.filter(item => item.enabled).length
);
const keyTypes = computed(() =>
  [
    ['PHONE', 'i-lucide-smartphone'],
    ['CPF', 'i-lucide-id-card'],
    ['EMAIL', 'i-lucide-mail'],
    ['EVP', 'i-lucide-key-round'],
  ].map(([value, icon]) => ({
    value,
    icon,
    label: t(`CONVERSATION.WHATSMEOW_PIX.KEY_TYPES.${value}`),
  }))
);
const valid = computed(
  () =>
    ['title', 'key', 'merchant_name'].every(field =>
      draft.value[field]?.trim()
    ) && audienceValid(draft.value)
);
const inputClass =
  'reset-base !mb-0 w-full rounded-lg border border-n-weak bg-n-solid-2 !px-3 !py-2.5 text-sm text-n-slate-12 focus:!border-n-blue-9 focus:!ring-0';
const failureText = failure =>
  failure.response?.data?.error || t('MARCOX_AI.PIX.ERROR');
let generation = 0;
const load = async () => {
  generation += 1;
  const current = generation;
  busy.value = true;
  try {
    const { data } = await API.getPixKeys(props.agentId);
    if (current !== generation) return;
    items.value = data.pix_keys;
    error.value = '';
  } catch (failure) {
    if (current === generation) error.value = failureText(failure);
  } finally {
    if (current === generation) busy.value = false;
  }
};
let initialLoad = Promise.resolve();
watch(
  () => props.agentId,
  () => {
    items.value = [];
    editor.value?.close();
    deleteDialog.value?.close();
    initialLoad = load();
  },
  { immediate: true }
);
const openEditor = item => {
  draft.value = item
    ? { ...item }
    : {
        title: '',
        key_type: 'PHONE',
        key: '',
        merchant_name: '',
        description: '',
        enabled: activeCount.value < 2,
        ...defaultAudience(props.globalScope, props.conversationId),
      };
  formError.value = error.value;
  editor.value.open();
};
const save = async () => {
  if (!valid.value || saving.value) return;
  saving.value = true;
  try {
    const {
      id,
      title,
      key_type: keyType,
      key,
      merchant_name: merchantName,
      description,
      enabled,
    } = draft.value;
    const { data } = await API.savePixKey(props.agentId, id, {
      title,
      key_type: keyType,
      key,
      merchant_name: merchantName,
      description,
      enabled,
      ...audiencePayload(draft.value),
    });
    items.value = data.pix_keys;
    editor.value.close();
    emit('saved');
    error.value = '';
  } catch (failure) {
    formError.value = failureText(failure);
  } finally {
    saving.value = false;
  }
};
const update = async (item, attributes) => {
  saving.value = true;
  try {
    const { data } = await API.savePixKey(props.agentId, item.id, attributes);
    items.value = data.pix_keys;
    error.value = '';
  } catch (failure) {
    error.value = failureText(failure);
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
    const { data } = await API.deletePixKey(props.agentId, deleting.value.id);
    items.value = data.pix_keys;
    error.value = '';
    deleteDialog.value.close();
  } catch (failure) {
    error.value = failureText(failure);
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
  <section :class="compact ? '' : 'min-h-0 flex-1 overflow-y-auto p-4 sm:p-6'">
    <div v-if="!compact" class="mx-auto w-full max-w-6xl space-y-6">
      <header class="flex flex-wrap items-start justify-between gap-4">
        <div class="max-w-2xl">
          <h2
            class="m-0 flex items-center gap-2 text-lg font-semibold text-n-slate-12"
          >
            <PixIcon class="size-5 text-n-teal-11" />{{
              t('MARCOX_AI.PIX.TITLE')
            }}
          </h2>
          <p class="mb-0 mt-2 text-sm leading-6 text-n-slate-11">
            {{ t('MARCOX_AI.PIX.BODY') }}
          </p>
        </div>
        <Button
          icon="i-lucide-plus"
          :label="t('MARCOX_AI.PIX.ADD')"
          :disabled="busy || saving"
          @click="openEditor()"
        />
      </header>
      <div
        class="flex items-center gap-2 rounded-xl border border-n-weak bg-n-solid-2 p-4 text-sm text-n-slate-11"
      >
        <span class="i-lucide-info size-4 shrink-0" />
        <p class="m-0">
          {{ t('MARCOX_AI.PIX.ACTIVE_COUNT', { count: activeCount }) }}.
          {{ t('MARCOX_AI.PIX.LIMIT_HINT') }}
        </p>
      </div>
      <p v-if="error" role="alert" class="text-sm text-n-ruby-11">
        {{ error }}
      </p>
      <p v-if="busy" class="text-sm text-n-slate-11">
        {{ t('MARCOX_AI.PIX.LOADING') }}
      </p>
      <p
        v-else-if="!items.length"
        class="rounded-xl border border-dashed border-n-weak p-8 text-center text-sm leading-6 text-n-slate-11"
      >
        {{ t('MARCOX_AI.PIX.EMPTY') }}
      </p>
      <div v-else class="grid gap-4 md:grid-cols-2 xl:grid-cols-3">
        <article
          v-for="item in items"
          :key="item.id"
          class="min-w-0 overflow-hidden rounded-xl border bg-n-solid-2"
          :class="
            item.enabled
              ? 'border-n-blue-9 ring-1 ring-n-blue-9'
              : 'border-n-weak'
          "
        >
          <button
            type="button"
            role="switch"
            :aria-checked="item.enabled"
            :aria-label="t('MARCOX_AI.PIX.TOGGLE', { name: item.title })"
            :title="
              !item.enabled && activeCount >= 2
                ? t('MARCOX_AI.PIX.LIMIT_HINT')
                : item.title
            "
            :disabled="saving || (!item.enabled && activeCount >= 2)"
            class="block w-full space-y-3 p-4 text-start disabled:cursor-not-allowed focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-9"
            @click="update(item, { enabled: !item.enabled })"
          >
            <span class="flex items-center justify-between gap-2">
              <span class="truncate text-sm font-semibold text-n-slate-12">
                {{ item.title }}
              </span>
              <span
                class="shrink-0 rounded-md px-2 py-1 text-xs"
                :class="
                  item.enabled
                    ? 'bg-n-blue-3 text-n-blue-11'
                    : 'bg-n-alpha-2 text-n-slate-11'
                "
              >
                {{
                  t(
                    item.primary
                      ? 'MARCOX_AI.PIX.PRIMARY'
                      : item.enabled
                        ? 'MARCOX_AI.PIX.ALTERNATIVE'
                        : 'MARCOX_AI.PIX.INACTIVE'
                  )
                }}
              </span>
            </span>
            <span class="block text-sm text-n-slate-11">
              {{ item.merchant_name }}
            </span>
            <span class="block break-all text-sm text-n-slate-12">
              {{
                `${t(`CONVERSATION.WHATSMEOW_PIX.KEY_TYPES.${item.key_type}`)}: ${item.key}`
              }}
            </span>
            <span
              v-if="item.description"
              class="block line-clamp-3 text-xs leading-5 text-n-slate-11"
            >
              {{ item.description }}
            </span>
            <AudienceBadge :item="item" />
          </button>
          <div
            class="flex flex-wrap items-center justify-end gap-1 border-t border-n-weak px-3 py-2"
          >
            <Button
              v-if="item.enabled && !item.primary"
              size="sm"
              variant="ghost"
              color="slate"
              icon="i-lucide-star"
              :label="t('MARCOX_AI.PIX.MAKE_PRIMARY')"
              :disabled="saving"
              @click="update(item, { primary: true })"
            />
            <Button
              variant="ghost"
              color="slate"
              icon="i-lucide-pencil"
              :aria-label="t('MARCOX_AI.PIX.EDIT')"
              :disabled="saving"
              @click="openEditor(item)"
            />
            <Button
              variant="ghost"
              color="ruby"
              icon="i-lucide-trash-2"
              :aria-label="t('MARCOX_AI.PIX.DELETE')"
              :disabled="saving"
              @click="requestDelete(item)"
            />
          </div>
        </article>
      </div>
      <p class="text-xs leading-5 text-n-slate-11">
        {{ t('MARCOX_AI.PIX.CHANNEL_HINT') }}
      </p>
    </div>
    <Dialog
      ref="editor"
      width="3xl"
      :title="t(draft.id ? 'MARCOX_AI.PIX.EDIT' : 'MARCOX_AI.PIX.ADD')"
      :confirm-button-label="t('MARCOX_AI.PIX.SAVE')"
      :disable-confirm-button="!valid || saving"
      :is-loading="saving"
      :prevent-close="saving"
      @confirm="save"
    >
      <div
        class="grid max-h-[60vh] min-w-0 gap-6 overflow-y-auto p-1 md:grid-cols-2"
      >
        <div class="min-w-0 space-y-4">
          <label class="block space-y-2 text-sm font-medium text-n-slate-12">
            <span>{{ t('MARCOX_AI.PIX.NAME') }}</span>
            <input
              v-model="draft.title"
              type="text"
              :class="inputClass"
              maxlength="120"
            />
          </label>
          <div class="space-y-2">
            <span class="text-sm font-medium text-n-slate-12">{{
              t('CONVERSATION.WHATSMEOW_PIX.KEY_TYPE')
            }}</span>
            <AiSelect
              v-model="draft.key_type"
              :options="keyTypes"
              :label="t('CONVERSATION.WHATSMEOW_PIX.KEY_TYPE')"
              :teleport="false"
              in-flow
            />
          </div>
          <label class="block space-y-2 text-sm font-medium text-n-slate-12">
            <span>{{ t('CONVERSATION.WHATSMEOW_PIX.KEY') }}</span>
            <input
              v-model="draft.key"
              type="text"
              :class="inputClass"
              maxlength="255"
            />
          </label>
          <label class="block space-y-2 text-sm font-medium text-n-slate-12">
            <span>{{ t('MARCOX_AI.PIX.HOLDER') }}</span>
            <input
              v-model="draft.merchant_name"
              type="text"
              :class="inputClass"
              maxlength="100"
            />
          </label>
        </div>
        <div class="min-w-0 space-y-4">
          <p class="m-0 text-sm font-medium text-n-slate-12">
            {{ t('MARCOX_AI.PIX.PREVIEW') }}
          </p>
          <WhatsmeowPixCard :pix="draft" standalone />
          <label class="block space-y-2 text-sm font-medium text-n-slate-12">
            <span>{{ t('MARCOX_AI.PIX.DESCRIPTION') }}</span>
            <textarea
              v-model="draft.description"
              :class="inputClass"
              rows="3"
              maxlength="800"
              :placeholder="t('MARCOX_AI.PIX.DESCRIPTION_HINT')"
            />
          </label>
          <AudienceSelector
            v-model="draft"
            :agent-id="agentId"
            :conversation-id="conversationId"
          />
          <AiToggleRow
            v-model="draft.enabled"
            :label="t('MARCOX_AI.PIX.ENABLED')"
            :disabled="!draft.enabled && activeCount >= 2"
            :description="t('MARCOX_AI.PIX.ENABLED_HINT')"
          />
        </div>
        <p
          v-if="formError"
          role="alert"
          class="m-0 text-sm text-n-ruby-11 md:col-span-2"
        >
          {{ formError }}
        </p>
      </div>
    </Dialog>
    <Dialog
      ref="deleteDialog"
      :title="t('MARCOX_AI.PIX.DELETE')"
      :description="t('MARCOX_AI.PIX.DELETE_HINT', { name: deleting?.title })"
      :is-loading="saving"
      :prevent-close="saving"
      @confirm="remove"
    />
  </section>
</template>
