<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useStore } from 'vuex';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import MarcosxAiAPI from 'dashboard/api/marcosxAi';

const copy = {
  title: 'MarcosX IA',
  subtitle:
    'Atendimento nativo para Chatwoot e Whatsmeow com modelos, chaves e pausa por humano por conta.',
  readOnly:
    'Voce pode acompanhar a configuracao, mas somente administradores podem alterar chaves e assistentes.',
  tabs: {
    overview: 'Visao geral',
    settings: 'Configuracao',
    credentials: 'Credenciais',
    assistants: 'Assistentes',
    inboxes: 'Caixas de entrada',
    playground: 'Playground',
    google: 'Google',
  },
  stats: {
    assistants: 'Assistentes',
    credentials: 'Credenciais ativas',
    inboxes: 'Caixas vinculadas',
    google: 'Google',
  },
  status: {
    connected: 'Conectado',
    disconnected: 'Nao conectado',
    active: 'Ativo',
    inactive: 'Inativo',
    ready: 'Pronto',
  },
  actions: {
    refresh: 'Atualizar',
    save: 'Salvar',
    saving: 'Salvando',
    test: 'Testar',
    testing: 'Testando',
    create: 'Criar assistente',
    newAssistant: 'Novo assistente',
    deleteAssistant: 'Excluir assistente',
    connectInbox: 'Vincular caixa',
    disconnect: 'Desvincular',
    send: 'Enviar teste',
    connectGoogle: 'Continuar com Google',
  },
  preferences: {
    title: 'Padroes da conta',
    description:
      'Esses valores entram como base para novos assistentes e para o runtime automatico.',
    provider: 'Provedor padrao',
    model: 'Modelo padrao',
    temperature: 'Temperatura',
    delay: 'Delay de resposta',
    history: 'Limite de historico',
    humanPause: 'Bloqueio apos humano',
  },
  credentials: {
    title: 'Chaves de IA',
    description:
      'As chaves ficam salvas por conta e nunca voltam para a interface depois de gravadas.',
    apiKey: 'Chave de API',
    apiBase: 'Endpoint opcional',
    model: 'Modelo padrao',
    enabled: 'Habilitar provedor',
    saved: 'Chave salva',
    notSaved: 'Sem chave',
    placeholder: 'Cole uma nova chave para atualizar',
  },
  assistant: {
    listTitle: 'Assistentes',
    empty: 'Nenhum assistente criado ainda.',
    formTitle: 'Configuracao do assistente',
    name: 'Nome',
    description: 'Descricao',
    instructions: 'Instrucao principal',
    provider: 'Provedor',
    model: 'Modelo',
    temperature: 'Temperatura',
    delay: 'Delay em segundos',
    history: 'Mensagens no contexto',
    humanPause: 'Bloqueio humano em minutos',
    autoResponse: 'Responder automaticamente',
    fallback: 'Mensagem de fallback',
    handoff: 'Mensagem de transferencia',
    confirmDelete: 'Excluir este assistente da MarcosX IA?',
  },
  inboxes: {
    title: 'Caixas atendidas pela IA',
    description:
      'Quando uma mensagem incoming chegar nessas caixas, a MarcosX IA agenda a resposta e revalida pausa antes de enviar.',
    select: 'Selecione uma caixa de entrada',
    linked: 'Vinculadas',
    available: 'Disponiveis',
    noLinked: 'Nenhuma caixa vinculada a este assistente.',
    usedByOther: 'Vinculada a outro assistente',
  },
  playground: {
    title: 'Teste sem enviar mensagem real',
    description:
      'Use o prompt e modelo do assistente selecionado para validar respostas antes de ativar em uma caixa.',
    message: 'Mensagem do cliente',
    response: 'Resposta da IA',
    empty: 'A resposta gerada vai aparecer aqui.',
    noAssistant: 'Crie ou selecione um assistente antes de testar.',
  },
  google: {
    title: 'Google por conta',
    description:
      'A base de OAuth ja fica pronta para Gmail e Agenda. As ferramentas de envio e agendamento entram na proxima fase.',
    scopes: 'Escopos preparados: Gmail send e Calendar events.',
  },
  notices: {
    loaded: 'MarcosX IA atualizada.',
    saved: 'Configuracao salva.',
    credentialSaved: 'Credencial salva.',
    credentialDeleted: 'Credencial removida.',
    credentialOk: 'Conexao testada com sucesso.',
    assistantSaved: 'Assistente salvo.',
    assistantDeleted: 'Assistente excluido.',
    inboxLinked: 'Caixa vinculada.',
    inboxUnlinked: 'Caixa desvinculada.',
    error: 'Nao foi possivel concluir a acao.',
  },
};

const defaultAssistantConfig = () => ({
  provider: 'openai',
  model: 'gpt-4.1-mini',
  temperature: 0.7,
  response_delay_seconds: 3,
  history_limit: 20,
  human_pause_minutes: 60,
  auto_response_enabled: true,
  fallback_message:
    'Estou com dificuldade para responder agora. Um atendente vai continuar por aqui.',
  handoff_message: 'Vou chamar um atendente para continuar seu atendimento.',
});

const defaultAssistantForm = () => ({
  id: null,
  name: 'Atendimento MarcosX',
  description: '',
  instructions:
    'Voce e a MarcosX IA. Responda com clareza, seja breve quando possivel e transfira para humano quando faltar informacao.',
  config: defaultAssistantConfig(),
});

const providerOrder = ['openai', 'groq', 'gemini'];
const routeTabs = {
  respostas: 'overview',
  faqs: 'overview',
  captain_assistants_responses_index: 'overview',
  captain_assistants_documents_index: 'assistants',
  captain_assistants_scenarios_index: 'credentials',
  captain_assistants_playground_index: 'playground',
  captain_assistants_inboxes_index: 'inboxes',
  captain_tools_index: 'google',
  captain_assistants_settings_index: 'settings',
  documents: 'assistants',
  scenarios: 'credentials',
  playground: 'playground',
  inboxes: 'inboxes',
  tools: 'google',
  settings: 'settings',
};

const route = useRoute();
const router = useRouter();
const store = useStore();

const isLoading = ref(false);
const isSavingPreferences = ref(false);
const isSavingAssistant = ref(false);
const isRunningPlayground = ref(false);
const testingProvider = ref('');
const activeTab = ref('overview');
const activeAssistantId = ref(null);
const selectedInboxId = ref('');
const playgroundMessage = ref('');
const playgroundResponse = ref('');
const preferences = ref({
  providers: {},
  features: {},
  settings: {},
  google_connection: null,
});
const credentials = ref([]);
const credentialForms = ref({});
const assistants = ref([]);
const linkedInboxes = ref([]);
const availableInboxes = ref([]);
const assistantForm = ref(defaultAssistantForm());

const isAdmin = computed(
  () => store.getters.getCurrentRole === 'administrator'
);
const providerDefinitions = computed(() => preferences.value.providers || {});
const providers = computed(() =>
  providerOrder
    .map(key => ({ key, ...(providerDefinitions.value[key] || {}) }))
    .filter(provider => provider.display_name)
);
const linkedInboxIds = computed(
  () => new Set(linkedInboxes.value.map(inbox => inbox.id))
);
const availableToLink = computed(() =>
  availableInboxes.value.filter(inbox => !linkedInboxIds.value.has(inbox.id))
);
const activeAssistant = computed(() =>
  assistants.value.find(assistant => assistant.id === activeAssistantId.value)
);
const selectedProvider = computed(() =>
  providers.value.find(
    provider => provider.key === assistantForm.value.config.provider
  )
);
const googleConnection = computed(() => preferences.value.google_connection);
const isGoogleConnected = computed(
  () => googleConnection.value?.status === 'connected'
);
const statCards = computed(() => [
  {
    icon: 'i-lucide-bot',
    label: copy.stats.assistants,
    value: assistants.value.length,
  },
  {
    icon: 'i-lucide-key-round',
    label: copy.stats.credentials,
    value: `${credentials.value.filter(item => item.enabled).length}/${
      providers.value.length
    }`,
  },
  {
    icon: 'i-lucide-inbox',
    label: copy.stats.inboxes,
    value: linkedInboxes.value.length,
  },
  {
    icon: 'i-lucide-calendar-check',
    label: copy.stats.google,
    value: isGoogleConnected.value
      ? copy.status.connected
      : copy.status.disconnected,
  },
]);

const credentialFor = providerKey =>
  credentials.value.find(credential => credential.provider === providerKey);

const providerName = providerKey =>
  providers.value.find(provider => provider.key === providerKey)
    ?.display_name || providerKey;

const numberValue = value => Number(value || 0);

const normalizeRouteTab = value => routeTabs[value] || value || 'overview';

const syncActiveTabFromRoute = value => {
  const nextTab = normalizeRouteTab(value);
  activeTab.value = copy.tabs[nextTab] ? nextTab : 'overview';
};

const goToTab = tabKey => {
  activeTab.value = tabKey;
  router.replace({
    name: 'captain_assistants_index',
    params: { accountId: route.params.accountId, navigationPath: tabKey },
  });
};

const normalizeCredentialForms = () => {
  const forms = {};
  providers.value.forEach(provider => {
    const existing = credentialFor(provider.key);
    forms[provider.key] = {
      api_key: '',
      api_base: existing?.api_base || provider.default_api_base || '',
      model: existing?.model || provider.default_model || '',
      enabled: existing?.enabled ?? true,
    };
  });
  credentialForms.value = forms;
};

const setAssistantForm = assistant => {
  if (!assistant) {
    assistantForm.value = defaultAssistantForm();
    activeAssistantId.value = null;
    return;
  }

  activeAssistantId.value = assistant.id;
  assistantForm.value = {
    id: assistant.id,
    name: assistant.name || '',
    description: assistant.description || '',
    instructions: assistant.instructions || '',
    config: {
      ...defaultAssistantConfig(),
      ...(assistant.config || {}),
    },
  };
};

const loadPreferences = async () => {
  const { data } = await MarcosxAiAPI.getPreferences();
  preferences.value = data;
  credentials.value = data.credentials || [];
  normalizeCredentialForms();
};

const loadAssistants = async () => {
  const { data } = await MarcosxAiAPI.getAssistants();
  assistants.value = data.assistants || [];
  const selected = assistants.value.find(
    assistant => assistant.id === activeAssistantId.value
  );
  setAssistantForm(selected || assistants.value[0]);
};

const loadInboxes = async () => {
  if (!activeAssistantId.value) {
    linkedInboxes.value = [];
    availableInboxes.value = [];
    return;
  }

  const { data } = await MarcosxAiAPI.getAssistantInboxes(
    activeAssistantId.value
  );
  linkedInboxes.value = data.inboxes || [];
  availableInboxes.value = data.available_inboxes || [];
};

const refreshAll = async ({ notify = false } = {}) => {
  isLoading.value = true;
  try {
    await loadPreferences();
    await loadAssistants();
    await loadInboxes();
    if (notify) useAlert(copy.notices.loaded);
  } catch (error) {
    useAlert(error?.response?.data?.error || copy.notices.error);
  } finally {
    isLoading.value = false;
  }
};

const savePreferences = async () => {
  isSavingPreferences.value = true;
  try {
    const settings = preferences.value.settings || {};
    const { data } = await MarcosxAiAPI.updatePreferences({
      settings: {
        default_provider: settings.default_provider,
        default_model: settings.default_model,
        temperature: numberValue(settings.temperature),
        response_delay_seconds: numberValue(settings.response_delay_seconds),
        history_limit: numberValue(settings.history_limit),
        human_pause_minutes: numberValue(settings.human_pause_minutes),
      },
    });
    preferences.value = data;
    useAlert(copy.notices.saved);
  } catch (error) {
    useAlert(error?.response?.data?.error || copy.notices.error);
  } finally {
    isSavingPreferences.value = false;
  }
};

const saveCredential = async provider => {
  const form = credentialForms.value[provider.key];
  const existing = credentialFor(provider.key);

  try {
    const { data } = await MarcosxAiAPI.saveCredential(existing?.id, {
      credential: {
        provider: provider.key,
        api_key: form.api_key,
        api_base: form.api_base,
        model: form.model,
        enabled: form.enabled,
      },
    });
    credentials.value = [
      ...credentials.value.filter(item => item.provider !== provider.key),
      data.credential,
    ].sort((a, b) => a.provider.localeCompare(b.provider));
    form.api_key = '';
    useAlert(copy.notices.credentialSaved);
  } catch (error) {
    useAlert(error?.response?.data?.error || copy.notices.error);
  }
};

const deleteCredential = async provider => {
  const existing = credentialFor(provider.key);
  if (!existing) return;

  try {
    await MarcosxAiAPI.deleteCredential(existing.id);
    credentials.value = credentials.value.filter(
      item => item.provider !== provider.key
    );
    normalizeCredentialForms();
    useAlert(copy.notices.credentialDeleted);
  } catch (error) {
    useAlert(error?.response?.data?.error || copy.notices.error);
  }
};

const testCredential = async provider => {
  testingProvider.value = provider.key;
  try {
    await MarcosxAiAPI.testCredential(provider.key);
    useAlert(copy.notices.credentialOk);
  } catch (error) {
    useAlert(error?.response?.data?.error || copy.notices.error);
  } finally {
    testingProvider.value = '';
  }
};

const saveAssistant = async () => {
  isSavingAssistant.value = true;
  const form = assistantForm.value;
  const payload = {
    assistant: {
      name: form.name,
      description: form.description,
      instructions: form.instructions,
      config: {
        ...form.config,
        temperature: numberValue(form.config.temperature),
        response_delay_seconds: numberValue(form.config.response_delay_seconds),
        history_limit: numberValue(form.config.history_limit),
        human_pause_minutes: numberValue(form.config.human_pause_minutes),
      },
    },
  };

  try {
    const { data } = form.id
      ? await MarcosxAiAPI.updateAssistant(form.id, payload)
      : await MarcosxAiAPI.createAssistant(payload);
    const savedAssistant = data.assistant;
    assistants.value = [
      ...assistants.value.filter(
        assistant => assistant.id !== savedAssistant.id
      ),
      savedAssistant,
    ].sort((a, b) => a.name.localeCompare(b.name));
    setAssistantForm(savedAssistant);
    await loadInboxes();
    useAlert(copy.notices.assistantSaved);
  } catch (error) {
    useAlert(error?.response?.data?.error || copy.notices.error);
  } finally {
    isSavingAssistant.value = false;
  }
};

const deleteAssistant = async () => {
  if (
    !assistantForm.value.id ||
    // eslint-disable-next-line no-alert
    !window.confirm(copy.assistant.confirmDelete)
  ) {
    return;
  }

  try {
    await MarcosxAiAPI.deleteAssistant(assistantForm.value.id);
    assistants.value = assistants.value.filter(
      assistant => assistant.id !== assistantForm.value.id
    );
    setAssistantForm(assistants.value[0]);
    await loadInboxes();
    useAlert(copy.notices.assistantDeleted);
  } catch (error) {
    useAlert(error?.response?.data?.error || copy.notices.error);
  }
};

const linkInbox = async () => {
  if (!selectedInboxId.value || !activeAssistantId.value) return;

  try {
    await MarcosxAiAPI.linkAssistantInbox(
      activeAssistantId.value,
      selectedInboxId.value
    );
    selectedInboxId.value = '';
    await loadInboxes();
    await loadAssistants();
    useAlert(copy.notices.inboxLinked);
  } catch (error) {
    useAlert(error?.response?.data?.error || copy.notices.error);
  }
};

const unlinkInbox = async inbox => {
  try {
    await MarcosxAiAPI.unlinkAssistantInbox(activeAssistantId.value, inbox.id);
    await loadInboxes();
    await loadAssistants();
    useAlert(copy.notices.inboxUnlinked);
  } catch (error) {
    useAlert(error?.response?.data?.error || copy.notices.error);
  }
};

const runPlayground = async () => {
  if (!activeAssistantId.value) {
    useAlert(copy.playground.noAssistant);
    return;
  }

  isRunningPlayground.value = true;
  playgroundResponse.value = '';

  try {
    const { data } = await MarcosxAiAPI.runPlayground(activeAssistantId.value, {
      assistant: { message: playgroundMessage.value },
    });
    playgroundResponse.value = data.response;
  } catch (error) {
    useAlert(error?.response?.data?.error || copy.notices.error);
  } finally {
    isRunningPlayground.value = false;
  }
};

const connectGoogle = async () => {
  try {
    const { data } = await MarcosxAiAPI.createGoogleAuthorization();
    if (data.url) window.location.href = data.url;
  } catch (error) {
    useAlert(error?.response?.data?.error || copy.notices.error);
  }
};

watch(
  () => route.params.navigationPath,
  value => syncActiveTabFromRoute(value),
  { immediate: true }
);

watch(activeAssistantId, () => loadInboxes());

watch(
  () => assistantForm.value.config.provider,
  providerKey => {
    const provider = providers.value.find(item => item.key === providerKey);
    if (provider && !assistantForm.value.config.model) {
      assistantForm.value.config.model = provider.default_model;
    }
  }
);

onMounted(() => refreshAll());
</script>

<template>
  <section class="flex h-full min-h-0 w-full flex-col bg-n-background">
    <header class="border-b border-n-weak bg-n-background px-6 py-5">
      <div
        class="flex flex-col gap-4 xl:flex-row xl:items-start xl:justify-between"
      >
        <div class="min-w-0">
          <div class="mb-2 flex items-center gap-3">
            <span
              class="grid size-10 place-items-center rounded-lg bg-n-brand/10 text-n-blue-11"
            >
              <span class="i-lucide-sparkles size-5" />
            </span>
            <div>
              <h1 class="text-xl font-semibold leading-7 text-n-slate-12">
                {{ copy.title }}
              </h1>
              <p class="max-w-3xl text-sm text-n-slate-11">
                {{ copy.subtitle }}
              </p>
            </div>
          </div>
          <p
            v-if="!isAdmin"
            class="rounded-lg border border-n-amber-6 bg-n-amber-3 px-3 py-2 text-sm text-n-amber-11"
          >
            {{ copy.readOnly }}
          </p>
        </div>
        <Button
          :label="copy.actions.refresh"
          icon="i-lucide-refresh-cw"
          color="slate"
          variant="outline"
          size="sm"
          @click="refreshAll({ notify: true })"
        />
      </div>
      <nav class="mt-5 flex gap-2 overflow-x-auto">
        <button
          v-for="tab in Object.keys(copy.tabs)"
          :key="tab"
          type="button"
          class="h-9 shrink-0 rounded-lg px-3 text-sm font-medium transition-colors"
          :class="
            activeTab === tab
              ? 'bg-n-brand text-white'
              : 'bg-n-alpha-2 text-n-slate-11 hover:bg-n-alpha-3'
          "
          @click="goToTab(tab)"
        >
          {{ copy.tabs[tab] }}
        </button>
      </nav>
    </header>

    <main class="min-h-0 flex-1 overflow-y-auto px-6 py-6">
      <div
        v-if="isLoading"
        class="grid min-h-[24rem] place-items-center text-n-slate-11"
      >
        <Spinner />
      </div>

      <div v-else class="mx-auto flex max-w-7xl flex-col gap-6">
        <section
          v-if="activeTab === 'overview'"
          class="grid gap-4 md:grid-cols-2 xl:grid-cols-4"
        >
          <article
            v-for="card in statCards"
            :key="card.label"
            class="rounded-lg border border-n-weak bg-n-surface-1 p-4"
          >
            <div class="mb-4 flex items-center justify-between">
              <span class="text-sm font-medium text-n-slate-11">
                {{ card.label }}
              </span>
              <span :class="card.icon" class="size-4 text-n-slate-10" />
            </div>
            <div class="text-2xl font-semibold text-n-slate-12">
              {{ card.value }}
            </div>
          </article>
        </section>

        <section
          v-if="activeTab === 'settings'"
          class="rounded-lg border border-n-weak bg-n-surface-1 p-5"
        >
          <div class="mb-5">
            <h2 class="text-base font-semibold text-n-slate-12">
              {{ copy.preferences.title }}
            </h2>
            <p class="text-sm text-n-slate-11">
              {{ copy.preferences.description }}
            </p>
          </div>
          <div class="grid gap-4 md:grid-cols-2 xl:grid-cols-3">
            <label class="grid gap-1 text-sm text-n-slate-11">
              {{ copy.preferences.provider }}
              <select
                v-model="preferences.settings.default_provider"
                :disabled="!isAdmin"
                class="h-10 rounded-lg border border-n-weak bg-n-background px-3 text-n-slate-12"
              >
                <option
                  v-for="provider in providers"
                  :key="provider.key"
                  :value="provider.key"
                >
                  {{ provider.display_name }}
                </option>
              </select>
            </label>
            <label class="grid gap-1 text-sm text-n-slate-11">
              {{ copy.preferences.model }}
              <input
                v-model="preferences.settings.default_model"
                :disabled="!isAdmin"
                class="h-10 rounded-lg border border-n-weak bg-n-background px-3 text-n-slate-12"
                type="text"
              />
            </label>
            <label class="grid gap-1 text-sm text-n-slate-11">
              {{ copy.preferences.temperature }}
              <input
                v-model.number="preferences.settings.temperature"
                :disabled="!isAdmin"
                class="h-10 rounded-lg border border-n-weak bg-n-background px-3 text-n-slate-12"
                max="2"
                min="0"
                step="0.1"
                type="number"
              />
            </label>
            <label class="grid gap-1 text-sm text-n-slate-11">
              {{ copy.preferences.delay }}
              <input
                v-model.number="preferences.settings.response_delay_seconds"
                :disabled="!isAdmin"
                class="h-10 rounded-lg border border-n-weak bg-n-background px-3 text-n-slate-12"
                min="0"
                type="number"
              />
            </label>
            <label class="grid gap-1 text-sm text-n-slate-11">
              {{ copy.preferences.history }}
              <input
                v-model.number="preferences.settings.history_limit"
                :disabled="!isAdmin"
                class="h-10 rounded-lg border border-n-weak bg-n-background px-3 text-n-slate-12"
                min="1"
                type="number"
              />
            </label>
            <label class="grid gap-1 text-sm text-n-slate-11">
              {{ copy.preferences.humanPause }}
              <input
                v-model.number="preferences.settings.human_pause_minutes"
                :disabled="!isAdmin"
                class="h-10 rounded-lg border border-n-weak bg-n-background px-3 text-n-slate-12"
                min="0"
                type="number"
              />
            </label>
          </div>
          <div v-if="isAdmin" class="mt-5 flex justify-end">
            <Button
              :is-loading="isSavingPreferences"
              :label="copy.actions.save"
              icon="i-lucide-save"
              @click="savePreferences"
            />
          </div>
        </section>

        <section v-if="activeTab === 'credentials'" class="grid gap-4">
          <div>
            <h2 class="text-base font-semibold text-n-slate-12">
              {{ copy.credentials.title }}
            </h2>
            <p class="text-sm text-n-slate-11">
              {{ copy.credentials.description }}
            </p>
          </div>
          <article
            v-for="provider in providers"
            :key="provider.key"
            class="rounded-lg border border-n-weak bg-n-surface-1 p-5"
          >
            <div
              class="mb-4 flex flex-col gap-2 md:flex-row md:items-center md:justify-between"
            >
              <div>
                <h3 class="font-semibold text-n-slate-12">
                  {{ provider.display_name }}
                </h3>
                <p class="text-sm text-n-slate-11">
                  {{
                    credentialFor(provider.key)
                      ? copy.credentials.saved
                      : copy.credentials.notSaved
                  }}
                </p>
              </div>
              <span
                class="w-fit rounded-full px-2 py-1 text-xs font-medium"
                :class="
                  credentialFor(provider.key)?.enabled
                    ? 'bg-n-teal-3 text-n-teal-11'
                    : 'bg-n-slate-3 text-n-slate-11'
                "
              >
                {{
                  credentialFor(provider.key)?.enabled
                    ? copy.status.active
                    : copy.status.inactive
                }}
              </span>
            </div>
            <div
              v-if="credentialForms[provider.key]"
              class="grid gap-4 md:grid-cols-2"
            >
              <label class="grid gap-1 text-sm text-n-slate-11">
                {{ copy.credentials.apiKey }}
                <input
                  v-model="credentialForms[provider.key].api_key"
                  :disabled="!isAdmin"
                  :placeholder="copy.credentials.placeholder"
                  class="h-10 rounded-lg border border-n-weak bg-n-background px-3 text-n-slate-12"
                  type="password"
                />
              </label>
              <label class="grid gap-1 text-sm text-n-slate-11">
                {{ copy.credentials.model }}
                <input
                  v-model="credentialForms[provider.key].model"
                  :disabled="!isAdmin"
                  class="h-10 rounded-lg border border-n-weak bg-n-background px-3 text-n-slate-12"
                  type="text"
                />
              </label>
              <label class="grid gap-1 text-sm text-n-slate-11 md:col-span-2">
                {{ copy.credentials.apiBase }}
                <input
                  v-model="credentialForms[provider.key].api_base"
                  :disabled="!isAdmin"
                  class="h-10 rounded-lg border border-n-weak bg-n-background px-3 text-n-slate-12"
                  type="url"
                />
              </label>
              <label class="flex items-center gap-2 text-sm text-n-slate-11">
                <input
                  v-model="credentialForms[provider.key].enabled"
                  :disabled="!isAdmin"
                  class="reset-base"
                  type="checkbox"
                />
                {{ copy.credentials.enabled }}
              </label>
              <div v-if="isAdmin" class="flex justify-end gap-2">
                <Button
                  :disabled="!credentialFor(provider.key)"
                  :is-loading="testingProvider === provider.key"
                  :label="copy.actions.test"
                  color="slate"
                  icon="i-lucide-zap"
                  variant="outline"
                  @click="testCredential(provider)"
                />
                <Button
                  v-if="credentialFor(provider.key)"
                  :label="copy.actions.disconnect"
                  color="ruby"
                  icon="i-lucide-trash-2"
                  variant="outline"
                  @click="deleteCredential(provider)"
                />
                <Button
                  :label="copy.actions.save"
                  icon="i-lucide-save"
                  @click="saveCredential(provider)"
                />
              </div>
            </div>
          </article>
        </section>

        <section
          v-if="activeTab === 'assistants'"
          class="grid gap-5 xl:grid-cols-[20rem_1fr]"
        >
          <aside class="rounded-lg border border-n-weak bg-n-surface-1 p-4">
            <div class="mb-4 flex items-center justify-between">
              <h2 class="font-semibold text-n-slate-12">
                {{ copy.assistant.listTitle }}
              </h2>
              <Button
                v-if="isAdmin"
                :label="copy.actions.newAssistant"
                color="slate"
                icon="i-lucide-plus"
                size="sm"
                variant="outline"
                @click="setAssistantForm(null)"
              />
            </div>
            <p v-if="assistants.length === 0" class="text-sm text-n-slate-11">
              {{ copy.assistant.empty }}
            </p>
            <button
              v-for="assistant in assistants"
              :key="assistant.id"
              type="button"
              class="mb-2 flex w-full items-start justify-between rounded-lg px-3 py-2 text-left"
              :class="
                assistant.id === activeAssistantId
                  ? 'bg-n-brand/10 text-n-blue-11'
                  : 'bg-n-alpha-2 text-n-slate-11 hover:bg-n-alpha-3'
              "
              @click="setAssistantForm(assistant)"
            >
              <span class="min-w-0">
                <span class="block truncate font-medium">
                  {{ assistant.name }}
                </span>
                <span class="block text-xs">
                  {{ providerName(assistant.config.provider) }}
                </span>
              </span>
              <span class="text-xs">{{ assistant.inboxes_count }}</span>
            </button>
          </aside>

          <form
            class="rounded-lg border border-n-weak bg-n-surface-1 p-5"
            @submit.prevent="saveAssistant"
          >
            <div
              class="mb-5 flex flex-col gap-2 md:flex-row md:items-center md:justify-between"
            >
              <div>
                <h2 class="text-base font-semibold text-n-slate-12">
                  {{ copy.assistant.formTitle }}
                </h2>
                <p v-if="activeAssistant" class="text-sm text-n-slate-11">
                  {{ activeAssistant.updated_at }}
                </p>
              </div>
              <Button
                v-if="isAdmin && assistantForm.id"
                :label="copy.actions.deleteAssistant"
                color="ruby"
                icon="i-lucide-trash-2"
                variant="outline"
                @click.prevent="deleteAssistant"
              />
            </div>
            <div class="grid gap-4 md:grid-cols-2">
              <label class="grid gap-1 text-sm text-n-slate-11">
                {{ copy.assistant.name }}
                <input
                  v-model="assistantForm.name"
                  :disabled="!isAdmin"
                  class="h-10 rounded-lg border border-n-weak bg-n-background px-3 text-n-slate-12"
                  required
                  type="text"
                />
              </label>
              <label class="grid gap-1 text-sm text-n-slate-11">
                {{ copy.assistant.description }}
                <input
                  v-model="assistantForm.description"
                  :disabled="!isAdmin"
                  class="h-10 rounded-lg border border-n-weak bg-n-background px-3 text-n-slate-12"
                  type="text"
                />
              </label>
              <label class="grid gap-1 text-sm text-n-slate-11 md:col-span-2">
                {{ copy.assistant.instructions }}
                <textarea
                  v-model="assistantForm.instructions"
                  :disabled="!isAdmin"
                  class="min-h-36 rounded-lg border border-n-weak bg-n-background px-3 py-2 text-n-slate-12"
                  required
                />
              </label>
              <label class="grid gap-1 text-sm text-n-slate-11">
                {{ copy.assistant.provider }}
                <select
                  v-model="assistantForm.config.provider"
                  :disabled="!isAdmin"
                  class="h-10 rounded-lg border border-n-weak bg-n-background px-3 text-n-slate-12"
                >
                  <option
                    v-for="provider in providers"
                    :key="provider.key"
                    :value="provider.key"
                  >
                    {{ provider.display_name }}
                  </option>
                </select>
              </label>
              <label class="grid gap-1 text-sm text-n-slate-11">
                {{ copy.assistant.model }}
                <input
                  v-model="assistantForm.config.model"
                  :disabled="!isAdmin"
                  :placeholder="selectedProvider?.default_model"
                  class="h-10 rounded-lg border border-n-weak bg-n-background px-3 text-n-slate-12"
                  required
                  type="text"
                />
              </label>
              <label class="grid gap-1 text-sm text-n-slate-11">
                {{ copy.assistant.temperature }}
                <input
                  v-model.number="assistantForm.config.temperature"
                  :disabled="!isAdmin"
                  class="h-10 rounded-lg border border-n-weak bg-n-background px-3 text-n-slate-12"
                  max="2"
                  min="0"
                  step="0.1"
                  type="number"
                />
              </label>
              <label class="grid gap-1 text-sm text-n-slate-11">
                {{ copy.assistant.delay }}
                <input
                  v-model.number="assistantForm.config.response_delay_seconds"
                  :disabled="!isAdmin"
                  class="h-10 rounded-lg border border-n-weak bg-n-background px-3 text-n-slate-12"
                  min="0"
                  type="number"
                />
              </label>
              <label class="grid gap-1 text-sm text-n-slate-11">
                {{ copy.assistant.history }}
                <input
                  v-model.number="assistantForm.config.history_limit"
                  :disabled="!isAdmin"
                  class="h-10 rounded-lg border border-n-weak bg-n-background px-3 text-n-slate-12"
                  min="1"
                  type="number"
                />
              </label>
              <label class="grid gap-1 text-sm text-n-slate-11">
                {{ copy.assistant.humanPause }}
                <input
                  v-model.number="assistantForm.config.human_pause_minutes"
                  :disabled="!isAdmin"
                  class="h-10 rounded-lg border border-n-weak bg-n-background px-3 text-n-slate-12"
                  min="0"
                  type="number"
                />
              </label>
              <label class="grid gap-1 text-sm text-n-slate-11 md:col-span-2">
                {{ copy.assistant.fallback }}
                <input
                  v-model="assistantForm.config.fallback_message"
                  :disabled="!isAdmin"
                  class="h-10 rounded-lg border border-n-weak bg-n-background px-3 text-n-slate-12"
                  type="text"
                />
              </label>
              <label class="grid gap-1 text-sm text-n-slate-11 md:col-span-2">
                {{ copy.assistant.handoff }}
                <input
                  v-model="assistantForm.config.handoff_message"
                  :disabled="!isAdmin"
                  class="h-10 rounded-lg border border-n-weak bg-n-background px-3 text-n-slate-12"
                  type="text"
                />
              </label>
              <label class="flex items-center gap-2 text-sm text-n-slate-11">
                <input
                  v-model="assistantForm.config.auto_response_enabled"
                  :disabled="!isAdmin"
                  class="reset-base"
                  type="checkbox"
                />
                {{ copy.assistant.autoResponse }}
              </label>
            </div>
            <div v-if="isAdmin" class="mt-5 flex justify-end">
              <Button
                :is-loading="isSavingAssistant"
                :label="
                  assistantForm.id ? copy.actions.save : copy.actions.create
                "
                icon="i-lucide-save"
                type="submit"
              />
            </div>
          </form>
        </section>

        <section
          v-if="activeTab === 'inboxes'"
          class="rounded-lg border border-n-weak bg-n-surface-1 p-5"
        >
          <div class="mb-5">
            <h2 class="text-base font-semibold text-n-slate-12">
              {{ copy.inboxes.title }}
            </h2>
            <p class="text-sm text-n-slate-11">
              {{ copy.inboxes.description }}
            </p>
          </div>
          <div class="mb-5 flex flex-col gap-3 md:flex-row">
            <select
              v-model="selectedInboxId"
              :disabled="!isAdmin || !activeAssistantId"
              class="h-10 min-w-0 flex-1 rounded-lg border border-n-weak bg-n-background px-3 text-n-slate-12"
            >
              <option value="">{{ copy.inboxes.select }}</option>
              <option
                v-for="inbox in availableToLink"
                :key="inbox.id"
                :disabled="Boolean(inbox.connected_assistant_id)"
                :value="inbox.id"
              >
                {{ inbox.name }}
                {{
                  inbox.connected_assistant_id ? copy.inboxes.usedByOther : ''
                }}
              </option>
            </select>
            <Button
              v-if="isAdmin"
              :disabled="!selectedInboxId || !activeAssistantId"
              :label="copy.actions.connectInbox"
              icon="i-lucide-link"
              @click="linkInbox"
            />
          </div>
          <div class="grid gap-3">
            <h3 class="text-sm font-semibold text-n-slate-12">
              {{ copy.inboxes.linked }}
            </h3>
            <p
              v-if="linkedInboxes.length === 0"
              class="text-sm text-n-slate-11"
            >
              {{ copy.inboxes.noLinked }}
            </p>
            <article
              v-for="inbox in linkedInboxes"
              :key="inbox.id"
              class="flex items-center justify-between rounded-lg border border-n-weak bg-n-background p-3"
            >
              <div>
                <h4 class="font-medium text-n-slate-12">{{ inbox.name }}</h4>
                <p class="text-xs text-n-slate-11">
                  {{ inbox.channel_type || inbox.inbox_type }}
                </p>
              </div>
              <Button
                v-if="isAdmin"
                :label="copy.actions.disconnect"
                color="ruby"
                icon="i-lucide-unlink"
                size="sm"
                variant="outline"
                @click="unlinkInbox(inbox)"
              />
            </article>
          </div>
        </section>

        <section
          v-if="activeTab === 'playground'"
          class="grid gap-5 xl:grid-cols-2"
        >
          <form
            class="rounded-lg border border-n-weak bg-n-surface-1 p-5"
            @submit.prevent="runPlayground"
          >
            <div class="mb-5">
              <h2 class="text-base font-semibold text-n-slate-12">
                {{ copy.playground.title }}
              </h2>
              <p class="text-sm text-n-slate-11">
                {{ copy.playground.description }}
              </p>
            </div>
            <label class="grid gap-1 text-sm text-n-slate-11">
              {{ copy.playground.message }}
              <textarea
                v-model="playgroundMessage"
                class="min-h-44 rounded-lg border border-n-weak bg-n-background px-3 py-2 text-n-slate-12"
                required
              />
            </label>
            <div class="mt-4 flex justify-end">
              <Button
                :disabled="!playgroundMessage"
                :is-loading="isRunningPlayground"
                :label="copy.actions.send"
                icon="i-lucide-send"
                type="submit"
              />
            </div>
          </form>
          <article class="rounded-lg border border-n-weak bg-n-surface-1 p-5">
            <h2 class="mb-3 text-base font-semibold text-n-slate-12">
              {{ copy.playground.response }}
            </h2>
            <p
              class="min-h-44 whitespace-pre-wrap rounded-lg bg-n-background p-4 text-sm text-n-slate-12"
            >
              {{ playgroundResponse || copy.playground.empty }}
            </p>
          </article>
        </section>

        <section
          v-if="activeTab === 'google'"
          class="rounded-lg border border-n-weak bg-n-surface-1 p-5"
        >
          <div
            class="flex flex-col gap-5 md:flex-row md:items-center md:justify-between"
          >
            <div>
              <h2 class="text-base font-semibold text-n-slate-12">
                {{ copy.google.title }}
              </h2>
              <p class="max-w-3xl text-sm text-n-slate-11">
                {{ copy.google.description }}
              </p>
              <p class="mt-2 text-sm text-n-slate-11">
                {{ googleConnection?.email || copy.google.scopes }}
              </p>
            </div>
            <div class="flex flex-col items-start gap-3 md:items-end">
              <span
                class="rounded-full px-2 py-1 text-xs font-medium"
                :class="
                  isGoogleConnected
                    ? 'bg-n-teal-3 text-n-teal-11'
                    : 'bg-n-slate-3 text-n-slate-11'
                "
              >
                {{
                  isGoogleConnected
                    ? copy.status.connected
                    : copy.status.disconnected
                }}
              </span>
              <Button
                v-if="isAdmin"
                :label="copy.actions.connectGoogle"
                icon="i-lucide-log-in"
                @click="connectGoogle"
              />
            </div>
          </div>
        </section>
      </div>
    </main>
  </section>
</template>
