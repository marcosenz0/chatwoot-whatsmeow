<script setup>
import { computed } from 'vue';
import { useIntegrationHook } from 'dashboard/composables/useIntegrationHook';
import { useBranding } from 'shared/composables/useBranding';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'next/icon/Icon.vue';

const props = defineProps({
  integrationId: {
    type: String,
    required: true,
  },
});

const emit = defineEmits([
  'add',
  'delete',
  'removeProvider',
  'setPrimaryProvider',
]);

const { integration, hasConnectedHooks } = useIntegrationHook(
  props.integrationId
);

const { replaceInstallationName } = useBranding();
const { t } = useI18n();

const logoFile = computed(
  () => integration.value?.logo || `${props.integrationId}.png`
);
const darkLogoFile = computed(() =>
  logoFile.value.replace(/(\.[^.]+)$/, '-dark$1')
);

const isAudioTranscription = computed(
  () => props.integrationId === 'audio_transcription'
);

const audioProviderCards = computed(() => [
  {
    id: 'openai',
    title: t('INTEGRATION_APPS.AUDIO_TRANSCRIPTION.OPENAI_TITLE'),
    description: t('INTEGRATION_APPS.AUDIO_TRANSCRIPTION.OPENAI_DESCRIPTION'),
    button: t('INTEGRATION_APPS.AUDIO_TRANSCRIPTION.OPENAI_BUTTON'),
    logo: 'openai.png',
    darkLogo: 'openai-dark.png',
  },
  {
    id: 'groq',
    title: t('INTEGRATION_APPS.AUDIO_TRANSCRIPTION.GROQ_TITLE'),
    description: t('INTEGRATION_APPS.AUDIO_TRANSCRIPTION.GROQ_DESCRIPTION'),
    button: t('INTEGRATION_APPS.AUDIO_TRANSCRIPTION.GROQ_BUTTON'),
    icon: 'i-lucide-zap',
  },
]);

const audioHook = computed(() => integration.value?.hooks?.[0]);
const audioSettings = computed(() => audioHook.value?.settings || {});

const providerLabels = {
  openai: 'OpenAI',
  groq: 'Groq',
};

const providerHasKey = provider =>
  Boolean(audioSettings.value?.[`${provider}_api_key`]);

const providerIsPrimary = provider =>
  providerHasKey(provider) && audioSettings.value.provider === provider;

const providerState = provider => {
  if (!providerHasKey(provider)) {
    return '';
  }

  return providerIsPrimary(provider)
    ? t('INTEGRATION_APPS.AUDIO_TRANSCRIPTION.PRIMARY_BADGE')
    : t('INTEGRATION_APPS.AUDIO_TRANSCRIPTION.FALLBACK_BADGE');
};

const connectAudioProvider = provider => {
  emit('add', provider);
};

const removeAudioProvider = provider => {
  emit('removeProvider', {
    hook: audioHook.value,
    provider,
    providerName: providerLabels[provider],
  });
};

const setPrimaryAudioProvider = provider => {
  emit('setPrimaryProvider', {
    hook: audioHook.value,
    provider,
  });
};
</script>

<template>
  <div
    class="outline outline-n-container outline-1 bg-n-card rounded-xl flex-grow overflow-auto p-4"
  >
    <div
      class="flex items-center justify-center"
      :class="{ 'items-start': isAudioTranscription }"
    >
      <div class="flex h-16 w-16 items-center justify-center">
        <img
          :src="`/dashboard/images/integrations/${logoFile}`"
          class="max-w-full rounded-md border border-n-weak shadow-sm block dark:hidden bg-n-alpha-3 dark:bg-n-alpha-2"
        />
        <img
          :src="`/dashboard/images/integrations/${darkLogoFile}`"
          class="max-w-full rounded-md border border-n-weak shadow-sm hidden dark:block bg-n-alpha-3 dark:bg-n-alpha-2"
        />
      </div>
      <div class="flex flex-col justify-center m-0 mx-4 flex-1">
        <h3 class="mb-1 text-heading-1 text-n-slate-12">
          {{ integration.name }}
        </h3>
        <p class="text-n-slate-11 text-body-main">
          {{ replaceInstallationName(integration.description) }}
        </p>
      </div>
      <div
        v-if="!isAudioTranscription"
        class="flex justify-center items-center mb-0 w-[15%]"
      >
        <div v-if="hasConnectedHooks">
          <div @click="$emit('delete', integration.hooks[0])">
            <Button
              ruby
              faded
              :label="$t('INTEGRATION_APPS.DISCONNECT.BUTTON_TEXT')"
            />
          </div>
        </div>
        <div v-else>
          <Button
            blue
            faded
            :label="$t('INTEGRATION_APPS.CONNECT.BUTTON_TEXT')"
            @click="$emit('add')"
          />
        </div>
      </div>
    </div>
    <div
      v-if="isAudioTranscription"
      class="grid grid-cols-1 gap-3 mt-5 md:grid-cols-2"
    >
      <div
        v-for="provider in audioProviderCards"
        :key="provider.id"
        class="flex flex-col justify-between gap-4 p-4 rounded-lg outline outline-1 outline-n-container bg-n-alpha-2"
      >
        <div class="flex items-start gap-3">
          <div
            class="grid size-11 shrink-0 place-items-center rounded-lg border border-n-weak bg-n-alpha-3"
          >
            <template v-if="provider.logo">
              <img
                :src="`/dashboard/images/integrations/${provider.logo}`"
                class="size-7 block dark:hidden"
              />
              <img
                :src="`/dashboard/images/integrations/${provider.darkLogo}`"
                class="size-7 hidden dark:block"
              />
            </template>
            <Icon v-else :icon="provider.icon" class="size-5 text-n-blue-10" />
          </div>
          <div class="min-w-0">
            <h4 class="mb-1 text-sm font-medium text-n-slate-12">
              {{ provider.title }}
            </h4>
            <p class="text-sm text-n-slate-11">
              {{ provider.description }}
            </p>
            <div v-if="providerHasKey(provider.id)" class="mt-2">
              <span
                class="inline-flex items-center rounded-md bg-n-teal-3 px-2 py-0.5 text-xs font-medium text-n-teal-11"
              >
                {{ providerState(provider.id) }}
              </span>
            </div>
          </div>
        </div>
        <div class="flex items-center gap-2">
          <Button
            faded
            blue
            size="sm"
            :label="
              providerHasKey(provider.id)
                ? $t('INTEGRATION_APPS.CONFIGURE')
                : provider.button
            "
            @click="connectAudioProvider(provider.id)"
          />
          <Button
            v-if="providerHasKey(provider.id)"
            faded
            ruby
            size="sm"
            :label="$t('INTEGRATION_APPS.DISCONNECT.BUTTON_TEXT')"
            @click="removeAudioProvider(provider.id)"
          />
          <Button
            v-if="
              providerHasKey(provider.id) && !providerIsPrimary(provider.id)
            "
            faded
            slate
            size="sm"
            :label="
              $t('INTEGRATION_APPS.AUDIO_TRANSCRIPTION.MAKE_PRIMARY_BUTTON')
            "
            @click="setPrimaryAudioProvider(provider.id)"
          />
        </div>
      </div>
    </div>
  </div>
</template>
