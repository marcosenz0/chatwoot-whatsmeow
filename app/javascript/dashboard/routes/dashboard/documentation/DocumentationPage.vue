<script setup>
import { computed, onMounted, ref } from 'vue';
import { useRoute } from 'vue-router';

import Button from 'dashboard/components-next/button/Button.vue';
import { useAlert } from 'dashboard/composables';
import { useStore } from 'dashboard/composables/store';
import { copyTextToClipboard } from 'shared/helpers/clipboard';

const CHATWOOT_BASE_URL = 'https://chatwoot.marcoswt.com.br';
const WHATSMEOW_BASE_URL = 'https://staging-api.marcoswt.com.br';
const store = useStore();
const route = useRoute();
const copiedKey = ref('');

const accountId = computed(() => route.params.accountId || '{account_id}');
const chatwootApiBase = computed(
  () => `${CHATWOOT_BASE_URL}/api/v1/accounts/${accountId.value}`
);

const whatsmeowInboxes = computed(() => {
  return store.getters['inboxes/getInboxes'].filter(
    inbox => inbox.channel_type === 'Channel::Whatsmeow'
  );
});

const connectedInboxes = computed(() => {
  return whatsmeowInboxes.value.filter(inbox => inbox.status === 'connected');
});

const overviewStats = computed(() => [
  {
    label: 'Base Chatwoot',
    value: CHATWOOT_BASE_URL,
    icon: 'i-lucide-server',
  },
  {
    label: 'Conta atual',
    value: accountId.value,
    icon: 'i-lucide-building-2',
  },
  {
    label: 'Instancias Whatsmeow',
    value: whatsmeowInboxes.value.length || '-',
    icon: 'i-lucide-inbox',
  },
  {
    label: 'Conectadas agora',
    value: connectedInboxes.value.length || '-',
    icon: 'i-lucide-wifi',
  },
]);

const authHeaders = `api_access_token: SEU_TOKEN_DE_ACESSO
Content-Type: application/json`;

const multipartHeaders = `api_access_token: SEU_TOKEN_DE_ACESSO

Nao defina Content-Type manualmente em multipart/form-data.
Deixe o n8n ou o cliente HTTP montar o boundary.`;

const replaceTokens = value =>
  value
    .replace(/\{account_id\}/g, accountId.value)
    .replace(/\{chatwoot_base_url\}/g, CHATWOOT_BASE_URL)
    .replace(/\{whatsmeow_base_url\}/g, WHATSMEOW_BASE_URL);

const endpointUrl = endpoint => {
  const path = replaceTokens(endpoint.path);
  return path.startsWith('http') ? path : `${CHATWOOT_BASE_URL}${path}`;
};

const endpointGroups = [
  {
    title: 'Instancias e Inboxes',
    icon: 'i-lucide-inbox',
    description:
      'Use esta parte para transformar o nome da instancia em inbox_id, channel_id, telefone conectado e status.',
    endpoints: [
      {
        method: 'GET',
        path: '/api/v1/accounts/{account_id}/inboxes',
        title: 'Listar caixas de entrada',
        note: 'No n8n, filtre payload[] onde channel_type seja Channel::Whatsmeow e name seja o nome digitado na planilha.',
        response: `{
  "payload": [
    {
      "id": 22,
      "name": "A10busine",
      "channel_id": 14,
      "channel_type": "Channel::Whatsmeow",
      "phone_number": "556392306407",
      "status": "connected"
    }
  ]
}`,
      },
      {
        method: 'GET',
        path: '/api/v1/accounts/{account_id}/inboxes/{inbox_id}/whatsmeow_status',
        title: 'Consultar status da instancia',
        note: 'Use antes de disparar para evitar mandar por uma instancia desconectada.',
        response: `{
  "status": "connected",
  "phone_number": "556392306407"
}`,
      },
      {
        method: 'POST',
        path: '/api/v1/accounts/{account_id}/inboxes/{inbox_id}/whatsmeow_session',
        title: 'Iniciar ou recuperar sessao WhatsApp',
        note: 'Normalmente usado pela tela de configuracao. Para QR novo, envie force_new como true.',
        body: `{
  "force_new": false
}`,
      },
      {
        method: 'DELETE',
        path: '/api/v1/accounts/{account_id}/inboxes/{inbox_id}/whatsmeow_session',
        title: 'Desconectar sessao WhatsApp',
        note: 'Use com cuidado. Isso encerra a sessao da instancia informada.',
      },
    ],
  },
  {
    title: 'Verificacao WhatsApp',
    icon: 'i-lucide-badge-check',
    description:
      'O verificador fica no servico Whatsmeow. Ele confirma se um numero existe no WhatsApp antes de criar conversa.',
    endpoints: [
      {
        method: 'GET',
        path: '{whatsmeow_base_url}/sessions/{inbox_id}/check_number?phone={phone}',
        title: 'Verificar se o numero existe no WhatsApp',
        note: 'Envie phone em formato internacional, somente digitos. Exemplo: 556391234567.',
        response: `{
  "phone": "+556391234567",
  "query": "556391234567",
  "jid": "556391234567@s.whatsapp.net",
  "is_on_whatsapp": true,
  "checked_at": "2026-06-03T12:00:00Z"
}`,
      },
      {
        method: 'GET',
        path: '{whatsmeow_base_url}/sessions/{inbox_id}/profile_picture?jid={jid}&force=true',
        title: 'Buscar foto de perfil do WhatsApp',
        note: 'Opcional. Use jid como 556391234567@s.whatsapp.net. force=true ignora cache.',
      },
    ],
  },
  {
    title: 'Contatos',
    icon: 'i-lucide-user-round',
    description:
      'Antes de criar conversa, busque ou crie o contato com source_id preso a inbox correta.',
    endpoints: [
      {
        method: 'GET',
        path: '/api/v1/accounts/{account_id}/contacts/search?q={telefone}',
        title: 'Buscar contato por telefone',
        note: 'Procure pelo numero normalizado. Use include_contact_inboxes=true se quiser conferir inboxes vinculadas.',
      },
      {
        method: 'POST',
        path: '/api/v1/accounts/{account_id}/contacts',
        title: 'Criar contato vinculado a uma instancia',
        note: 'source_id deve ser o JID do WhatsApp. Para contato direto, use 55...@s.whatsapp.net.',
        body: `{
  "name": "Mercado Exemplo",
  "phone_number": "+556391234567",
  "inbox_id": 22,
  "source_id": "556391234567@s.whatsapp.net",
  "additional_attributes": {
    "city": "Guarai",
    "description": "Lead disparo locucao"
  },
  "custom_attributes": {
    "origem": "disparo_locucao",
    "campanha": "anuncio_locucao",
    "tipo": "Supermercado",
    "prioridade": "Alta"
  }
}`,
        response: `{
  "payload": {
    "contact": { "id": 30, "name": "Mercado Exemplo" },
    "contact_inbox": {
      "source_id": "556391234567@s.whatsapp.net"
    }
  }
}`,
      },
      {
        method: 'PATCH',
        path: '/api/v1/accounts/{account_id}/contacts/{contact_id}',
        title: 'Atualizar dados do contato',
        note: 'Use para atualizar nome, telefone, cidade, tipo, prioridade ou atributos customizados.',
        body: `{
  "name": "Mercado Exemplo Atualizado",
  "phone_number": "+556391234567",
  "custom_attributes": {
    "tipo": "Supermercado",
    "prioridade": "Alta"
  }
}`,
      },
      {
        method: 'POST',
        path: '/api/v1/accounts/{account_id}/contacts/{contact_id}/labels',
        title: 'Adicionar labels ao contato',
        note: 'Opcional para classificar origem, prioridade, cidade ou campanha dentro do Chatwoot.',
        body: `{
  "labels": ["lead_locucao", "prioridade_alta"]
}`,
      },
    ],
  },
  {
    title: 'Conversas',
    icon: 'i-lucide-messages-square',
    description:
      'A conversa liga contato, inbox e source_id. As mensagens sempre saem por uma conversa.',
    endpoints: [
      {
        method: 'POST',
        path: '/api/v1/accounts/{account_id}/conversations',
        title: 'Criar ou abrir conversa',
        note: 'Use contact_id, inbox_id e source_id da mesma instancia. O id retornado e display_id da conversa.',
        body: `{
  "source_id": "556391234567@s.whatsapp.net",
  "inbox_id": 22,
  "contact_id": 30,
  "status": "open"
}`,
        response: `{
  "id": 140,
  "display_id": 140,
  "inbox_id": 22,
  "contact_id": 30
}`,
      },
      {
        method: 'POST',
        path: '/api/v1/accounts/{account_id}/conversations/{conversation_id}/toggle_status',
        title: 'Alterar status da conversa',
        note: 'Use open, pending, resolved ou snoozed conforme o processo de atendimento.',
        body: `{
  "status": "open"
}`,
      },
      {
        method: 'POST',
        path: '/api/v1/accounts/{account_id}/conversations/{conversation_id}/labels',
        title: 'Adicionar labels a conversa',
        note: 'Bom para marcar disparo, campanha, cidade ou origem do lead.',
        body: `{
  "labels": ["disparo_locucao", "google_sheets"]
}`,
      },
    ],
  },
  {
    title: 'Mensagens',
    icon: 'i-lucide-send',
    description:
      'Envie texto, nota interna, audio, imagem, video ou documento. Para WhatsApp Direct, o Chatwoot repassa ao Whatsmeow.',
    endpoints: [
      {
        method: 'POST',
        path: '/api/v1/accounts/{account_id}/conversations/{conversation_id}/messages',
        title: 'Enviar texto para o cliente',
        note: 'message_type deve ser outgoing. private false envia ao WhatsApp; private true vira nota interna.',
        body: `{
  "content": "Boa tarde! Trabalho com locucao para anuncios em carro de som.",
  "message_type": "outgoing",
  "private": false
}`,
      },
      {
        method: 'POST',
        path: '/api/v1/accounts/{account_id}/conversations/{conversation_id}/messages',
        title: 'Enviar nota interna',
        note: 'Notas internas aparecem no Chatwoot e nao sao enviadas para o WhatsApp.',
        body: `{
  "content": "Lead veio da planilha de disparo.",
  "message_type": "outgoing",
  "private": true
}`,
      },
      {
        method: 'POST',
        path: '/api/v1/accounts/{account_id}/conversations/{conversation_id}/messages',
        title: 'Enviar audio como anexo real',
        note: 'Use multipart/form-data no n8n. Para audio normal, mantenha whatsmeow_recorded_audio como false.',
        multipart: `content:
message_type: outgoing
private: false
content_attributes: {"whatsmeow_recorded_audio":false}
attachments[]: arquivo.mp3`,
      },
      {
        method: 'POST',
        path: '/api/v1/accounts/{account_id}/conversations/{conversation_id}/messages',
        title: 'Enviar audio como mensagem de voz',
        note: 'Use somente quando quiser PTT/voz gravada. Para os exemplos de locucao, prefira false.',
        multipart: `content:
message_type: outgoing
private: false
content_attributes: {"whatsmeow_recorded_audio":true}
attachments[]: voz.mp3`,
      },
    ],
  },
  {
    title: 'Grupos e conversa direta',
    icon: 'i-lucide-users-round',
    description:
      'Endpoints auxiliares para grupos Whatsmeow e para abrir conversa privada com participante de grupo.',
    endpoints: [
      {
        method: 'GET',
        path: '/api/v1/accounts/{account_id}/inboxes/{inbox_id}/whatsmeow_groups',
        title: 'Listar grupos da instancia',
        note: 'Retorna grupos do WhatsApp conectado naquela inbox.',
      },
      {
        method: 'GET',
        path: '/api/v1/accounts/{account_id}/inboxes/{inbox_id}/whatsmeow_group_members?group_jid={group_jid}',
        title: 'Listar membros de um grupo',
        note: 'Use group_jid terminado em @g.us.',
      },
      {
        method: 'POST',
        path: '/api/v1/accounts/{account_id}/inboxes/{inbox_id}/whatsmeow_direct_conversation',
        title: 'Abrir conversa privada com participante',
        note: 'Cria ou abre conversa interna. Nao envia mensagem sozinho.',
        body: `{
  "participant_jid": "556391234567@s.whatsapp.net",
  "participant_lid_jid": "",
  "participant_phone": "556391234567",
  "participant_name": "Cliente Exemplo"
}`,
      },
    ],
  },
  {
    title: 'Webhooks para n8n',
    icon: 'i-lucide-radio',
    description:
      'Use webhooks quando quiser acionar um fluxo n8n a partir de eventos do Chatwoot.',
    endpoints: [
      {
        method: 'GET',
        path: '/api/v1/accounts/{account_id}/webhooks',
        title: 'Listar webhooks cadastrados',
        note: 'Mostra as URLs que recebem eventos da conta.',
      },
      {
        method: 'POST',
        path: '/api/v1/accounts/{account_id}/webhooks',
        title: 'Criar webhook',
        note: 'No fluxo de atendimento, filtre event message_created, message_type incoming e ignore outgoing.',
        body: `{
  "webhook": {
    "url": "https://n8n.seudominio.com/webhook/chatwoot",
    "subscriptions": ["message_created", "conversation_updated"]
  }
}`,
      },
    ],
  },
];

const n8nRecipes = [
  {
    title: 'Resolver instancia por nome',
    steps: [
      'Ler o nome da instancia da planilha ou do seletor manual.',
      'Chamar GET /inboxes.',
      'Filtrar payload[] por channel_type Channel::Whatsmeow.',
      'Comparar name em minusculo com o valor digitado.',
      'Usar id como inbox_id, channel_id para referencia e phone_number para registrar a instancia usada.',
    ],
  },
  {
    title: 'Disparo seguro por Google Sheets',
    steps: [
      'Ler apenas contatos com status Aguardando e prioridade Media ou Alta.',
      'Normalizar telefone para 55 + DDD + numero, somente digitos.',
      'Remover duplicados antes do Limit para duplicado nao ocupar vaga.',
      'Verificar formato minimo antes de chamar Whatsmeow.',
      'Chamar check_number e seguir somente se is_on_whatsapp for true.',
      'Buscar ou criar contato no Chatwoot usando inbox_id e source_id.',
      'Criar conversa, enviar texto e depois enviar os audios via multipart.',
      'Atualizar status, instancia e data na planilha.',
    ],
  },
  {
    title: 'Extrator de contatos Maps',
    steps: [
      'Salvar nome, telefone, cidade, segmento e prioridade.',
      'Prioridade Alta: supermercado, atacarejo, hortifruti, moveis, eletro, construcao, roupas e calcados.',
      'Prioridade Media: farmacia, pet shop, oficinas, lojas locais, academias, material agricola e servicos com promocao.',
      'Prioridade Baixa: negocios com baixa chance de carro de som ou sem telefone claro.',
      'No disparador, enviar somente Media e Alta; Baixa fica para revisao manual.',
    ],
  },
];

const commonErrors = [
  {
    title: '401 ou 403',
    text: 'Token ausente, token errado ou usuario sem permissao na conta. Confira api_access_token e account_id.',
  },
  {
    title: 'Numero invalido',
    text: 'Telefone com letras, curto demais ou sem DDD. Normalize antes do check_number.',
  },
  {
    title: 'Sessao desconectada',
    text: 'A instancia nao esta connected. Consulte whatsmeow_status antes do lote.',
  },
  {
    title: 'Audio virou link',
    text: 'O node enviou texto em vez de multipart. Baixe o arquivo e envie em attachments[].',
  },
  {
    title: 'Audio virou voz gravada',
    text: 'content_attributes tem whatsmeow_recorded_audio true. Para exemplo de locucao normal, use false.',
  },
  {
    title: 'Duplicado disparado',
    text: 'Compare pelo telefone normalizado antes do Limit e marque duplicados na planilha.',
  },
];

const curlForEndpoint = endpoint => {
  const url = endpointUrl(endpoint);
  const headers = endpoint.multipart
    ? `  -H "api_access_token: SEU_TOKEN_DE_ACESSO"`
    : `  -H "api_access_token: SEU_TOKEN_DE_ACESSO" \\
  -H "Content-Type: application/json"`;
  const data = endpoint.body
    ? ` \\
  -d '${endpoint.body}'`
    : '';

  return `curl -X ${endpoint.method} "${url}" \\
${headers}${data}`;
};

const copyValue = async (value, key) => {
  await copyTextToClipboard(replaceTokens(value));
  copiedKey.value = key;
  useAlert('Copiado para a area de transferencia.');
  window.setTimeout(() => {
    if (copiedKey.value === key) {
      copiedKey.value = '';
    }
  }, 1800);
};

onMounted(() => {
  if (!store.getters['inboxes/getInboxes'].length) {
    store.dispatch('inboxes/get');
  }
});
</script>

<template>
  <!-- eslint-disable vue/no-bare-strings-in-template -->
  <!-- eslint-disable @intlify/vue-i18n/no-raw-text -->
  <div class="flex-1 min-h-0 overflow-y-auto bg-n-background">
    <div class="w-full px-4 py-6 mx-auto max-w-7xl sm:px-6 lg:px-8">
      <section
        class="grid gap-6 pb-6 border-b border-n-weak lg:grid-cols-[1.35fr_0.65fr]"
      >
        <div class="min-w-0">
          <div class="flex items-center gap-3 mb-5">
            <span
              class="inline-flex items-center justify-center rounded-lg size-10 bg-n-brand/10 text-n-brand"
            >
              <i class="i-lucide-book-open-text size-5" />
            </span>
            <div class="min-w-0">
              <p class="text-sm font-medium text-n-slate-10">Manual interno</p>
              <h1
                class="text-2xl font-semibold tracking-normal break-words text-n-slate-12"
              >
                Documentacao da API Chatwoot + Whatsmeow
              </h1>
            </div>
          </div>
          <p class="max-w-3xl text-sm leading-6 text-n-slate-11">
            Esta pagina resume os endpoints usados pelos fluxos do n8n para
            listar instancias, verificar WhatsApp, criar contatos, abrir
            conversas, enviar texto, enviar audio e manter a planilha sem
            duplicidade.
          </p>
        </div>

        <div
          class="grid grid-cols-2 gap-3 p-3 border rounded-lg border-n-weak bg-n-surface-1"
        >
          <div
            v-for="stat in overviewStats"
            :key="stat.label"
            class="min-w-0 p-3 rounded-md bg-n-alpha-1"
          >
            <div class="flex items-center gap-2 text-xs text-n-slate-10">
              <i :class="stat.icon" class="size-4 shrink-0" />
              <span class="truncate">{{ stat.label }}</span>
            </div>
            <div class="mt-2 text-sm font-semibold truncate text-n-slate-12">
              {{ stat.value }}
            </div>
          </div>
        </div>
      </section>

      <section class="grid gap-4 py-6 lg:grid-cols-2">
        <div class="p-4 border rounded-lg border-n-weak bg-n-surface-1">
          <div class="flex items-start justify-between gap-3">
            <div>
              <h2 class="text-base font-semibold text-n-slate-12">
                Autenticacao
              </h2>
              <p class="mt-1 text-sm text-n-slate-10">
                Para automacoes, use o token do perfil no header.
              </p>
            </div>
            <Button
              icon="i-lucide-copy"
              slate
              ghost
              sm
              title="Copiar headers JSON"
              @click="copyValue(authHeaders, 'auth-json')"
            />
          </div>
          <pre
            class="p-3 mt-4 overflow-x-auto text-xs border rounded-md bg-n-alpha-1 border-n-weak text-n-slate-12"
          ><code>{{ authHeaders }}</code></pre>
        </div>

        <div class="p-4 border rounded-lg border-n-weak bg-n-surface-1">
          <div class="flex items-start justify-between gap-3">
            <div>
              <h2 class="text-base font-semibold text-n-slate-12">
                Anexos e audios
              </h2>
              <p class="mt-1 text-sm text-n-slate-10">
                Para audio, imagem, video ou documento, envie multipart.
              </p>
            </div>
            <Button
              icon="i-lucide-copy"
              slate
              ghost
              sm
              title="Copiar headers multipart"
              @click="copyValue(multipartHeaders, 'auth-multipart')"
            />
          </div>
          <pre
            class="p-3 mt-4 overflow-x-auto text-xs border rounded-md bg-n-alpha-1 border-n-weak text-n-slate-12"
          ><code>{{ multipartHeaders }}</code></pre>
        </div>
      </section>

      <section class="py-6 border-t border-n-weak">
        <div class="flex items-center justify-between gap-3 mb-4">
          <div>
            <h2 class="text-lg font-semibold text-n-slate-12">
              Instancias atuais
            </h2>
            <p class="mt-1 text-sm text-n-slate-10">
              Dados carregados da conta logada em tempo real.
            </p>
          </div>
          <Button
            icon="i-lucide-refresh-cw"
            slate
            outline
            sm
            title="Recarregar instancias"
            @click="store.dispatch('inboxes/get')"
          />
        </div>

        <div
          class="overflow-hidden border rounded-lg border-n-weak bg-n-surface-1"
        >
          <div class="overflow-x-auto">
            <table class="w-full text-sm text-left">
              <thead
                class="border-b bg-n-alpha-1 border-n-weak text-n-slate-10"
              >
                <tr>
                  <th class="px-4 py-3 font-medium">Instancia</th>
                  <th class="px-4 py-3 font-medium">Inbox ID</th>
                  <th class="px-4 py-3 font-medium">Channel ID</th>
                  <th class="px-4 py-3 font-medium">Telefone</th>
                  <th class="px-4 py-3 font-medium">Status</th>
                </tr>
              </thead>
              <tbody class="divide-y divide-n-weak">
                <tr v-for="inbox in whatsmeowInboxes" :key="inbox.id">
                  <td class="px-4 py-3 font-medium text-n-slate-12">
                    {{ inbox.name }}
                  </td>
                  <td class="px-4 py-3 font-mono text-n-slate-11">
                    {{ inbox.id }}
                  </td>
                  <td class="px-4 py-3 font-mono text-n-slate-11">
                    {{ inbox.channel_id }}
                  </td>
                  <td class="px-4 py-3 font-mono text-n-slate-11">
                    {{ inbox.phone_number || '-' }}
                  </td>
                  <td class="px-4 py-3">
                    <span
                      class="inline-flex items-center gap-1.5 px-2 py-1 text-xs font-medium rounded-md"
                      :class="
                        inbox.status === 'connected'
                          ? 'bg-n-teal-9/10 text-n-teal-11'
                          : 'bg-n-ruby-9/10 text-n-ruby-11'
                      "
                    >
                      <i
                        :class="
                          inbox.status === 'connected'
                            ? 'i-lucide-check-circle'
                            : 'i-lucide-circle-alert'
                        "
                        class="size-3"
                      />
                      {{ inbox.status || 'sem status' }}
                    </span>
                  </td>
                </tr>
                <tr v-if="!whatsmeowInboxes.length">
                  <td colspan="5" class="px-4 py-8 text-center text-n-slate-10">
                    Nenhuma instancia Whatsmeow foi encontrada nesta conta.
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>
      </section>

      <section class="py-6 border-t border-n-weak">
        <div class="mb-5">
          <h2 class="text-lg font-semibold text-n-slate-12">Endpoints</h2>
          <p class="mt-1 text-sm text-n-slate-10">
            Os exemplos abaixo ja usam a conta atual quando disponivel.
          </p>
        </div>

        <div class="space-y-6">
          <div
            v-for="group in endpointGroups"
            :key="group.title"
            class="border rounded-lg border-n-weak bg-n-surface-1"
          >
            <div class="flex gap-3 p-4 border-b border-n-weak">
              <span
                class="inline-flex items-center justify-center rounded-md size-9 bg-n-alpha-1 text-n-slate-11"
              >
                <i :class="group.icon" class="size-4" />
              </span>
              <div>
                <h3 class="text-base font-semibold text-n-slate-12">
                  {{ group.title }}
                </h3>
                <p class="mt-1 text-sm text-n-slate-10">
                  {{ group.description }}
                </p>
              </div>
            </div>

            <div class="divide-y divide-n-weak">
              <article
                v-for="endpoint in group.endpoints"
                :key="`${group.title}-${endpoint.title}`"
                class="grid gap-4 p-4 lg:grid-cols-[0.9fr_1.1fr]"
              >
                <div class="min-w-0">
                  <div class="flex flex-wrap items-center gap-2">
                    <span
                      class="px-2 py-1 font-mono text-xs font-semibold rounded-md bg-n-alpha-1 text-n-slate-12"
                    >
                      {{ endpoint.method }}
                    </span>
                    <h4 class="font-semibold text-n-slate-12">
                      {{ endpoint.title }}
                    </h4>
                  </div>
                  <p class="mt-3 text-sm leading-6 text-n-slate-10">
                    {{ endpoint.note }}
                  </p>
                  <code
                    class="block p-3 mt-3 overflow-x-auto text-xs border rounded-md border-n-weak bg-n-alpha-1 text-n-slate-12"
                  >
                    {{ replaceTokens(endpoint.path) }}
                  </code>
                </div>

                <div class="min-w-0 space-y-3">
                  <div class="flex items-center justify-end gap-2">
                    <Button
                      icon="i-lucide-copy"
                      slate
                      ghost
                      xs
                      title="Copiar URL"
                      @click="
                        copyValue(
                          endpointUrl(endpoint),
                          `${group.title}-${endpoint.title}-url`
                        )
                      "
                    />
                    <Button
                      icon="i-lucide-terminal"
                      slate
                      ghost
                      xs
                      title="Copiar cURL"
                      @click="
                        copyValue(
                          curlForEndpoint(endpoint),
                          `${group.title}-${endpoint.title}-curl`
                        )
                      "
                    />
                  </div>
                  <pre
                    v-if="endpoint.body"
                    class="p-3 overflow-x-auto text-xs border rounded-md bg-n-alpha-1 border-n-weak text-n-slate-12"
                  ><code>{{ endpoint.body }}</code></pre>
                  <pre
                    v-if="endpoint.multipart"
                    class="p-3 overflow-x-auto text-xs border rounded-md bg-n-alpha-1 border-n-weak text-n-slate-12"
                  ><code>{{ endpoint.multipart }}</code></pre>
                  <pre
                    v-if="endpoint.response"
                    class="p-3 overflow-x-auto text-xs border rounded-md bg-n-alpha-1 border-n-weak text-n-slate-12"
                  ><code>{{ endpoint.response }}</code></pre>
                </div>
              </article>
            </div>
          </div>
        </div>
      </section>

      <section class="grid gap-6 py-6 border-t border-n-weak lg:grid-cols-3">
        <div
          v-for="recipe in n8nRecipes"
          :key="recipe.title"
          class="p-4 border rounded-lg border-n-weak bg-n-surface-1"
        >
          <h2 class="text-base font-semibold text-n-slate-12">
            {{ recipe.title }}
          </h2>
          <ol class="mt-4 space-y-3 text-sm leading-6 text-n-slate-10">
            <li
              v-for="(step, index) in recipe.steps"
              :key="step"
              class="flex gap-3"
            >
              <span
                class="flex items-center justify-center flex-none mt-0.5 text-xs font-semibold rounded-md size-5 bg-n-alpha-1 text-n-slate-11"
              >
                {{ index + 1 }}
              </span>
              <span>{{ step }}</span>
            </li>
          </ol>
        </div>
      </section>

      <section class="py-6 border-t border-n-weak">
        <h2 class="text-lg font-semibold text-n-slate-12">Erros comuns</h2>
        <div class="grid gap-3 mt-4 md:grid-cols-2 xl:grid-cols-3">
          <div
            v-for="error in commonErrors"
            :key="error.title"
            class="p-4 border rounded-lg border-n-weak bg-n-surface-1"
          >
            <div class="flex items-center gap-2 font-semibold text-n-slate-12">
              <i class="i-lucide-circle-alert size-4 text-n-amber-9" />
              <span>{{ error.title }}</span>
            </div>
            <p class="mt-2 text-sm leading-6 text-n-slate-10">
              {{ error.text }}
            </p>
          </div>
        </div>
      </section>

      <section class="py-6 border-t border-n-weak">
        <div class="p-4 border rounded-lg border-n-weak bg-n-surface-1">
          <h2 class="text-base font-semibold text-n-slate-12">
            Padrao recomendado para n8n
          </h2>
          <pre
            class="p-3 mt-4 overflow-x-auto text-xs border rounded-md bg-n-alpha-1 border-n-weak text-n-slate-12"
          ><code>{{ `Base Chatwoot: ${chatwootApiBase}
Listar instancias: GET ${chatwootApiBase}/inboxes
Verificar numero: GET ${WHATSMEOW_BASE_URL}/sessions/{inbox_id}/check_number?phone={telefone}
Criar contato: POST ${chatwootApiBase}/contacts
Criar conversa: POST ${chatwootApiBase}/conversations
Enviar mensagem: POST ${chatwootApiBase}/conversations/{conversation_id}/messages` }}</code></pre>
        </div>
      </section>
    </div>
  </div>
</template>
