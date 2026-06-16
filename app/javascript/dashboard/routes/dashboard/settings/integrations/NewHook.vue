<!-- eslint-disable vue/v-slot-style -->
<script>
import { mapGetters } from 'vuex';
import { useAlert } from 'dashboard/composables';
import { useIntegrationHook } from 'dashboard/composables/useIntegrationHook';
import { FormKit } from '@formkit/vue';
import { useBranding } from 'shared/composables/useBranding';

import NextButton from 'dashboard/components-next/button/Button.vue';

export default {
  components: {
    FormKit,
    NextButton,
  },
  props: {
    integrationId: {
      type: String,
      required: true,
    },
    initialProvider: {
      type: String,
      default: '',
    },
  },
  emits: ['close'],
  setup(props) {
    const { integration, isHookTypeInbox } = useIntegrationHook(
      props.integrationId
    );
    const { replaceInstallationName } = useBranding();

    return { integration, isHookTypeInbox, replaceInstallationName };
  },
  data() {
    return {
      endPoint: '',
      alertMessage: '',
      values: this.initialValues(),
    };
  },
  computed: {
    ...mapGetters({
      uiFlags: 'integrations/getUIFlags',
      dialogFlowEnabledInboxes: 'inboxes/dialogFlowEnabledInboxes',
    }),
    inboxes() {
      return this.dialogFlowEnabledInboxes
        .filter(inbox => {
          if (!this.isIntegrationDialogflow) {
            return true;
          }
          return !this.connectedDialogflowInboxIds.includes(inbox.id);
        })
        .map(inbox => ({ label: inbox.name, value: inbox.id }));
    },

    connectedDialogflowInboxIds() {
      if (!this.isIntegrationDialogflow) {
        return [];
      }
      return this.integration.hooks.map(hook => hook.inbox?.id);
    },
    existingAudioHook() {
      if (!this.isAudioTranscription) {
        return null;
      }

      return this.integration.hooks?.[0] || null;
    },
    existingAudioSettings() {
      return this.existingAudioHook?.settings || {};
    },
    audioProvider() {
      return this.initialProvider || this.existingAudioSettings.provider || '';
    },
    audioProviderName() {
      return this.audioProvider === 'groq' ? 'Groq' : 'OpenAI';
    },
    audioProviderKeyName() {
      return `${this.audioProvider}_api_key`;
    },
    hasSavedAudioProviderKey() {
      return Boolean(this.existingAudioSettings[this.audioProviderKeyName]);
    },
    formItems() {
      if (this.isAudioTranscription) {
        return this.audioProviderFormItems;
      }

      return this.integration.settings_form_schema;
    },
    audioProviderFormItems() {
      const fieldNames = [
        this.audioProviderKeyName,
        `${this.audioProvider}_transcription_model`,
        `${this.audioProvider}_summary_model`,
        'language',
      ];

      return this.integration.settings_form_schema
        .filter(item => fieldNames.includes(item.name))
        .map(item => this.audioFormItem(item));
    },
    isIntegrationDialogflow() {
      return this.integration.id === 'dialogflow';
    },
    isAudioTranscription() {
      return this.integration.id === 'audio_transcription';
    },
    modalTitle() {
      if (!this.isAudioTranscription || !this.initialProvider) {
        return this.integration.name;
      }

      const actionKey = this.hasSavedAudioProviderKey
        ? 'CONFIGURE_PROVIDER_TITLE'
        : 'CONNECT_PROVIDER_TITLE';

      return this.$t(`INTEGRATION_APPS.AUDIO_TRANSCRIPTION.${actionKey}`, {
        provider: this.audioProviderName,
      });
    },
    modalDescription() {
      if (!this.isAudioTranscription) {
        return this.replaceInstallationName(this.integration.short_description);
      }

      return this.initialProvider === 'groq'
        ? this.$t('INTEGRATION_APPS.AUDIO_TRANSCRIPTION.MODAL_DESCRIPTION_GROQ')
        : this.$t(
            'INTEGRATION_APPS.AUDIO_TRANSCRIPTION.MODAL_DESCRIPTION_OPENAI'
          );
    },
    submitButtonLabel() {
      if (this.integration.id === 'openai' && this.uiFlags.isCreatingHook) {
        return this.$t('INTEGRATION_APPS.ADD.FORM.VALIDATING_OPENAI');
      }

      if (this.isAudioTranscription && this.hasSavedAudioProviderKey) {
        return this.$t('INTEGRATION_APPS.ADD.FORM.SAVE');
      }

      return this.$t('INTEGRATION_APPS.ADD.FORM.SUBMIT');
    },
  },
  methods: {
    initialValues() {
      if (
        this.integrationId !== 'audio_transcription' ||
        !this.initialProvider
      ) {
        return {};
      }

      const provider = this.initialProvider;
      const settings = this.integration?.hooks?.[0]?.settings || {};
      const values = {
        language: settings.language || 'pt',
      };

      const providerFields = [
        `${provider}_transcription_model`,
        `${provider}_summary_model`,
      ];

      providerFields.forEach(fieldName => {
        values[fieldName] =
          settings[fieldName] || this.defaultValueForField(fieldName);
      });

      values[`${provider}_api_key`] = '';

      return values;
    },
    defaultValueForField(fieldName) {
      return (
        this.integration?.settings_form_schema?.find(
          item => item.name === fieldName
        )?.default || ''
      );
    },
    audioFormItem(item) {
      if (item.name !== this.audioProviderKeyName) {
        return item;
      }

      return {
        ...item,
        validation: this.hasSavedAudioProviderKey ? '' : 'required',
        placeholder: this.hasSavedAudioProviderKey
          ? this.$t(
              'INTEGRATION_APPS.AUDIO_TRANSCRIPTION.SAVED_KEY_PLACEHOLDER'
            )
          : '',
        help: this.hasSavedAudioProviderKey
          ? this.$t('INTEGRATION_APPS.AUDIO_TRANSCRIPTION.SAVED_KEY_HELP')
          : item.help,
      };
    },
    onClose() {
      this.$emit('close');
    },
    fallbackProviderFor(primaryProvider, settings) {
      const otherProvider = primaryProvider === 'groq' ? 'openai' : 'groq';
      return settings[`${otherProvider}_api_key`] ? otherProvider : 'none';
    },
    buildAudioTranscriptionHookPayload() {
      const existingSettings = { ...this.existingAudioSettings };
      const settings = { ...existingSettings };

      Object.keys(this.values).forEach(key => {
        if (key === this.audioProviderKeyName && !this.values[key]) {
          return;
        }

        settings[key] = this.values[key];
      });

      settings.provider = this.hasSavedAudioProviderKey
        ? existingSettings.provider || this.audioProvider
        : this.audioProvider;
      settings.fallback_provider = this.fallbackProviderFor(
        settings.provider,
        settings
      );

      return {
        app_id: this.integration.id,
        settings,
      };
    },
    buildHookPayload() {
      if (this.isAudioTranscription) {
        return this.buildAudioTranscriptionHookPayload();
      }

      const hookPayload = {
        app_id: this.integration.id,
        settings: {},
      };

      hookPayload.settings = Object.keys(this.values).reduce((acc, key) => {
        if (key !== 'inbox') {
          acc[key] = this.values[key];
        }
        return acc;
      }, {});

      this.formItems.forEach(item => {
        if (item.validation?.includes('JSON')) {
          hookPayload.settings[item.name] = JSON.parse(
            hookPayload.settings[item.name]
          );
        }
      });

      if (this.isHookTypeInbox && this.values.inbox) {
        hookPayload.inbox_id = this.values.inbox;
      }

      return hookPayload;
    },
    async submitForm() {
      try {
        const hookPayload = this.buildHookPayload();

        if (this.isAudioTranscription && this.existingAudioHook?.id) {
          await this.$store.dispatch('integrations/updateHook', {
            hookId: this.existingAudioHook.id,
            hookData: hookPayload,
          });
        } else {
          await this.$store.dispatch('integrations/createHook', hookPayload);
        }

        this.alertMessage = this.$t('INTEGRATION_APPS.ADD.API.SUCCESS_MESSAGE');
        this.onClose();
      } catch (error) {
        const errorMessage = error?.response?.data?.message;
        this.alertMessage =
          errorMessage || this.$t('INTEGRATION_APPS.ADD.API.ERROR_MESSAGE');
      } finally {
        useAlert(this.alertMessage);
      }
    },
  },
  watch: {
    initialProvider() {
      this.values = this.initialValues();
    },
  },
};
</script>

<template>
  <div class="flex flex-col h-auto overflow-auto integration-hooks">
    <woot-modal-header
      :header-title="modalTitle"
      :header-content="modalDescription"
    />
    <FormKit
      v-model="values"
      type="form"
      form-class="w-full grid gap-4"
      :submit-attrs="{
        inputClass: 'hidden',
        wrapperClass: 'hidden',
      }"
      :incomplete-message="false"
      @submit="submitForm"
    >
      <FormKit v-for="item in formItems" :key="item.name" v-bind="item" />
      <FormKit
        v-if="isHookTypeInbox"
        :options="inboxes"
        type="select"
        name="inbox"
        input-class="reset-base"
        :placeholder="$t('INTEGRATION_APPS.ADD.FORM.INBOX.LABEL')"
        :label="$t('INTEGRATION_APPS.ADD.FORM.INBOX.PLACEHOLDER')"
        validation="required"
        validation-name="Inbox"
      />
      <div class="flex flex-row justify-end w-full gap-2 px-0 py-2">
        <NextButton
          faded
          slate
          type="reset"
          :label="$t('INTEGRATION_APPS.ADD.FORM.CANCEL')"
          @click.prevent="onClose"
        />
        <NextButton
          type="submit"
          :label="submitButtonLabel"
          :is-loading="uiFlags.isCreatingHook"
        />
      </div>
    </FormKit>
  </div>
</template>

<style lang="css">
.formkit-outer {
  @apply mt-2;
}

.formkit-form > .formkit-wrapper > ul.formkit-messages {
  @apply hidden;
}

.formkit-form .formkit-help {
  @apply text-n-slate-10 text-sm font-normal mt-2 w-full;
}

/* equivalent of .reset-base */
.formkit-input {
  margin-bottom: 0px !important;
}

[data-invalid] .formkit-message {
  @apply text-n-ruby-9 block text-xs font-normal my-1 w-full;
}

.formkit-outer[data-type='checkbox'] .formkit-wrapper {
  @apply flex items-center gap-2 px-0.5;
}

.formkit-messages {
  @apply list-none m-0 p-0;
}

.formkit-actions {
  @apply hidden;
}
</style>
