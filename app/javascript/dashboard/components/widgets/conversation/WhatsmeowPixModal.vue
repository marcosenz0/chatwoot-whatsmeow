<script setup>
import { computed, nextTick, reactive, ref, watch } from 'vue';
import { OnClickOutside } from '@vueuse/components';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import WhatsmeowPixAPI from 'dashboard/api/whatsmeowPix';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import WhatsmeowPixCard from 'next/message/WhatsmeowPixCard.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';
import Icon from 'next/icon/Icon.vue';
import PixIcon from 'next/icon/PixIcon.vue';

const props = defineProps({
  isOpen: {
    type: Boolean,
    default: false,
  },
  inboxId: {
    type: Number,
    required: true,
  },
  conversationId: {
    type: Number,
    required: true,
  },
});

const emit = defineEmits(['close', 'sent']);
const { t } = useI18n();

const dialogRef = ref(null);
const keyTypeInput = ref(null);
const keyTypeMenu = ref(null);
const isKeyTypeMenuOpen = ref(false);
const sendButton = ref(null);
const closeButton = ref(null);
const previouslyFocusedElement = ref(null);

const isLoading = ref(false);
const isSaving = ref(false);
const isDeleting = ref(false);
const isSending = ref(false);
const isConfigured = ref(false);
const canManage = ref(false);
const confirmDelete = ref(false);
const openedConversationId = ref(null);
const requestId = ref(0);
const mode = ref('edit');
const savedPix = ref(null);

const emptyForm = () => ({
  keyType: 'PHONE',
  key: '',
  merchantName: '',
});

const form = reactive(emptyForm());

const keyTypes = computed(() => [
  {
    value: 'PHONE',
    label: t('CONVERSATION.WHATSMEOW_PIX.KEY_TYPES.PHONE'),
    icon: 'i-lucide-smartphone',
  },
  {
    value: 'CPF',
    label: t('CONVERSATION.WHATSMEOW_PIX.KEY_TYPES.CPF'),
    icon: 'i-lucide-id-card',
  },
  {
    value: 'EMAIL',
    label: t('CONVERSATION.WHATSMEOW_PIX.KEY_TYPES.EMAIL'),
    icon: 'i-lucide-mail',
  },
  {
    value: 'EVP',
    label: t('CONVERSATION.WHATSMEOW_PIX.KEY_TYPES.EVP'),
    icon: 'i-lucide-key-round',
  },
]);

const selectedKeyType = computed(() =>
  keyTypes.value.find(keyType => keyType.value === form.keyType)
);

const activeConversationId = computed(() => Number(props.conversationId || 0));
const isEditing = computed(() => mode.value === 'edit');

const normalizedPayload = computed(() => ({
  key_type: form.keyType,
  key: form.key.trim(),
  merchant_name: form.merchantName.trim(),
}));

const formPix = computed(() => ({
  keyType: form.keyType,
  key: form.key,
  merchantName: form.merchantName,
}));

const previewPix = computed(() =>
  isEditing.value ? formPix.value : savedPix.value || formPix.value
);

const isFormComplete = computed(
  () => !!form.keyType && !!form.key.trim() && !!form.merchantName.trim()
);

const isBusy = computed(
  () => isLoading.value || isSaving.value || isDeleting.value || isSending.value
);

const canSend = computed(
  () => !isBusy.value && isConfigured.value && !isEditing.value
);

const inputType = computed(() => {
  if (form.keyType === 'EMAIL') return 'email';
  if (['PHONE', 'CPF'].includes(form.keyType)) return 'tel';
  return 'text';
});

const keyPlaceholder = computed(() => {
  const placeholders = {
    PHONE: t('CONVERSATION.WHATSMEOW_PIX.KEY_PLACEHOLDERS.PHONE'),
    CPF: t('CONVERSATION.WHATSMEOW_PIX.KEY_PLACEHOLDERS.CPF'),
    EMAIL: t('CONVERSATION.WHATSMEOW_PIX.KEY_PLACEHOLDERS.EMAIL'),
    EVP: t('CONVERSATION.WHATSMEOW_PIX.KEY_PLACEHOLDERS.EVP'),
  };
  return placeholders[form.keyType] || '';
});

const resetForm = () => {
  Object.assign(form, emptyForm());
};

const focusControl = control => {
  const element = control?.value?.$el || control?.value;
  element?.focus?.();
};

const focusKeyTypeOption = index => {
  nextTick(() => {
    keyTypeMenu.value?.querySelectorAll('[role="option"]')[index]?.focus();
  });
};

const openKeyTypeMenu = () => {
  if (!canManage.value || isBusy.value) return;
  isKeyTypeMenuOpen.value = true;
  const selectedIndex = keyTypes.value.findIndex(
    keyType => keyType.value === form.keyType
  );
  focusKeyTypeOption(Math.max(0, selectedIndex));
};

const toggleKeyTypeMenu = () => {
  if (isKeyTypeMenuOpen.value) {
    isKeyTypeMenuOpen.value = false;
  } else {
    openKeyTypeMenu();
  }
};

const closeKeyTypeMenu = () => {
  isKeyTypeMenuOpen.value = false;
  focusControl(keyTypeInput);
};

const selectKeyType = value => {
  form.keyType = value;
  closeKeyTypeMenu();
};

const handleKeyTypeFocusOut = event => {
  if (!event.currentTarget.contains(event.relatedTarget)) {
    isKeyTypeMenuOpen.value = false;
  }
};

const handleKeyTypeMenuKeydown = event => {
  const options = keyTypeMenu.value?.querySelectorAll('[role="option"]');
  if (!options?.length) return;

  if (event.key === 'Escape') {
    event.preventDefault();
    closeKeyTypeMenu();
    return;
  }

  const currentIndex = Array.from(options).indexOf(document.activeElement);
  const lastIndex = options.length - 1;
  const nextIndex = {
    ArrowDown: Math.min(currentIndex + 1, lastIndex),
    ArrowUp: Math.max(currentIndex - 1, 0),
    Home: 0,
    End: lastIndex,
  }[event.key];

  if (nextIndex !== undefined) {
    event.preventDefault();
    options[nextIndex].focus();
  }
};

const focusRelevantControl = () => {
  nextTick(() => {
    if (isEditing.value && canManage.value) {
      focusControl(keyTypeInput);
    } else if (isConfigured.value) {
      focusControl(sendButton);
    } else {
      focusControl(closeButton);
    }
  });
};

const close = () => {
  if (isBusy.value) return;
  dialogRef.value?.close();
};

const resetModal = () => {
  requestId.value += 1;
  openedConversationId.value = null;
  isLoading.value = false;
  isSaving.value = false;
  isDeleting.value = false;
  isSending.value = false;
  isConfigured.value = false;
  canManage.value = false;
  confirmDelete.value = false;
  isKeyTypeMenuOpen.value = false;
  savedPix.value = null;
  mode.value = 'edit';
  resetForm();
};

const handleDialogClose = () => {
  const focusTarget = previouslyFocusedElement.value;
  resetModal();
  previouslyFocusedElement.value = null;
  emit('close');
  nextTick(() => focusTarget?.focus?.());
};

const apiErrorMessage = (error, fallbackMessage) => {
  const apiError = error?.response?.data?.error;
  return (
    (typeof apiError === 'object' ? apiError?.message : apiError) ||
    fallbackMessage
  );
};

const applyConfiguration = data => {
  const payload = data?.payload || data || {};
  const pix = payload.pix || {};
  const normalizedPix = {
    keyType: pix.keyType || pix.key_type || 'PHONE',
    key: pix.key || '',
    merchantName: pix.merchantName || pix.merchant_name || '',
  };

  isConfigured.value = !!payload.configured;
  canManage.value = payload.canManage ?? payload.can_manage ?? false;
  savedPix.value = isConfigured.value ? normalizedPix : null;
  Object.assign(form, isConfigured.value ? normalizedPix : emptyForm());
  mode.value = isConfigured.value ? 'preview' : 'edit';
};

const loadConfiguration = async () => {
  const currentRequestId = requestId.value + 1;
  requestId.value = currentRequestId;
  isLoading.value = true;
  let didLoad = false;

  try {
    const { data } = await WhatsmeowPixAPI.getConfiguration(
      props.inboxId,
      activeConversationId.value
    );
    if (requestId.value !== currentRequestId) return;
    applyConfiguration(data);
    didLoad = true;
  } catch (error) {
    if (requestId.value !== currentRequestId) return;
    useAlert(
      apiErrorMessage(error, t('CONVERSATION.WHATSMEOW_PIX.LOAD_FAILED'))
    );
    dialogRef.value?.close();
  } finally {
    if (requestId.value === currentRequestId) {
      isLoading.value = false;
      if (didLoad) focusRelevantControl();
    }
  }
};

const enterEditMode = () => {
  if (!canManage.value || isBusy.value) return;
  isKeyTypeMenuOpen.value = false;
  Object.assign(form, savedPix.value || emptyForm());
  confirmDelete.value = false;
  mode.value = 'edit';
  focusRelevantControl();
};

const cancelEdit = () => {
  isKeyTypeMenuOpen.value = false;
  if (!isConfigured.value) {
    close();
    return;
  }

  Object.assign(form, savedPix.value);
  confirmDelete.value = false;
  mode.value = 'preview';
  focusRelevantControl();
};

const saveConfiguration = async () => {
  if (!canManage.value || !isFormComplete.value || isBusy.value) return;

  isSaving.value = true;
  let didSave = false;
  try {
    const { data } = await WhatsmeowPixAPI.saveConfiguration(
      props.inboxId,
      normalizedPayload.value
    );
    applyConfiguration(data);
    didSave = true;
    useAlert(t('CONVERSATION.WHATSMEOW_PIX.SAVED'));
  } catch (error) {
    useAlert(
      apiErrorMessage(error, t('CONVERSATION.WHATSMEOW_PIX.SAVE_FAILED'))
    );
  } finally {
    isSaving.value = false;
    if (didSave) focusRelevantControl();
  }
};

const deleteConfiguration = async () => {
  if (!canManage.value || !isConfigured.value || isBusy.value) return;

  if (!confirmDelete.value) {
    confirmDelete.value = true;
    return;
  }

  isDeleting.value = true;
  let didDelete = false;
  try {
    const { data } = await WhatsmeowPixAPI.deleteConfiguration(props.inboxId);
    applyConfiguration(data);
    confirmDelete.value = false;
    didDelete = true;
    useAlert(t('CONVERSATION.WHATSMEOW_PIX.DELETED'));
  } catch (error) {
    useAlert(
      apiErrorMessage(error, t('CONVERSATION.WHATSMEOW_PIX.DELETE_FAILED'))
    );
  } finally {
    isDeleting.value = false;
    if (didDelete) focusRelevantControl();
  }
};

const sendPix = async () => {
  if (!canSend.value) return;

  const targetConversationId = activeConversationId.value;
  if (
    !targetConversationId ||
    openedConversationId.value !== targetConversationId
  ) {
    useAlert(t('CONVERSATION.WHATSMEOW_PIX.CONVERSATION_CHANGED'));
    dialogRef.value?.close();
    return;
  }

  isSending.value = true;
  let sentMessage = null;
  try {
    const { data } = await WhatsmeowPixAPI.send(targetConversationId, {});
    sentMessage = data?.payload || data;
  } catch (error) {
    useAlert(
      apiErrorMessage(error, t('CONVERSATION.WHATSMEOW_PIX.SEND_FAILED'))
    );
  } finally {
    isSending.value = false;
  }

  if (sentMessage) {
    emit('sent', sentMessage);
    dialogRef.value?.close();
  }
};

watch(
  () => props.isOpen,
  value => {
    requestId.value += 1;

    if (value) {
      previouslyFocusedElement.value = document.activeElement;
      openedConversationId.value = activeConversationId.value;
      confirmDelete.value = false;
      nextTick(() => {
        dialogRef.value?.open();
        loadConfiguration();
      });
    } else if (openedConversationId.value) {
      dialogRef.value?.close();
    }
  }
);

watch(activeConversationId, conversationId => {
  if (
    props.isOpen &&
    openedConversationId.value &&
    openedConversationId.value !== conversationId
  ) {
    useAlert(t('CONVERSATION.WHATSMEOW_PIX.CONVERSATION_CHANGED'));
    dialogRef.value?.close();
  }
});
</script>

<template>
  <Dialog
    ref="dialogRef"
    width="3xl"
    overflow-y-auto
    :show-cancel-button="false"
    :show-confirm-button="false"
    :prevent-close="isBusy"
    @close="handleDialogClose"
  >
    <div class="flex min-w-0 items-center gap-3">
      <div
        class="grid size-11 shrink-0 place-content-center rounded-xl bg-n-teal-3 text-n-teal-11"
      >
        <PixIcon class="size-6" />
      </div>
      <div class="min-w-0">
        <h3 class="m-0 truncate text-base font-semibold text-n-slate-12">
          {{ t('CONVERSATION.WHATSMEOW_PIX.TITLE') }}
        </h3>
        <p class="m-0 text-sm text-n-slate-11">
          {{ t('CONVERSATION.WHATSMEOW_PIX.SUBTITLE') }}
        </p>
      </div>
    </div>

    <div
      v-if="isLoading"
      class="flex min-h-64 items-center justify-center gap-2 text-sm text-n-slate-11"
      role="status"
    >
      <Icon icon="i-lucide-loader-circle" class="size-4 animate-spin" />
      <span>{{ t('CONVERSATION.WHATSMEOW_PIX.LOADING') }}</span>
    </div>

    <template v-else-if="isEditing">
      <div class="grid min-w-0 items-start gap-4 md:grid-cols-2">
        <fieldset
          class="m-0 grid min-w-0 content-start gap-4 rounded-2xl border border-n-weak bg-n-surface-1 p-4 shadow-sm"
          :disabled="!canManage || isBusy"
        >
          <div class="flex items-start gap-2.5">
            <div
              class="grid size-8 shrink-0 place-content-center rounded-lg bg-n-teal-3 text-n-teal-11"
            >
              <Icon icon="i-lucide-wallet-cards" class="size-4" />
            </div>
            <div class="min-w-0">
              <h4 class="m-0 text-sm font-semibold text-n-slate-12">
                {{ t('CONVERSATION.WHATSMEOW_PIX.CONFIGURATION') }}
              </h4>
              <p class="m-0 mt-1 text-xs leading-5 text-n-slate-11">
                {{
                  canManage
                    ? t('CONVERSATION.WHATSMEOW_PIX.CONFIGURATION_HINT')
                    : t('CONVERSATION.WHATSMEOW_PIX.READ_ONLY_HINT')
                }}
              </p>
            </div>
          </div>

          <div class="grid min-w-0 gap-1.5">
            <span
              id="whatsmeow-pix-key-type-label"
              class="text-sm font-medium text-n-slate-12"
            >
              {{ t('CONVERSATION.WHATSMEOW_PIX.KEY_TYPE') }}
            </span>
            <OnClickOutside @trigger="isKeyTypeMenuOpen = false">
              <div class="relative min-w-0" @focusout="handleKeyTypeFocusOut">
                <button
                  id="whatsmeow-pix-key-type"
                  ref="keyTypeInput"
                  type="button"
                  class="reset-base flex h-11 w-full min-w-0 items-center justify-between gap-3 rounded-xl border border-n-weak bg-n-alpha-1 px-3.5 text-left text-sm text-n-slate-12 shadow-sm transition-colors hover:border-n-teal-8 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-n-teal-9 disabled:cursor-not-allowed disabled:opacity-60"
                  :class="{ 'border-n-teal-9': isKeyTypeMenuOpen }"
                  :disabled="!canManage || isBusy"
                  :aria-expanded="isKeyTypeMenuOpen"
                  aria-haspopup="listbox"
                  aria-controls="whatsmeow-pix-key-type-options"
                  aria-labelledby="whatsmeow-pix-key-type-label whatsmeow-pix-key-type-value"
                  @click="toggleKeyTypeMenu"
                  @keydown.down.prevent="openKeyTypeMenu"
                  @keydown.up.prevent="openKeyTypeMenu"
                >
                  <span class="flex min-w-0 items-center gap-2.5">
                    <Icon
                      :icon="selectedKeyType?.icon"
                      class="size-4 shrink-0 text-n-teal-11"
                    />
                    <span id="whatsmeow-pix-key-type-value" class="truncate">
                      {{ selectedKeyType?.label }}
                    </span>
                  </span>
                  <Icon
                    icon="i-lucide-chevron-down"
                    class="size-4 shrink-0 text-n-slate-11 transition-transform duration-200"
                    :class="{ 'rotate-180': isKeyTypeMenuOpen }"
                  />
                </button>

                <Transition
                  enter-active-class="transition duration-150 ease-out motion-reduce:transition-none"
                  enter-from-class="-translate-y-1 opacity-0"
                  enter-to-class="translate-y-0 opacity-100"
                  leave-active-class="transition duration-100 ease-in motion-reduce:transition-none"
                  leave-from-class="translate-y-0 opacity-100"
                  leave-to-class="-translate-y-1 opacity-0"
                >
                  <div
                    v-if="isKeyTypeMenuOpen"
                    id="whatsmeow-pix-key-type-options"
                    ref="keyTypeMenu"
                    role="listbox"
                    :aria-label="t('CONVERSATION.WHATSMEOW_PIX.KEY_TYPE')"
                    class="absolute inset-x-0 top-full z-30 mt-2 grid gap-1 rounded-xl border border-n-weak bg-n-solid-1 p-1.5 shadow-xl"
                    @keydown="handleKeyTypeMenuKeydown"
                  >
                    <button
                      v-for="keyType in keyTypes"
                      :key="keyType.value"
                      type="button"
                      role="option"
                      :aria-selected="keyType.value === form.keyType"
                      class="reset-base flex w-full items-center gap-3 rounded-lg px-3 py-2.5 text-left text-sm transition-colors focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-teal-9"
                      :class="
                        keyType.value === form.keyType
                          ? 'bg-n-teal-3 font-medium text-n-teal-11'
                          : 'text-n-slate-12 hover:bg-n-alpha-2'
                      "
                      @click="selectKeyType(keyType.value)"
                    >
                      <Icon :icon="keyType.icon" class="size-4 shrink-0" />
                      <span class="min-w-0 flex-1 truncate">{{
                        keyType.label
                      }}</span>
                      <Icon
                        v-if="keyType.value === form.keyType"
                        icon="i-lucide-check"
                        class="size-4 shrink-0"
                      />
                    </button>
                  </div>
                </Transition>
              </div>
            </OnClickOutside>
          </div>

          <label class="grid min-w-0 gap-1" for="whatsmeow-pix-key">
            <span class="text-sm font-medium text-n-slate-12">
              {{ t('CONVERSATION.WHATSMEOW_PIX.KEY') }}
            </span>
            <input
              id="whatsmeow-pix-key"
              v-model="form.key"
              class="reset-base h-11 min-w-0 rounded-xl border border-n-weak bg-n-alpha-1 px-3.5 text-sm text-n-slate-12 shadow-sm outline-none transition-colors focus:border-n-teal-9 focus:ring-2 focus:ring-n-teal-9/20 disabled:cursor-not-allowed disabled:opacity-60"
              :type="inputType"
              :placeholder="keyPlaceholder"
              maxlength="255"
              autocomplete="off"
            />
          </label>

          <label class="grid min-w-0 gap-1" for="whatsmeow-pix-merchant-name">
            <span class="text-sm font-medium text-n-slate-12">
              {{ t('CONVERSATION.WHATSMEOW_PIX.MERCHANT_NAME') }}
            </span>
            <input
              id="whatsmeow-pix-merchant-name"
              v-model="form.merchantName"
              class="reset-base h-11 min-w-0 rounded-xl border border-n-weak bg-n-alpha-1 px-3.5 text-sm text-n-slate-12 shadow-sm outline-none transition-colors focus:border-n-teal-9 focus:ring-2 focus:ring-n-teal-9/20 disabled:cursor-not-allowed disabled:opacity-60"
              type="text"
              maxlength="100"
              :placeholder="
                t('CONVERSATION.WHATSMEOW_PIX.MERCHANT_PLACEHOLDER')
              "
              autocomplete="organization"
            />
          </label>

          <p
            v-if="!isConfigured"
            class="m-0 flex items-start gap-2 rounded-xl border border-n-teal-7 bg-n-teal-3 px-3 py-2.5 text-xs leading-5 text-n-teal-11"
          >
            <Icon icon="i-lucide-info" class="mt-0.5 size-3.5 shrink-0" />
            {{ t('CONVERSATION.WHATSMEOW_PIX.NOT_CONFIGURED') }}
          </p>
        </fieldset>

        <div
          class="grid min-w-0 content-start gap-4 rounded-2xl border border-n-weak bg-n-surface-1 p-4 shadow-sm"
        >
          <div class="flex items-start gap-2.5">
            <div
              class="grid size-8 shrink-0 place-content-center rounded-lg bg-n-teal-3 text-n-teal-11"
            >
              <Icon icon="i-lucide-eye" class="size-4" />
            </div>
            <div class="min-w-0">
              <h4 class="m-0 text-sm font-semibold text-n-slate-12">
                {{ t('CONVERSATION.WHATSMEOW_PIX.PREVIEW') }}
              </h4>
              <p class="m-0 mt-1 text-xs leading-5 text-n-slate-11">
                {{ t('CONVERSATION.WHATSMEOW_PIX.PREVIEW_HINT') }}
              </p>
            </div>
          </div>
          <WhatsmeowPixCard :pix="previewPix" standalone />
          <p class="m-0 text-xs leading-5 text-n-slate-10">
            {{ t('CONVERSATION.WHATSMEOW_PIX.DELIVERY_NOTE') }}
          </p>
        </div>
      </div>

      <div
        v-if="confirmDelete"
        class="flex flex-wrap items-center justify-between gap-3 rounded-lg bg-n-ruby-3 px-4 py-3"
      >
        <p class="m-0 text-sm text-n-ruby-12">
          {{ t('CONVERSATION.WHATSMEOW_PIX.DELETE_CONFIRMATION') }}
        </p>
        <div class="flex gap-2">
          <NextButton
            type="button"
            :label="t('CONVERSATION.WHATSMEOW_PIX.CANCEL')"
            slate
            ghost
            sm
            @click="confirmDelete = false"
          />
          <NextButton
            type="button"
            :label="t('CONVERSATION.WHATSMEOW_PIX.CONFIRM_DELETE')"
            ruby
            sm
            :is-loading="isDeleting"
            @click="deleteConfiguration"
          />
        </div>
      </div>

      <div class="flex flex-wrap items-center justify-between gap-3">
        <NextButton
          v-if="canManage && isConfigured"
          type="button"
          :label="t('CONVERSATION.WHATSMEOW_PIX.DELETE_CONFIGURATION')"
          icon="i-lucide-trash-2"
          ruby
          ghost
          sm
          :disabled="isBusy"
          @click="deleteConfiguration"
        />
        <span v-else />
        <div class="flex flex-wrap justify-end gap-2">
          <NextButton
            ref="closeButton"
            type="button"
            :label="t('CONVERSATION.WHATSMEOW_PIX.CANCEL')"
            slate
            ghost
            :disabled="isBusy"
            @click="cancelEdit"
          />
          <NextButton
            v-if="canManage"
            type="button"
            :label="t('CONVERSATION.WHATSMEOW_PIX.SAVE_CONFIGURATION')"
            :disabled="!isFormComplete || isBusy"
            :is-loading="isSaving"
            @click="saveConfiguration"
          />
        </div>
      </div>
    </template>

    <template v-else>
      <div class="mx-auto grid w-full min-w-0 max-w-md gap-4">
        <div>
          <h4 class="m-0 text-sm font-semibold text-n-slate-12">
            {{ t('CONVERSATION.WHATSMEOW_PIX.PREVIEW') }}
          </h4>
          <p class="m-0 mt-1 text-xs text-n-slate-11">
            {{ t('CONVERSATION.WHATSMEOW_PIX.PREVIEW_HINT') }}
          </p>
        </div>
        <WhatsmeowPixCard :pix="previewPix" standalone />
        <p class="m-0 text-xs text-n-slate-10">
          {{ t('CONVERSATION.WHATSMEOW_PIX.DELIVERY_NOTE') }}
        </p>
      </div>

      <div class="flex flex-wrap items-center justify-end gap-2">
        <NextButton
          ref="closeButton"
          type="button"
          :label="t('CONVERSATION.WHATSMEOW_PIX.CANCEL')"
          slate
          ghost
          :disabled="isBusy"
          @click="close"
        />
        <NextButton
          v-if="canManage"
          type="button"
          :label="t('CONVERSATION.WHATSMEOW_PIX.EDIT_CONFIGURATION')"
          icon="i-lucide-pencil"
          slate
          faded
          :disabled="isBusy"
          @click="enterEditMode"
        />
        <NextButton
          ref="sendButton"
          type="button"
          autofocus
          :label="t('CONVERSATION.WHATSMEOW_PIX.SEND')"
          icon="i-lucide-send"
          :disabled="!canSend"
          :is-loading="isSending"
          @click="sendPix"
        />
      </div>
    </template>
  </Dialog>
</template>
