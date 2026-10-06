<script setup>
import { reactive, ref, watch } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import NextButton from 'dashboard/components-next/button/Button.vue';
import TelegramPersonalPairing from '../components/TelegramPersonalPairing.vue';

const props = defineProps({ inbox: { type: Object, required: true } });
const store = useStore();
const { t } = useI18n();
const options = [
  'ignore_groups',
  'ignore_channels',
  'hide_groups',
  'hide_channels',
];
const settings = reactive({});
watch(
  () => props.inbox,
  inbox => {
    options.forEach(option => {
      settings[option] = !!inbox[option];
    });
  },
  { immediate: true }
);
const busy = ref(false);
const save = async () => {
  busy.value = true;
  try {
    await store.dispatch('inboxes/updateInbox', {
      id: props.inbox.id,
      channel: { ...settings },
    });
    useAlert(t('TELEGRAM_PERSONAL.SAVED'));
  } catch {
    useAlert(t('TELEGRAM_PERSONAL.ERRORS.service_unavailable'));
  } finally {
    busy.value = false;
  }
};
</script>

<template>
  <div class="flex flex-col gap-6">
    <TelegramPersonalPairing :key="inbox.id" :inbox-id="inbox.id" />
    <form class="flex max-w-lg flex-col gap-3 p-6" @submit.prevent="save">
      <h3 class="text-lg font-medium text-n-slate-12">
        {{ t('TELEGRAM_PERSONAL.FILTERS_TITLE') }}
      </h3>
      <label
        v-for="option in options"
        :key="option"
        class="flex flex-col gap-1"
      >
        <span class="flex items-center gap-2">
          <input
            v-model="settings[option]"
            type="checkbox"
            class="reset-base"
          />
          {{ t(`TELEGRAM_PERSONAL.FILTERS.${option}.LABEL`) }}
        </span>
        <span class="text-sm text-n-slate-11">
          {{ t(`TELEGRAM_PERSONAL.FILTERS.${option}.DESCRIPTION`) }}
        </span>
      </label>
      <NextButton
        type="submit"
        :label="t('TELEGRAM_PERSONAL.SAVE')"
        :is-loading="busy"
      />
    </form>
  </div>
</template>
