<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import Icon from 'next/icon/Icon.vue';
import PixIcon from 'next/icon/PixIcon.vue';

const props = defineProps({
  pix: {
    type: Object,
    default: () => ({}),
  },
  standalone: {
    type: Boolean,
    default: false,
  },
});

const { t } = useI18n();

const keyType = computed(() => props.pix.keyType || props.pix.key_type || '');
const pixKey = computed(() => String(props.pix.key || '').trim());
const merchantName = computed(() =>
  String(props.pix.merchantName || props.pix.merchant_name || '').trim()
);

const keyTypeLabel = computed(() => {
  const labels = {
    PHONE: t('CONVERSATION.WHATSMEOW_PIX.KEY_TYPES.PHONE'),
    CPF: t('CONVERSATION.WHATSMEOW_PIX.KEY_TYPES.CPF'),
    EMAIL: t('CONVERSATION.WHATSMEOW_PIX.KEY_TYPES.EMAIL'),
    EVP: t('CONVERSATION.WHATSMEOW_PIX.KEY_TYPES.EVP'),
  };
  return labels[keyType.value] || t('CONVERSATION.WHATSMEOW_PIX.KEY');
});

const displayKey = computed(
  () => pixKey.value || t('CONVERSATION.WHATSMEOW_PIX.PREVIEW_KEY')
);

const displayMerchantName = computed(
  () => merchantName.value || t('CONVERSATION.WHATSMEOW_PIX.PREVIEW_MERCHANT')
);

const copyPixKey = async () => {
  if (!pixKey.value) return;

  try {
    await navigator.clipboard.writeText(pixKey.value);
    useAlert(t('CONVERSATION.WHATSMEOW_PIX.COPIED'));
  } catch {
    useAlert(t('CONVERSATION.WHATSMEOW_PIX.COPY_FAILED'));
  }
};
</script>

<template>
  <div
    class="w-full overflow-hidden"
    :class="{
      'rounded-xl border border-n-weak bg-n-solid-1': standalone,
    }"
  >
    <div class="flex items-start gap-3 bg-n-teal-9/10 p-4">
      <div
        class="grid size-10 shrink-0 place-content-center rounded-full bg-n-teal-9 text-white"
      >
        <PixIcon class="size-5" />
      </div>
      <div class="min-w-0 flex-1">
        <p class="m-0 text-sm font-semibold text-n-slate-12">
          {{ t('CONVERSATION.WHATSMEOW_PIX.CARD_TITLE') }}
        </p>
        <p class="m-0 mt-0.5 truncate text-sm text-n-slate-11">
          {{ displayMerchantName }}
        </p>
      </div>
    </div>

    <div class="grid gap-1 px-4 py-3">
      <p class="m-0 text-xs font-medium text-n-slate-10">
        {{ keyTypeLabel }}
      </p>
      <p class="m-0 break-all font-mono text-sm text-n-slate-12">
        {{ displayKey }}
      </p>
    </div>

    <button
      type="button"
      class="flex w-full items-center justify-center gap-2 border-t border-n-weak px-4 py-2.5 text-sm font-semibold text-n-teal-11 hover:bg-n-alpha-2 disabled:cursor-not-allowed disabled:opacity-50"
      :disabled="!pixKey"
      @click.stop="copyPixKey"
    >
      <Icon icon="i-lucide-copy" class="size-4" />
      <span>{{ t('CONVERSATION.WHATSMEOW_PIX.COPY_KEY') }}</span>
    </button>
  </div>
</template>
