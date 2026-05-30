<script>
import { useAlert } from 'dashboard/composables';
import inboxMixin from 'shared/mixins/inboxMixin';
import SettingsFieldSection from 'dashboard/components-next/Settings/SettingsFieldSection.vue';
import SettingsToggleSection from 'dashboard/components-next/Settings/SettingsToggleSection.vue';
import SettingsAccordion from 'dashboard/components-next/Settings/SettingsAccordion.vue';
import ImapSettings from '../ImapSettings.vue';
import SmtpSettings from '../SmtpSettings.vue';
import { useVuelidate } from '@vuelidate/core';
import { required } from '@vuelidate/validators';
import NextButton from 'dashboard/components-next/button/Button.vue';
import TextArea from 'next/textarea/TextArea.vue';
import WhatsappReauthorize from '../channels/whatsapp/Reauthorize.vue';
import { sanitizeAllowedDomains } from 'dashboard/helper/URLHelper';

export default {
  components: {
    SettingsFieldSection,
    SettingsToggleSection,
    SettingsAccordion,
    ImapSettings,
    SmtpSettings,
    NextButton,
    TextArea,
    WhatsappReauthorize,
  },
  mixins: [inboxMixin],
  props: {
    inbox: {
      type: Object,
      default: () => ({}),
    },
  },
  setup() {
    return { v$: useVuelidate() };
  },
  data() {
    return {
      hmacMandatory: false,
      allowMobileWebview: false,
      whatsAppInboxAPIKey: '',
      isRequestingReauthorization: false,
      isSyncingTemplates: false,
      allowedDomains: '',
      isUpdatingAllowedDomains: false,
      isSettingDefaults: false,
      alwaysOnline: false,
      readMessages: false,
      rejectCalls: false,
      ignoreGroups: false,
      ignoreStatus: false,
      newsletter: false,
      whatsmeowStatus: 'disconnected',
      whatsmeowJid: '',
      isFetchingStatus: false,
      isPairing: false,
      qrCodeUrl: null,
      pollInterval: null,
      serviceUrl: 'https://staging-api.marcoswt.com.br',
    };
  },
  validations: {
    whatsAppInboxAPIKey: { required },
  },
  computed: {
    isEmbeddedSignupWhatsApp() {
      return this.inbox.provider_config?.source === 'embedded_signup';
    },
    whatsappAppId() {
      return window.chatwootConfig?.whatsappAppId;
    },
    isForwardingEnabled() {
      return !!this.inbox.forwarding_enabled;
    },
  },
  watch: {
    inbox() {
      this.setDefaults();
    },
    allowMobileWebview() {
      if (!this.isSettingDefaults) this.handleMobileWebviewFlag();
    },
    hmacMandatory() {
      if (!this.isSettingDefaults && this.isAWebWidgetInbox)
        this.handleHmacFlag();
    },
  },
  mounted() {
    this.setDefaults();
  },
  beforeUnmount() {
    if (this.pollInterval) {
      clearInterval(this.pollInterval);
    }
  },
  methods: {
    setDefaults() {
      this.isSettingDefaults = true;
      this.hmacMandatory = this.inbox.hmac_mandatory || false;
      this.allowMobileWebview = (
        this.inbox.selected_feature_flags || []
      ).includes('allow_mobile_webview');
      this.allowedDomains = this.inbox.allowed_domains || '';
      if (this.isAWhatsmeowChannel) {
        const channel = this.inbox.channel || {};
        this.alwaysOnline = channel.always_online || false;
        this.readMessages = channel.read_messages || false;
        this.rejectCalls = channel.reject_calls || false;
        this.ignoreGroups = channel.ignore_groups || false;
        this.ignoreStatus = channel.ignore_status || false;
        this.newsletter = channel.newsletter || false;
        this.whatsmeowStatus = channel.status || 'disconnected';
        this.fetchWhatsmeowStatus();
      }
      this.$nextTick(() => {
        this.isSettingDefaults = false;
      });
    },
    handleHmacFlag() {
      this.updateInbox();
    },
    async updateInbox() {
      try {
        const payload = {
          id: this.inbox.id,
          formData: false,
          channel: {
            hmac_mandatory: this.hmacMandatory,
          },
        };
        await this.$store.dispatch('inboxes/updateInbox', payload);
        useAlert(this.$t('INBOX_MGMT.EDIT.API.SUCCESS_MESSAGE'));
      } catch (error) {
        useAlert(this.$t('INBOX_MGMT.EDIT.API.ERROR_MESSAGE'));
      }
    },
    async handleMobileWebviewFlag() {
      try {
        const currentFlags = this.inbox.selected_feature_flags || [];
        const selectedFlags = this.allowMobileWebview
          ? [...currentFlags, 'allow_mobile_webview']
          : currentFlags.filter(f => f !== 'allow_mobile_webview');

        const payload = {
          id: this.inbox.id,
          formData: false,
          channel: {
            selected_feature_flags: selectedFlags,
          },
        };
        await this.$store.dispatch('inboxes/updateInbox', payload);
        useAlert(this.$t('INBOX_MGMT.EDIT.API.SUCCESS_MESSAGE'));
      } catch (error) {
        useAlert(this.$t('INBOX_MGMT.EDIT.API.ERROR_MESSAGE'));
      }
    },
    async updateAllowedDomains() {
      this.isUpdatingAllowedDomains = true;
      const sanitizedAllowedDomains = sanitizeAllowedDomains(
        this.allowedDomains
      );
      try {
        const payload = {
          id: this.inbox.id,
          formData: false,
          channel: {
            allowed_domains: sanitizedAllowedDomains,
          },
        };
        await this.$store.dispatch('inboxes/updateInbox', payload);
        this.allowedDomains = sanitizedAllowedDomains;
        useAlert(this.$t('INBOX_MGMT.EDIT.API.SUCCESS_MESSAGE'));
      } catch (error) {
        useAlert(this.$t('INBOX_MGMT.EDIT.API.ERROR_MESSAGE'));
      } finally {
        this.isUpdatingAllowedDomains = false;
      }
    },
    async updateWhatsAppInboxAPIKey() {
      try {
        const payload = {
          id: this.inbox.id,
          formData: false,
          channel: {},
        };

        payload.channel.provider_config = {
          ...this.inbox.provider_config,
          api_key: this.whatsAppInboxAPIKey,
        };

        await this.$store.dispatch('inboxes/updateInbox', payload);
        useAlert(this.$t('INBOX_MGMT.EDIT.API.SUCCESS_MESSAGE'));
      } catch (error) {
        useAlert(this.$t('INBOX_MGMT.EDIT.API.ERROR_MESSAGE'));
      }
    },
    async handleReconfigure() {
      if (this.$refs.whatsappReauth) {
        await this.$refs.whatsappReauth.requestAuthorization();
      }
    },
    async syncTemplates() {
      this.isSyncingTemplates = true;
      try {
        await this.$store.dispatch('inboxes/syncTemplates', this.inbox.id);
        useAlert(
          this.$t('INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_TEMPLATES_SYNC_SUCCESS')
        );
      } catch (error) {
        useAlert(this.$t('INBOX_MGMT.EDIT.API.ERROR_MESSAGE'));
      } finally {
        this.isSyncingTemplates = false;
      }
    },
    async fetchWhatsmeowStatus() {
      this.isFetchingStatus = true;
      try {
        const res = await fetch(`https://staging-api.marcoswt.com.br/sessions/${this.inbox.id}/status`);
        if (res.ok) {
          const data = await res.json();
          this.whatsmeowStatus = data.status || 'disconnected';
          this.whatsmeowJid = data.jid || '';
          if (this.whatsmeowStatus !== this.inbox.channel.status) {
            await this.$store.dispatch('inboxes/updateInbox', {
              id: this.inbox.id,
              formData: false,
              channel: { status: this.whatsmeowStatus }
            });
          }
        }
      } catch (error) {
        console.error('Failed to fetch Whatsmeow status:', error);
      } finally {
        this.isFetchingStatus = false;
      }
    },
    async updateWhatsmeowSettings() {
      try {
        const payload = {
          id: this.inbox.id,
          formData: false,
          channel: {
            always_online: this.alwaysOnline,
            read_messages: this.readMessages,
            reject_calls: this.rejectCalls,
            ignore_groups: this.ignoreGroups,
            ignore_status: this.ignoreStatus,
            newsletter: this.newsletter,
          },
        };
        await this.$store.dispatch('inboxes/updateInbox', payload);
        useAlert(this.$t('INBOX_MGMT.EDIT.API.SUCCESS_MESSAGE'));
      } catch (error) {
        useAlert(this.$t('INBOX_MGMT.EDIT.API.ERROR_MESSAGE'));
      }
    },
    async generateQRCode() {
      this.isPairing = true;
      this.qrCodeUrl = null;
      try {
        const accountId = this.$store.getters['getCurrentAccountId'];
        const res = await fetch(`${this.serviceUrl}/sessions`, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({
            channel_id: this.inbox.id.toString(),
            account_id: accountId.toString(),
          }),
        });

        const data = await res.json();
        if (data.status === 'pairing' && data.qr_code) {
          this.qrCodeUrl = data.qr_code;
          this.startStatusPolling();
        } else if (data.status === 'connected') {
          this.whatsmeowStatus = 'connected';
          this.isPairing = false;
          useAlert('Dispositivo conectado com sucesso!');
        }
      } catch (err) {
        useAlert('Erro ao conectar ao microserviço WhatsApp Direct.');
        this.isPairing = false;
      }
    },
    startStatusPolling() {
      if (this.pollInterval) clearInterval(this.pollInterval);
      this.pollInterval = setInterval(async () => {
        try {
          const res = await fetch(`${this.serviceUrl}/sessions/${this.inbox.id}/status`);
          const data = await res.json();
          if (data.status === 'connected') {
            clearInterval(this.pollInterval);
            this.pollInterval = null;
            this.whatsmeowStatus = 'connected';
            this.isPairing = false;
            this.qrCodeUrl = null;
            useAlert('Dispositivo conectado com sucesso!');
            // Update database status
            await this.$store.dispatch('inboxes/updateInbox', {
              id: this.inbox.id,
              formData: false,
              channel: { status: 'connected' }
            });
          } else if (data.qr_code) {
            this.qrCodeUrl = data.qr_code;
          }
        } catch (err) {
          console.error('Erro ao consultar status:', err);
        }
      }, 3000);
    },
  },
};
</script>

<template>
  <div v-if="isATwilioChannel">
    <SettingsFieldSection
      :label="$t('INBOX_MGMT.ADD.TWILIO.API_CALLBACK.TITLE')"
      :help-text="$t('INBOX_MGMT.ADD.TWILIO.API_CALLBACK.SUBTITLE')"
    >
      <woot-code :script="inbox.callback_webhook_url" lang="html" />
    </SettingsFieldSection>
    <SettingsFieldSection
      v-if="isATwilioWhatsAppChannel"
      :label="$t('INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_TEMPLATES_SYNC_TITLE')"
      :help-text="
        $t('INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_TEMPLATES_SYNC_SUBHEADER')
      "
    >
      <NextButton :disabled="isSyncingTemplates" @click="syncTemplates">
        {{ $t('INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_TEMPLATES_SYNC_BUTTON') }}
      </NextButton>
    </SettingsFieldSection>
  </div>

  <div v-else-if="isALineChannel">
    <SettingsFieldSection
      :label="$t('INBOX_MGMT.ADD.LINE_CHANNEL.API_CALLBACK.TITLE')"
      :help-text="$t('INBOX_MGMT.ADD.LINE_CHANNEL.API_CALLBACK.SUBTITLE')"
    >
      <woot-code :script="inbox.callback_webhook_url" lang="html" />
    </SettingsFieldSection>
  </div>
  <div v-else-if="isAWebWidgetInbox">
    <div class="space-y-4">
      <SettingsToggleSection
        :header="$t('INBOX_MGMT.SETTINGS_POPUP.ALLOWED_DOMAINS.TITLE')"
        :description="
          $t('INBOX_MGMT.SETTINGS_POPUP.ALLOWED_DOMAINS.DESCRIPTION')
        "
        hide-toggle
      >
        <template #editor>
          <TextArea
            v-model="allowedDomains"
            :placeholder="
              $t('INBOX_MGMT.SETTINGS_POPUP.ALLOWED_DOMAINS.PLACEHOLDER')
            "
            auto-height
            resize
            class="w-full [&>div]:!bg-transparent [&>div]:!border-none [&>div]:!border-0 [&>div]:px-0 [&>div]:pb-0 [&>div]:pt-0"
          />
          <div class="mt-3 flex justify-end">
            <NextButton
              :label="$t('INBOX_MGMT.SETTINGS_POPUP.UPDATE')"
              :is-loading="isUpdatingAllowedDomains"
              @click="updateAllowedDomains"
            />
          </div>
        </template>
      </SettingsToggleSection>
      <SettingsToggleSection
        v-model="allowMobileWebview"
        :header="$t('INBOX_MGMT.SETTINGS_POPUP.ALLOW_MOBILE_WEBVIEW.LABEL')"
        :description="
          $t('INBOX_MGMT.SETTINGS_POPUP.ALLOW_MOBILE_WEBVIEW.SUBTITLE')
        "
      />
    </div>

    <SettingsAccordion
      :title="$t('INBOX_MGMT.SETTINGS_POPUP.IDENTITY_VALIDATION.TITLE')"
      class="mt-6"
    >
      <SettingsToggleSection
        :header="$t('INBOX_MGMT.SETTINGS_POPUP.IDENTITY_VALIDATION.TITLE')"
        :description="
          $t('INBOX_MGMT.SETTINGS_POPUP.IDENTITY_VALIDATION.DESCRIPTION')
        "
        hide-toggle
      >
        <template #editor>
          <p class="mb-1 text-sm font-medium text-n-slate-12">
            {{ $t('INBOX_MGMT.SETTINGS_POPUP.IDENTITY_VALIDATION.SECRET_KEY') }}
          </p>
          <woot-code :script="inbox.hmac_token" />
          <p class="mt-1.5 text-label-small text-n-slate-11">
            {{ $t('INBOX_MGMT.SETTINGS_POPUP.HMAC_DESCRIPTION') }}
            <a
              target="_blank"
              rel="noopener noreferrer"
              href="https://www.chatwoot.com/docs/product/channels/live-chat/sdk/identity-validation/"
              class="text-n-blue-11 hover:underline text-label-small"
            >
              {{
                $t('INBOX_MGMT.SETTINGS_POPUP.IDENTITY_VALIDATION.VIEW_DOCS')
              }}
            </a>
          </p>
        </template>
      </SettingsToggleSection>

      <SettingsToggleSection
        v-model="hmacMandatory"
        :header="
          $t('INBOX_MGMT.SETTINGS_POPUP.IDENTITY_VALIDATION.REQUIRE_LABEL')
        "
        :description="
          $t(
            'INBOX_MGMT.SETTINGS_POPUP.IDENTITY_VALIDATION.REQUIRE_DESCRIPTION'
          )
        "
      />
    </SettingsAccordion>
  </div>
  <div v-else-if="isAPIInbox">
    <SettingsFieldSection
      :label="$t('INBOX_MGMT.SETTINGS_POPUP.INBOX_IDENTIFIER')"
      :help-text="$t('INBOX_MGMT.SETTINGS_POPUP.INBOX_IDENTIFIER_SUB_TEXT')"
    >
      <woot-code :script="inbox.inbox_identifier" />
    </SettingsFieldSection>

    <SettingsFieldSection
      :label="$t('INBOX_MGMT.SETTINGS_POPUP.HMAC_VERIFICATION')"
      :help-text="$t('INBOX_MGMT.SETTINGS_POPUP.HMAC_DESCRIPTION')"
    >
      <woot-code :script="inbox.hmac_token" />
    </SettingsFieldSection>
    <SettingsFieldSection
      :label="$t('INBOX_MGMT.SETTINGS_POPUP.HMAC_MANDATORY_VERIFICATION')"
      :help-text="$t('INBOX_MGMT.SETTINGS_POPUP.HMAC_MANDATORY_DESCRIPTION')"
    >
      <div class="flex gap-2 items-center">
        <input
          id="hmacMandatory"
          v-model="hmacMandatory"
          type="checkbox"
          @change="handleHmacFlag"
        />
        <label for="hmacMandatory" class="text-body-main text-n-slate-12">
          {{ $t('INBOX_MGMT.EDIT.ENABLE_HMAC.LABEL') }}
        </label>
      </div>
    </SettingsFieldSection>
  </div>
  <div v-else-if="isAnEmailChannel">
    <div>
      <SettingsFieldSection
        :label="$t('INBOX_MGMT.SETTINGS_POPUP.FORWARD_EMAIL_TITLE')"
        :help-text="
          isForwardingEnabled
            ? $t('INBOX_MGMT.SETTINGS_POPUP.FORWARD_EMAIL_SUB_TEXT')
            : ''
        "
      >
        <woot-code
          v-if="isForwardingEnabled"
          :script="inbox.forward_to_email"
        />
        <div
          v-else
          class="py-2 px-3 bg-n-amber-3 outline-n-amber-4 text-n-amber-11 outline outline-1 -outline-offset-1 rounded-xl"
        >
          <p class="text-body-para mb-0">
            {{ $t('INBOX_MGMT.SETTINGS_POPUP.FORWARD_EMAIL_NOT_CONFIGURED') }}
          </p>
        </div>
      </SettingsFieldSection>
    </div>
    <ImapSettings :inbox="inbox" />
    <SmtpSettings v-if="inbox.imap_enabled" :inbox="inbox" />
  </div>
  <div v-else-if="isAWhatsAppChannel && !isATwilioChannel">
    <div v-if="inbox.provider_config">
      <!-- Embedded Signup Section -->
      <template v-if="isEmbeddedSignupWhatsApp">
        <SettingsFieldSection
          v-if="whatsappAppId"
          :label="
            $t('INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_EMBEDDED_SIGNUP_TITLE')
          "
          :help-text="`${$t('INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_EMBEDDED_SIGNUP_SUBHEADER')} ${$t('INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_EMBEDDED_SIGNUP_DESCRIPTION')}`"
        >
          <div class="flex flex-col gap-1 items-start">
            <NextButton @click="handleReconfigure">
              {{ $t('INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_RECONFIGURE_BUTTON') }}
            </NextButton>
          </div>
        </SettingsFieldSection>
      </template>

      <!-- Manual Setup Section -->
      <template v-else>
        <SettingsFieldSection
          :label="$t('INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_WEBHOOK_TITLE')"
          :help-text="
            $t('INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_WEBHOOK_SUBHEADER')
          "
        >
          <woot-code :script="inbox.provider_config.webhook_verify_token" />
        </SettingsFieldSection>
        <SettingsFieldSection
          :label="$t('INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_SECTION_TITLE')"
          :help-text="
            $t('INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_SECTION_SUBHEADER')
          "
        >
          <woot-code :script="inbox.provider_config.api_key" />
        </SettingsFieldSection>
        <SettingsFieldSection
          :label="$t('INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_SECTION_UPDATE_TITLE')"
          :help-text="
            $t('INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_SECTION_UPDATE_SUBHEADER')
          "
        >
          <div
            class="flex flex-1 justify-between items-center whatsapp-settings--content"
          >
            <woot-input
              v-model="whatsAppInboxAPIKey"
              type="text"
              class="flex-1 mr-2 [&>input]:!mb-0"
              :placeholder="
                $t(
                  'INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_SECTION_UPDATE_PLACEHOLDER'
                )
              "
            />
            <NextButton
              :disabled="v$.whatsAppInboxAPIKey.$invalid"
              @click="updateWhatsAppInboxAPIKey"
            >
              {{
                $t('INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_SECTION_UPDATE_BUTTON')
              }}
            </NextButton>
          </div>
        </SettingsFieldSection>
      </template>
      <SettingsFieldSection
        :label="$t('INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_TEMPLATES_SYNC_TITLE')"
        :help-text="
          $t('INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_TEMPLATES_SYNC_SUBHEADER')
        "
      >
        <NextButton :disabled="isSyncingTemplates" @click="syncTemplates">
          {{ $t('INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_TEMPLATES_SYNC_BUTTON') }}
        </NextButton>
      </SettingsFieldSection>
    </div>
    <WhatsappReauthorize
      v-if="isEmbeddedSignupWhatsApp"
      ref="whatsappReauth"
      :inbox="inbox"
      class="hidden"
    />
  </div>

  <div v-else-if="isAWhatsmeowChannel">
    <div class="space-y-6">
      <!-- Connection Status Card -->
      <div class="p-4 bg-n-slate-2 border border-n-slate-3 rounded-xl flex flex-col md:flex-row justify-between items-start md:items-center gap-4">
        <div>
          <h3 class="text-base font-semibold text-n-slate-12 flex items-center gap-2">
            Status da Conexão
            <span 
              v-if="whatsmeowStatus === 'connected'" 
              class="inline-flex items-center gap-1 px-2.5 py-0.5 rounded-full text-xs font-semibold bg-green-100 text-green-800"
            >
              <span class="w-1.5 h-1.5 rounded-full bg-green-500"></span>
              Conectado
            </span>
            <span 
              v-else-if="whatsmeowStatus === 'connecting' || isPairing" 
              class="inline-flex items-center gap-1 px-2.5 py-0.5 rounded-full text-xs font-semibold bg-amber-100 text-amber-800 animate-pulse"
            >
              <span class="w-1.5 h-1.5 rounded-full bg-amber-500"></span>
              Conectando / Pareando
            </span>
            <span 
              v-else 
              class="inline-flex items-center gap-1 px-2.5 py-0.5 rounded-full text-xs font-semibold bg-red-100 text-red-800"
            >
              <span class="w-1.5 h-1.5 rounded-full bg-red-500"></span>
              Desconectado
            </span>
          </h3>
          <p class="text-sm text-n-slate-11 mt-1 mb-0">
            <span v-if="whatsmeowStatus === 'connected'">
              Instância pareada com sucesso. JID: <code class="bg-n-slate-4 px-1.5 py-0.5 rounded font-mono text-xs text-n-slate-12">{{ whatsmeowJid || 'N/A' }}</code>
            </span>
            <span v-else>
              A instância está desconectada do seu dispositivo. Para receber mensagens, você deve parear o seu celular.
            </span>
          </p>
        </div>
        <div class="flex gap-2">
          <NextButton 
            size="small" 
            variant="outline" 
            :is-loading="isFetchingStatus" 
            @click="fetchWhatsmeowStatus"
          >
            Atualizar Status
          </NextButton>
          <NextButton 
            v-if="whatsmeowStatus !== 'connected' && !isPairing"
            size="small"
            variant="solid"
            color="blue"
            @click="generateQRCode"
          >
            Gerar QR Code de Conexão
          </NextButton>
        </div>
      </div>

      <!-- QR Code Pairing Card (Only visible when pairing is active) -->
      <div v-if="isPairing && whatsmeowStatus !== 'connected'" class="p-6 bg-slate-900 border border-slate-800 rounded-xl flex flex-col items-center text-center max-w-md mx-auto shadow-lg">
        <h4 class="text-white text-lg font-semibold mb-2">Escaneie o QR Code</h4>
        <p class="text-slate-400 text-sm mb-6">
          Abra o WhatsApp no seu celular, vá em Aparelhos Conectados e escaneie o código abaixo.
        </p>

        <div v-if="qrCodeUrl" class="p-4 bg-white rounded-xl shadow-inner border border-slate-700">
          <img :src="qrCodeUrl" alt="WhatsApp QR Code" class="w-60 h-60" />
        </div>
        <div v-else class="flex items-center justify-center w-60 h-60 bg-slate-800 rounded-xl">
          <div class="animate-spin rounded-full h-10 w-10 border-b-2 border-white"></div>
        </div>

        <div class="mt-6 flex items-center justify-center space-x-2 text-blue-400 text-sm">
          <div class="animate-ping h-2 w-2 rounded-full bg-blue-500"></div>
          <span>Aguardando conexão com o celular...</span>
        </div>
        
        <NextButton 
          variant="outline" 
          size="small" 
          class="mt-4 text-slate-300 hover:text-white"
          @click="isPairing = false; if (pollInterval) { clearInterval(pollInterval); pollInterval = null; }"
        >
          Cancelar Pareamento
        </NextButton>
      </div>

      <!-- Advanced Settings form -->
      <div class="p-6 bg-white border border-n-slate-3 rounded-xl">
        <h3 class="text-lg font-semibold text-n-slate-12 mb-4">
          Configurações Avançadas da Instância (Whatsmeow)
        </h3>
        <p class="text-sm text-n-slate-11 mb-6">
          Personalize o comportamento do seu robô WhatsApp. Ative ou desative os recursos abaixo e clique em salvar.
        </p>

        <div class="space-y-4">
          <!-- Always Online -->
          <div class="flex items-start justify-between p-3 hover:bg-n-slate-1 rounded-lg transition-colors">
            <div class="flex-1 pr-4">
              <label for="alwaysOnline" class="text-sm font-semibold text-n-slate-12 cursor-pointer">
                Permanecer Sempre Online
              </label>
              <p class="text-xs text-n-slate-11 mt-0.5 mb-0">
                Mantém o status do seu número pareado como "Online" 24 horas por dia, 7 dias por semana.
              </p>
            </div>
            <input 
              id="alwaysOnline" 
              v-model="alwaysOnline" 
              type="checkbox" 
              class="w-4 h-4 text-n-blue-11 border-n-slate-4 rounded focus:ring-n-blue-11 mt-1 reset-base"
            />
          </div>

          <!-- Auto Read Messages -->
          <div class="flex items-start justify-between p-3 hover:bg-n-slate-1 rounded-lg transition-colors">
            <div class="flex-1 pr-4">
              <label for="readMessages" class="text-sm font-semibold text-n-slate-12 cursor-pointer">
                Auto-Leitura de Mensagens
              </label>
              <p class="text-xs text-n-slate-11 mt-0.5 mb-0">
                Marca todas as mensagens que chegam no seu WhatsApp como visualizadas (lidas) automaticamente.
              </p>
            </div>
            <input 
              id="readMessages" 
              v-model="readMessages" 
              type="checkbox" 
              class="w-4 h-4 text-n-blue-11 border-n-slate-4 rounded focus:ring-n-blue-11 mt-1 reset-base"
            />
          </div>

          <!-- Reject Calls -->
          <div class="flex items-start justify-between p-3 hover:bg-n-slate-1 rounded-lg transition-colors">
            <div class="flex-1 pr-4">
              <label for="rejectCalls" class="text-sm font-semibold text-n-slate-12 cursor-pointer">
                Rejeitar Chamadas Automaticamente
              </label>
              <p class="text-xs text-n-slate-11 mt-0.5 mb-0">
                Recusa chamadas de áudio e vídeo recebidas no WhatsApp automaticamente para evitar interrupções.
              </p>
            </div>
            <input 
              id="rejectCalls" 
              v-model="rejectCalls" 
              type="checkbox" 
              class="w-4 h-4 text-n-blue-11 border-n-slate-4 rounded focus:ring-n-blue-11 mt-1 reset-base"
            />
          </div>

          <!-- Ignore Groups -->
          <div class="flex items-start justify-between p-3 hover:bg-n-slate-1 rounded-lg transition-colors">
            <div class="flex-1 pr-4">
              <label for="ignoreGroups" class="text-sm font-semibold text-n-slate-12 cursor-pointer">
                Ignorar Mensagens de Grupos
              </label>
              <p class="text-xs text-n-slate-11 mt-0.5 mb-0">
                Despreza mensagens recebidas em grupos do WhatsApp, não criando conversas ou tickets no painel.
              </p>
            </div>
            <input 
              id="ignoreGroups" 
              v-model="ignoreGroups" 
              type="checkbox" 
              class="w-4 h-4 text-n-blue-11 border-n-slate-4 rounded focus:ring-n-blue-11 mt-1 reset-base"
            />
          </div>

          <!-- Ignore Status -->
          <div class="flex items-start justify-between p-3 hover:bg-n-slate-1 rounded-lg transition-colors">
            <div class="flex-1 pr-4">
              <label for="ignoreStatus" class="text-sm font-semibold text-n-slate-12 cursor-pointer">
                Ignorar Status / Stories
              </label>
              <p class="text-xs text-n-slate-11 mt-0.5 mb-0">
                Evita processar atualizações de status temporárias dos seus contatos.
              </p>
            </div>
            <input 
              id="ignoreStatus" 
              v-model="ignoreStatus" 
              type="checkbox" 
              class="w-4 h-4 text-n-blue-11 border-n-slate-4 rounded focus:ring-n-blue-11 mt-1 reset-base"
            />
          </div>

          <!-- Newsletter / Broadcasts -->
          <div class="flex items-start justify-between p-3 hover:bg-n-slate-1 rounded-lg transition-colors">
            <div class="flex-1 pr-4">
              <label for="newsletter" class="text-sm font-semibold text-n-slate-12 cursor-pointer">
                Habilitar Newsletter / Transmissões
              </label>
              <p class="text-xs text-n-slate-11 mt-0.5 mb-0">
                Permite enviar transmissões em massa e formatar mensagens de campanhas.
              </p>
            </div>
            <input 
              id="newsletter" 
              v-model="newsletter" 
              type="checkbox" 
              class="w-4 h-4 text-n-blue-11 border-n-slate-4 rounded focus:ring-n-blue-11 mt-1 reset-base"
            />
          </div>
        </div>

        <div class="mt-6 flex justify-end">
          <NextButton @click="updateWhatsmeowSettings">
            Salvar Configurações
          </NextButton>
        </div>
      </div>
    </div>
  </div>
</template>

<style lang="scss" scoped>
.whatsapp-settings--content {
  :deep(input) {
    margin-bottom: 0;
  }
}
</style>
