<script>
import { isEmptyObject } from '../../../../helper/commons';
import { mapGetters } from 'vuex';
import { useAlert } from 'dashboard/composables';
import { useIntegrationHook } from 'dashboard/composables/useIntegrationHook';
import NewHook from './NewHook.vue';
import SingleIntegrationHooks from './SingleIntegrationHooks.vue';
import MultipleIntegrationHooks from './MultipleIntegrationHooks.vue';
import SettingsLayout from '../SettingsLayout.vue';
import BaseSettingsHeader from '../components/BaseSettingsHeader.vue';

export default {
  components: {
    NewHook,
    SingleIntegrationHooks,
    MultipleIntegrationHooks,
    SettingsLayout,
    BaseSettingsHeader,
  },
  props: {
    integrationId: {
      type: [String, Number],
      required: true,
    },
  },
  setup(props) {
    const { integrationId } = props;

    const {
      integration,
      isIntegrationMultiple,
      isIntegrationSingle,
      isHookTypeInbox,
    } = useIntegrationHook(integrationId);

    return {
      integration,
      isIntegrationMultiple,
      isIntegrationSingle,
      isHookTypeInbox,
    };
  },
  data() {
    return {
      loading: {},
      showAddHookModal: false,
      showDeleteConfirmationPopup: false,
      selectedHook: {},
      selectedProvider: '',
      selectedProviderForRemoval: '',
      selectedProviderNameForRemoval: '',
      alertMessage: '',
    };
  },
  computed: {
    ...mapGetters({ uiFlags: 'integrations/getUIFlags' }),
    showIntegrationHooks() {
      return !this.uiFlags.isFetching && !isEmptyObject(this.integration);
    },
    showAddButton() {
      return this.showIntegrationHooks && this.isIntegrationMultiple;
    },
    deleteTitle() {
      return this.isHookTypeInbox
        ? this.$t('INTEGRATION_APPS.DELETE.TITLE.INBOX')
        : this.$t('INTEGRATION_APPS.DELETE.TITLE.ACCOUNT');
    },
    deleteMessage() {
      return this.isHookTypeInbox
        ? this.$t('INTEGRATION_APPS.DELETE.MESSAGE.INBOX')
        : this.$t('INTEGRATION_APPS.DELETE.MESSAGE.ACCOUNT');
    },
    confirmText() {
      return this.isHookTypeInbox
        ? this.$t('INTEGRATION_APPS.DELETE.CONFIRM_BUTTON_TEXT.INBOX')
        : this.$t('INTEGRATION_APPS.DELETE.CONFIRM_BUTTON_TEXT.ACCOUNT');
    },
    cancelText() {
      return this.$t('INTEGRATION_APPS.DELETE.CANCEL_BUTTON_TEXT');
    },
    isAudioTranscription() {
      return this.integrationId === 'audio_transcription';
    },
  },
  mounted() {
    this.$store.dispatch('integrations/get');
  },
  methods: {
    openAddHookModal(provider = '') {
      this.selectedProvider = provider;
      this.showAddHookModal = true;
    },
    hideAddHookModal() {
      this.showAddHookModal = false;
      this.selectedProvider = '';
    },
    openDeletePopup(response) {
      this.showDeleteConfirmationPopup = true;
      this.selectedHook = response;
    },
    openProviderDeletePopup({ hook, provider, providerName }) {
      this.showDeleteConfirmationPopup = true;
      this.selectedHook = hook;
      this.selectedProviderForRemoval = provider;
      this.selectedProviderNameForRemoval = providerName;
    },
    closeDeletePopup() {
      this.showDeleteConfirmationPopup = false;
      this.selectedProviderForRemoval = '';
      this.selectedProviderNameForRemoval = '';
    },
    nextProviderSettingsAfterRemoval() {
      const provider = this.selectedProviderForRemoval;
      const otherProvider = provider === 'openai' ? 'groq' : 'openai';
      const settings = { ...(this.selectedHook.settings || {}) };

      delete settings[`${provider}_api_key`];

      if (!settings[`${otherProvider}_api_key`]) {
        return null;
      }

      settings.provider = otherProvider;
      settings.fallback_provider = 'none';
      return settings;
    },
    fallbackProviderFor(primaryProvider, settings) {
      const otherProvider = primaryProvider === 'openai' ? 'groq' : 'openai';
      return settings[`${otherProvider}_api_key`] ? otherProvider : 'none';
    },
    async setPrimaryAudioProvider({ hook, provider }) {
      const settings = {
        ...(hook.settings || {}),
        provider,
      };
      settings.fallback_provider = this.fallbackProviderFor(provider, settings);

      try {
        await this.$store.dispatch('integrations/updateHook', {
          hookId: hook.id,
          hookData: {
            settings,
          },
        });
        this.alertMessage = this.$t('INTEGRATION_APPS.ADD.API.SUCCESS_MESSAGE');
      } catch (error) {
        const errorMessage = error?.response?.data?.message;
        this.alertMessage =
          errorMessage || this.$t('INTEGRATION_APPS.ADD.API.ERROR_MESSAGE');
      } finally {
        useAlert(this.alertMessage);
      }
    },
    async disconnectAudioProvider() {
      const nextSettings = this.nextProviderSettingsAfterRemoval();

      if (!nextSettings) {
        await this.$store.dispatch('integrations/deleteHook', {
          hookId: this.selectedHook.id,
          appId: this.selectedHook.app_id,
        });
        return;
      }

      await this.$store.dispatch('integrations/updateHook', {
        hookId: this.selectedHook.id,
        hookData: {
          settings: nextSettings,
        },
      });
    },
    async confirmDeletion() {
      try {
        if (this.isAudioTranscription && this.selectedProviderForRemoval) {
          await this.disconnectAudioProvider();
        } else {
          await this.$store.dispatch('integrations/deleteHook', {
            hookId: this.selectedHook.id,
            appId: this.selectedHook.app_id,
          });
        }
        this.alertMessage = this.$t(
          'INTEGRATION_APPS.DELETE.API.SUCCESS_MESSAGE'
        );
        this.closeDeletePopup();
      } catch (error) {
        const errorMessage = error?.response?.data?.message;
        this.alertMessage =
          errorMessage || this.$t('INTEGRATION_APPS.DELETE.API.ERROR_MESSAGE');
      } finally {
        useAlert(this.alertMessage);
      }
    },
  },
};
</script>

<template>
  <SettingsLayout :is-loading="uiFlags.isFetching">
    <template v-if="isIntegrationSingle" #header>
      <BaseSettingsHeader
        :title="integration.name || ''"
        description=""
        :feature-name="integrationId"
        :back-button-label="$t('INTEGRATION_SETTINGS.HEADER')"
      />
    </template>
    <template #body>
      <div v-if="showIntegrationHooks" class="w-full">
        <div v-if="isIntegrationMultiple">
          <MultipleIntegrationHooks
            :integration-id="integrationId"
            :show-add-button="showAddButton"
            @add="openAddHookModal"
            @delete="openDeletePopup"
          />
        </div>

        <div v-if="isIntegrationSingle">
          <SingleIntegrationHooks
            :integration-id="integrationId"
            @add="openAddHookModal"
            @delete="openDeletePopup"
            @remove-provider="openProviderDeletePopup"
            @set-primary-provider="setPrimaryAudioProvider"
          />
        </div>
      </div>
    </template>
    <woot-modal
      v-model:show="showAddHookModal"
      :on-close="hideAddHookModal"
      size="integration-hook-modal"
    >
      <NewHook
        :integration-id="integrationId"
        :initial-provider="selectedProvider"
        @close="hideAddHookModal"
      />
    </woot-modal>

    <woot-delete-modal
      v-model:show="showDeleteConfirmationPopup"
      :on-close="closeDeletePopup"
      :on-confirm="confirmDeletion"
      :title="
        selectedProviderForRemoval
          ? $t(
              'INTEGRATION_APPS.AUDIO_TRANSCRIPTION.DISCONNECT_PROVIDER_TITLE',
              {
                provider: selectedProviderNameForRemoval,
              }
            )
          : deleteTitle
      "
      :message="
        selectedProviderForRemoval
          ? $t(
              'INTEGRATION_APPS.AUDIO_TRANSCRIPTION.DISCONNECT_PROVIDER_MESSAGE',
              {
                provider: selectedProviderNameForRemoval,
              }
            )
          : deleteMessage
      "
      :confirm-text="confirmText"
      :reject-text="cancelText"
    />
  </SettingsLayout>
</template>
