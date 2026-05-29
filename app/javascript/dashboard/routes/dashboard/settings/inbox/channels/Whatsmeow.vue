<script>
import { mapGetters } from 'vuex';
import { useVuelidate } from '@vuelidate/core';
import { useAlert } from 'dashboard/composables';
import { required } from '@vuelidate/validators';
import router from '../../../../index';
import PageHeader from '../../SettingsSubPageHeader.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';

export default {
  components: {
    PageHeader,
    NextButton,
  },
  setup() {
    return { v$: useVuelidate() };
  },
  data() {
    return {
      phoneNumber: '',
      channelName: '',
      inboxId: null,
      qrCodeUrl: null,
      isPairing: false,
      isPaired: false,
      pollInterval: null,
      serviceUrl: 'https://staging-api.marcoswt.com.br',
    };
  },
  computed: {
    ...mapGetters({
      uiFlags: 'inboxes/getUIFlags',
    }),
  },
  validations: {
    phoneNumber: { required },
    channelName: { required },
  },
  beforeUnmount() {
    if (this.pollInterval) {
      clearInterval(this.pollInterval);
    }
  },
  methods: {
    async createChannel() {
      this.v$.$touch();
      if (this.v$.$invalid) {
        return;
      }

      try {
        // 1. Create Inbox Channel in Chatwoot
        const whatsmeowChannel = await this.$store.dispatch(
          'inboxes/createChannel',
          {
            channel: {
              type: 'whatsmeow',
              phone_number: this.phoneNumber,
            },
            name: this.channelName,
          }
        );

        this.inboxId = whatsmeowChannel.id;
        this.isPairing = true;

        // 2. Start session on Whatsmeow Go API
        await this.startWhatsmeowSession(whatsmeowChannel.id);
      } catch (error) {
        useAlert(error.message || 'Failed to create Whatsmeow direct channel.');
      }
    },

    async startWhatsmeowSession(channelId) {
      try {
        const accountId = this.$store.getters['getCurrentAccountId'];
        const res = await fetch(`${this.serviceUrl}/sessions`, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({
            channel_id: channelId.toString(),
            account_id: accountId.toString(),
          }),
        });

        const data = await res.json();
        if (data.status === 'pairing' && data.qr_code) {
          this.qrCodeUrl = data.qr_code;
          // Start polling status
          this.startStatusPolling(channelId);
        } else if (data.status === 'connected') {
          this.handlePairingSuccess();
        }
      } catch (err) {
        useAlert('Error connecting to WhatsApp Direct microservice.');
      }
    },

    startStatusPolling(channelId) {
      this.pollInterval = setInterval(async () => {
        try {
          const res = await fetch(`${this.serviceUrl}/sessions/${channelId}/status`);
          const data = await res.json();
          if (data.status === 'connected') {
            clearInterval(this.pollInterval);
            this.handlePairingSuccess();
          } else if (data.qr_code) {
            // Update QR code if refreshed
            this.qrCodeUrl = data.qr_code;
          }
        } catch (err) {
          console.error('Failed to poll status', err);
        }
      }, 3000);
    },

    handlePairingSuccess() {
      this.isPaired = true;
      this.qrCodeUrl = null;
      setTimeout(() => {
        router.replace({
          name: 'settings_inboxes_add_agents',
          params: {
            page: 'new',
            inbox_id: this.inboxId,
          },
        });
      }, 2000);
    },
  },
};
</script>

<template>
  <div class="h-full w-full p-6 col-span-6">
    <PageHeader
      header-title="WhatsApp Direct (Whatsmeow)"
      header-content="Conecte seu WhatsApp diretamente usando a biblioteca Whatsmeow em alta performance. Sem dependências externas complexas."
    />

    <!-- Phase 1: Setup Credentials -->
    <form
      v-if="!isPairing"
      class="flex flex-wrap flex-col mx-0"
      @submit.prevent="createChannel()"
    >
      <div class="flex-shrink-0 flex-grow-0">
        <label :class="{ error: v$.channelName.$error }">
          Nome do Canal / Inbox
          <input
            v-model="channelName"
            type="text"
            placeholder="Ex: WhatsApp Suporte"
            @blur="v$.channelName.$touch"
          />
        </label>
      </div>

      <div class="flex-shrink-0 flex-grow-0 mt-4">
        <label :class="{ error: v$.phoneNumber.$error }">
          Número de Telefone (DDI + DDD + Número)
          <input
            v-model="phoneNumber"
            type="text"
            placeholder="Ex: +5511999999999"
            @blur="v$.phoneNumber.$touch"
          />
        </label>
      </div>

      <div class="w-full mt-6">
        <NextButton
          :is-loading="uiFlags.isCreating"
          type="submit"
          solid
          blue
          label="Gerar QR Code de Conexão"
        />
      </div>
    </form>

    <!-- Phase 2: Pairing QR Code -->
    <div v-else-if="isPairing && !isPaired" class="flex flex-col items-center p-8 bg-slate-900 rounded-2xl shadow-xl mt-6 border border-slate-800 max-w-md mx-auto text-center">
      <h3 class="text-white text-lg font-semibold mb-2">Escaneie o QR Code</h3>
      <p class="text-slate-400 text-sm mb-6">Abra o WhatsApp no seu celular, vá em Aparelhos Conectados e escaneie o código abaixo.</p>
      
      <div v-if="qrCodeUrl" class="p-4 bg-white rounded-xl shadow-inner border border-slate-700 animate-pulse-subtle">
        <img :src="qrCodeUrl" alt="WhatsApp QR Code" class="w-64 h-64" />
      </div>
      <div v-else class="flex items-center justify-center w-64 h-64 bg-slate-800 rounded-xl">
        <div class="animate-spin rounded-full h-12 w-12 border-b-2 border-white"></div>
      </div>

      <div class="mt-6 flex items-center justify-center space-x-2 text-blue-400 text-sm">
        <div class="animate-ping h-2.5 w-2.5 rounded-full bg-blue-500"></div>
        <span>Aguardando conexão com o celular...</span>
      </div>
    </div>

    <!-- Phase 3: Pairing Success -->
    <div v-else-if="isPaired" class="flex flex-col items-center p-8 bg-slate-900 rounded-2xl shadow-xl mt-6 border border-green-900 max-w-md mx-auto text-center animate-fade-in">
      <div class="w-20 h-20 bg-green-900/30 rounded-full flex items-center justify-center border-2 border-green-500 mb-6 scale-up-center">
        <svg class="w-10 h-10 text-green-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2.5" d="M5 13l4 4L19 7" />
        </svg>
      </div>
      <h3 class="text-white text-xl font-bold mb-2">Aparelho Conectado!</h3>
      <p class="text-slate-300 text-sm mb-2">Seu WhatsApp foi integrado com sucesso ao Chatwoot.</p>
      <p class="text-green-400 text-xs font-semibold animate-pulse">Redirecionando para a equipe de atendentes...</p>
    </div>
  </div>
</template>

<style scoped>
.animate-pulse-subtle {
  animation: pulse 3s cubic-bezier(0.4, 0, 0.6, 1) infinite;
}
.animate-fade-in {
  animation: fadeIn 0.5s ease-out forwards;
}
.scale-up-center {
  animation: scaleUp 0.4s cubic-bezier(0.390, 0.575, 0.565, 1.000) both;
}

@keyframes pulse {
  0%, 100% { opacity: 1; }
  50% { opacity: 0.95; }
}
@keyframes fadeIn {
  from { opacity: 0; transform: translateY(10px); }
  to { opacity: 1; transform: translateY(0); }
}
@keyframes scaleUp {
  0% { transform: scale(0.5); }
  100% { transform: scale(1); }
}
</style>
