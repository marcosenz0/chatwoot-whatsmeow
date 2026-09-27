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
const keySummary = computed(() => `${keyTypeLabel.value}: ${displayKey.value}`);

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
    class="w-full min-w-0 overflow-hidden rounded-xl border border-n-teal-7 bg-n-teal-3"
    :class="{
      'shadow-sm': standalone,
    }"
  >
    <div class="flex items-center gap-3 px-4 py-3.5">
      <div
        class="grid size-11 shrink-0 place-content-center rounded-full bg-n-teal-5 text-n-teal-11"
      >
        <PixIcon class="size-6" />
      </div>
      <div class="min-w-0 flex-1">
        <p class="m-0 truncate text-sm font-semibold text-n-slate-12">
          {{ displayMerchantName }}
        </p>
        <p class="m-0 mt-1 break-all text-sm text-n-slate-11">
          {{ keySummary }}
        </p>
      </div>
    </div>

    <button
      type="button"
      class="flex w-full items-center justify-center gap-2 border-t border-n-teal-7 bg-n-teal-4 px-4 py-3 text-sm font-semibold text-n-teal-11 transition-colors hover:bg-n-teal-5 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-[-2px] focus-visible:outline-n-teal-9 disabled:cursor-not-allowed disabled:opacity-50"
      :disabled="!pixKey"
      @click.stop="copyPixKey"
    >
      <Icon icon="i-lucide-copy" class="size-4" />
      <span>{{ t('CONVERSATION.WHATSMEOW_PIX.COPY_KEY') }}</span>
    </button>
  </div>
</template>
