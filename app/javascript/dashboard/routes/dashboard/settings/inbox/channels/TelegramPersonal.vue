<script setup>
import { ref } from 'vue';
import { useStore } from 'vuex';
import { useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import NextButton from 'dashboard/components-next/button/Button.vue';
import PageHeader from '../../SettingsSubPageHeader.vue';
import TelegramPersonalPairing from '../components/TelegramPersonalPairing.vue';

const store = useStore();
const router = useRouter();
const { t } = useI18n();
const name = ref('');
const phone = ref('');
const inboxId = ref(null);
const busy = ref(false);
const create = async () => {
  busy.value = true;
  try {
    const inbox = await store.dispatch('inboxes/createChannel', {
      name: name.value.trim(),
      lock_to_single_conversation: true,
      channel: { type: 'telegram_personal', phone_number: phone.value.trim() },
    });
    inboxId.value = inbox.id;
  } catch (error) {
    useAlert(
      error.message || t('TELEGRAM_PERSONAL.ERRORS.service_unavailable')
    );
  } finally {
    busy.value = false;
  }
};
const finish = () =>
  router.replace({
    name: 'settings_inboxes_add_agents',
    params: { page: 'new', inbox_id: inboxId.value },
  });
</script>

<template>
  <div class="h-full w-full p-6 col-span-6">
    <PageHeader
      :header-title="t('TELEGRAM_PERSONAL.TITLE')"
      :header-content="t('TELEGRAM_PERSONAL.DESCRIPTION')"
    />
    <form
      v-if="!inboxId"
      class="flex max-w-lg flex-col gap-4"
      @submit.prevent="create"
    >
      <label>
        {{ t('TELEGRAM_PERSONAL.NAME') }}
        <input v-model="name" required type="text" maxlength="100" />
      </label>
      <label>
        {{ t('TELEGRAM_PERSONAL.PHONE') }}
        <input
          v-model="phone"
          required
          type="tel"
          pattern="\+[1-9][0-9]{7,14}"
          :placeholder="t('TELEGRAM_PERSONAL.PHONE_PLACEHOLDER')"
        />
      </label>
      <NextButton
        type="submit"
        :label="t('TELEGRAM_PERSONAL.CREATE')"
        :is-loading="busy"
      />
    </form>
    <TelegramPersonalPairing v-else :inbox-id="inboxId" @connected="finish" />
  </div>
</template>
