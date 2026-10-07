<script setup>
import { computed, onMounted, ref } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import MarcosxAiAPI from 'dashboard/api/marcosxAi';
import AgentEditor from '../components/AgentEditor.vue';
import ProvidersPanel from '../components/ProvidersPanel.vue';
import AiPlayground from '../components/AiPlayground.vue';

const store = useStore();
const route = useRoute();
const router = useRouter();
const { t } = useI18n();
const canEdit = computed(
  () => store.getters.getCurrentRole === 'administrator'
);
const preferences = ref({});
const agents = ref([]);
const credentials = ref([]);
const catalogs = ref({});
const logs = ref([]);
const loading = ref(true);
const saving = ref(false);
const busyProvider = ref('');
const editing = ref(null);
const search = ref('');
const testAgentId = ref(null);
const inboxes = computed(() => store.getters['inboxes/getInboxes'] || []);
const tabs = [
  { id: 'overview', key: 'AGENTS', icon: 'i-lucide-bot' },
  { id: 'credentials', key: 'PROVIDERS', icon: 'i-lucide-plug-zap' },
  { id: 'playground', key: 'PLAYGROUND', icon: 'i-lucide-messages-square' },
  { id: 'activity', key: 'ACTIVITY', icon: 'i-lucide-activity' },
];
const activeTab = computed(() =>
  tabs.some(item => item.id === route.params.navigationPath)
    ? route.params.navigationPath
    : 'overview'
);
const visibleAgents = computed(() =>
  agents.value.filter(item =>
    `${item.name} ${item.description || ''}`
      .toLowerCase()
      .includes(search.value.toLowerCase())
  )
);
const notifyError = error =>
  useAlert(error.response?.data?.error || t('MARCOX_AI.ERROR'));
const loadModels = async (provider, refresh = false) => {
  try {
    const { data } = await MarcosxAiAPI.getModels(provider, refresh);
    catalogs.value[provider] = data;
  } catch (error) {
    if (refresh) notifyError(error);
  }
};
const navigate = id => {
  editing.value = null;
  router.replace({
    name: 'captain_assistants_index',
    params: { accountId: route.params.accountId, navigationPath: id },
  });
};
const refresh = async () => {
  loading.value = true;
  try {
    const [settings, profiles] = await Promise.all([
      MarcosxAiAPI.getPreferences(),
      MarcosxAiAPI.getAssistants(),
      store.dispatch('inboxes/get'),
    ]);
    preferences.value = settings.data;
    credentials.value = settings.data.credentials;
    agents.value = profiles.data.assistants;
    if (canEdit.value) {
      await Promise.all(
        Object.keys(settings.data.providers).map(provider =>
          loadModels(provider)
        )
      );
      const { data } = await MarcosxAiAPI.getLogs();
      logs.value = data.logs;
    }
  } catch (error) {
    notifyError(error);
  } finally {
    loading.value = false;
  }
};
onMounted(refresh);
const newAgent = () => {
  editing.value = {
    id: null,
    name: '',
    description: '',
    instructions: preferences.value.default_prompt || '',
    inbox_ids: [],
    config: { ...preferences.value.agent_defaults },
    response_guidelines: [],
    guardrails: [],
  };
};
const saveAgent = async form => {
  saving.value = true;
  try {
    const {
      id,
      name,
      description,
      instructions,
      config,
      inbox_ids: inboxIds,
      response_guidelines: guidelines,
      guardrails,
    } = form;
    const body = {
      assistant: {
        name,
        description,
        instructions,
        config,
        inbox_ids: inboxIds,
        response_guidelines: guidelines,
        guardrails,
      },
    };
    const { data } = id
      ? await MarcosxAiAPI.updateAssistant(id, body)
      : await MarcosxAiAPI.createAssistant(body);
    agents.value = [
      data.assistant,
      ...agents.value.filter(item => item.id !== id),
    ];
    editing.value = null;
    useAlert(t('MARCOX_AI.SAVED'));
  } catch (error) {
    notifyError(error);
  } finally {
    saving.value = false;
  }
};
const deleteAgent = async id => {
  if (!window.confirm(t('MARCOX_AI.EDITOR.CONFIRM_DELETE'))) return;
  try {
    await MarcosxAiAPI.deleteAssistant(id);
    agents.value = agents.value.filter(item => item.id !== id);
    editing.value = null;
  } catch (error) {
    notifyError(error);
  }
};
const testAgent = id => {
  testAgentId.value = id;
  navigate('playground');
};
const saveConnection = async (provider, form) => {
  busyProvider.value = provider;
  try {
    await MarcosxAiAPI.saveCredential(form.id, {
      credential: {
        provider,
        api_key: form.api_key,
        api_base: form.api_base,
        model: form.model,
        enabled: form.enabled,
      },
    });
    const { data } = await MarcosxAiAPI.getCredentials();
    credentials.value = data.credentials;
    await loadModels(provider, true);
    useAlert(t('MARCOX_AI.SAVED'));
  } catch (error) {
    notifyError(error);
  } finally {
    busyProvider.value = '';
  }
};
const testConnection = async provider => {
  busyProvider.value = provider;
  try {
    await MarcosxAiAPI.testCredential(provider);
    useAlert(t('MARCOX_AI.PROVIDERS.TEST_OK'));
  } catch (error) {
    notifyError(error);
  } finally {
    busyProvider.value = '';
  }
};
const eventLabel = event =>
  ({
    response_generated: 'GENERATED',
    response_sent: 'SENT',
    handoff: 'HANDOFF',
    response_failed: 'FAILED',
  })[event] || 'EVENT';
</script>

<template>
  <div class="flex h-full min-w-0 flex-1 flex-col bg-n-solid-2">
    <header class="border-b border-n-weak bg-n-solid-1 px-6 pt-6 lg:px-10">
      <div class="flex items-start justify-between gap-4">
        <div class="flex items-center gap-4">
          <span
            class="flex size-12 items-center justify-center rounded-2xl bg-n-blue-3 text-n-blue-11"
            ><span class="i-lucide-sparkles size-6"
          /></span>
          <div>
            <h1 class="text-2xl font-semibold tracking-tight text-n-slate-12">
              {{ t('MARCOX_AI.TITLE') }}
            </h1>
            <p class="mt-1 text-sm text-n-slate-11">
              {{ t('MARCOX_AI.SUBTITLE') }}
            </p>
          </div>
        </div>
        <Button
          v-if="canEdit && activeTab === 'overview' && !editing"
          :label="t('MARCOX_AI.NEW_AGENT')"
          icon="i-lucide-plus"
          :disabled="loading"
          @click="newAgent"
        />
      </div>
      <nav
        class="mt-6 flex gap-6 overflow-x-auto"
        :aria-label="t('MARCOX_AI.TITLE')"
      >
        <button
          v-for="item in tabs.filter(
            item => canEdit || !['credentials', 'activity'].includes(item.id)
          )"
          :key="item.id"
          class="flex shrink-0 items-center gap-2 border-b-2 px-1 pb-3 text-sm font-medium"
          :class="
            activeTab === item.id
              ? 'border-n-blue-9 text-n-blue-11'
              : 'border-transparent text-n-slate-11 hover:text-n-slate-12'
          "
          :aria-current="activeTab === item.id ? 'page' : undefined"
          @click="navigate(item.id)"
        >
          <span class="size-4" :class="item.icon" />{{
            t(`MARCOX_AI.TABS.${item.key}`)
          }}
        </button>
      </nav>
    </header>
    <div v-if="loading" class="flex flex-1 items-center justify-center">
      <Spinner />
    </div>
    <main v-else class="min-h-0 flex-1 overflow-y-auto p-6 lg:p-10">
      <p v-if="!canEdit" class="mb-4 text-sm text-n-slate-11">
        {{ t('MARCOX_AI.READ_ONLY') }}
      </p>
      <template v-if="activeTab === 'overview'">
        <AgentEditor
          v-if="editing"
          class="mx-auto h-full min-h-[32rem] max-w-4xl"
          :agent="editing"
          :agents="agents"
          :inboxes="inboxes"
          :credentials="credentials"
          :catalogs="catalogs"
          :default-prompt="preferences.default_prompt"
          :can-edit="canEdit"
          :saving="saving"
          @save="saveAgent"
          @cancel="editing = null"
          @delete="deleteAgent"
          @test="testAgent"
        />
        <div
          v-else-if="!agents.length"
          class="mx-auto mt-8 max-w-3xl rounded-3xl border border-n-weak bg-n-solid-1 px-8 py-14 text-center"
        >
          <span
            class="mx-auto flex size-20 items-center justify-center rounded-3xl bg-n-blue-3 text-n-blue-11"
            ><span class="i-lucide-bot size-10"
          /></span>
          <h2 class="mt-7 text-2xl font-semibold text-n-slate-12">
            {{ t('MARCOX_AI.EMPTY_TITLE') }}
          </h2>
          <p class="mx-auto mt-3 max-w-lg text-base text-n-slate-11">
            {{ t('MARCOX_AI.EMPTY_BODY') }}
          </p>
          <Button
            v-if="canEdit"
            class="mt-7"
            icon="i-lucide-plus"
            :label="t('MARCOX_AI.EMPTY_CTA')"
            @click="newAgent"
          />
          <div
            class="mt-12 grid gap-6 border-t border-n-weak pt-8 sm:grid-cols-3"
          >
            <div
              v-for="(key, index) in [
                'EMPTY_CONTEXT',
                'EMPTY_MEDIA',
                'EMPTY_CONTROL',
              ]"
              :key="key"
              class="space-y-3 text-sm text-n-slate-11"
            >
              <span
                class="mx-auto block size-5 text-n-slate-12"
                :class="
                  [
                    'i-lucide-brain',
                    'i-lucide-audio-lines',
                    'i-lucide-toggle-right',
                  ][index]
                "
              />
              <p>{{ t(`MARCOX_AI.${key}`) }}</p>
            </div>
          </div>
        </div>
        <div v-else class="mx-auto max-w-6xl space-y-6">
          <label class="relative block max-w-sm"
            ><span
              class="i-lucide-search absolute left-3 top-3 size-4 text-n-slate-11" /><input
              v-model="search"
              :aria-label="t('MARCOX_AI.SEARCH_AGENTS')"
              :placeholder="t('MARCOX_AI.SEARCH_AGENTS')"
              class="!mb-0 h-10 w-full rounded-lg border border-n-weak bg-n-solid-1 pl-10 pr-3 text-sm"
          /></label>
          <div class="grid gap-5 md:grid-cols-2 xl:grid-cols-3">
            <button
              v-for="agent in visibleAgents"
              :key="agent.id"
              class="flex min-h-60 flex-col rounded-2xl border border-n-weak bg-n-solid-1 p-6 text-left transition-colors hover:border-n-blue-7"
              @click="editing = agent"
            >
              <div class="flex w-full items-center justify-between">
                <span
                  class="flex size-11 items-center justify-center rounded-xl bg-n-blue-3 text-n-blue-11"
                  ><span class="i-lucide-bot size-5" /></span
                ><span
                  class="rounded-full px-2.5 py-1 text-xs font-medium"
                  :class="
                    agent.config.auto_response_enabled
                      ? 'bg-n-teal-3 text-n-teal-11'
                      : 'bg-n-alpha-2 text-n-slate-11'
                  "
                  >{{
                    t(
                      agent.config.auto_response_enabled
                        ? 'MARCOX_AI.ACTIVE'
                        : 'MARCOX_AI.DRAFT'
                    )
                  }}</span
                >
              </div>
              <h2 class="mt-5 text-lg font-semibold text-n-slate-12">
                {{ agent.name }}
              </h2>
              <p class="mt-2 line-clamp-2 text-sm text-n-slate-11">
                {{ agent.description || agent.instructions }}
              </p>
              <div
                class="mt-auto flex w-full items-center justify-between gap-3 border-t border-n-weak pt-4 text-xs text-n-slate-11"
              >
                <span class="truncate">{{ agent.config.model }}</span
                ><span>{{
                  t(
                    agent.inboxes_count
                      ? 'MARCOX_AI.INBOX_COUNT'
                      : 'MARCOX_AI.NO_INBOX',
                    { count: agent.inboxes_count }
                  )
                }}</span>
              </div>
            </button>
          </div>
        </div>
      </template>
      <ProvidersPanel
        v-else-if="activeTab === 'credentials' && canEdit"
        :providers="preferences.providers"
        :credentials="credentials"
        :catalogs="catalogs"
        :can-edit="canEdit"
        :busy="busyProvider"
        @save="saveConnection"
        @test="testConnection"
        @refresh="provider => loadModels(provider, true)"
      />
      <AiPlayground
        v-else-if="activeTab === 'playground'"
        :agents="agents"
        :agent-id="testAgentId"
      />
      <section
        v-else-if="activeTab === 'activity' && canEdit"
        class="mx-auto max-w-6xl"
      >
        <div class="mb-6 flex items-center justify-between">
          <div>
            <h2 class="text-xl font-semibold text-n-slate-12">
              {{ t('MARCOX_AI.ACTIVITY.TITLE') }}
            </h2>
            <p class="mt-2 text-sm text-n-slate-11">
              {{ t('MARCOX_AI.ACTIVITY.BODY') }}
            </p>
          </div>
          <Button
            icon="i-lucide-refresh-cw"
            variant="outline"
            color="slate"
            :label="t('MARCOX_AI.REFRESH')"
            @click="refresh"
          />
        </div>
        <div
          class="overflow-x-auto rounded-2xl border border-n-weak bg-n-solid-1"
        >
          <p
            v-if="!logs.length"
            class="p-12 text-center text-sm text-n-slate-11"
          >
            {{ t('MARCOX_AI.ACTIVITY.EMPTY') }}
          </p>
          <table v-else class="w-full text-left text-sm">
            <thead class="border-b border-n-weak text-n-slate-11">
              <tr>
                <th
                  v-for="key in ['EVENT', 'AGENT', 'CONVERSATION', 'WHEN']"
                  :key="key"
                  class="p-4 font-medium"
                >
                  {{ t(`MARCOX_AI.ACTIVITY.${key}`) }}
                </th>
              </tr>
            </thead>
            <tbody>
              <tr
                v-for="log in logs"
                :key="log.id"
                class="border-b border-n-weak last:border-0"
              >
                <td class="p-4">
                  <span
                    :class="
                      log.status === 'error'
                        ? 'text-n-ruby-11'
                        : 'text-n-slate-12'
                    "
                    >{{
                      t(`MARCOX_AI.ACTIVITY.${eventLabel(log.event)}`)
                    }}</span
                  >
                  <p
                    v-if="log.error"
                    class="mt-1 max-w-sm break-words text-xs text-n-ruby-11"
                  >
                    {{ log.error }}
                  </p>
                </td>
                <td class="p-4 text-n-slate-12">{{ log.assistant_name }}</td>
                <td class="p-4">
                  <RouterLink
                    v-if="log.conversation_id"
                    :to="{
                      name: 'inbox_conversation',
                      params: {
                        accountId: route.params.accountId,
                        conversationId: log.conversation_id,
                      },
                    }"
                    class="text-n-blue-11"
                  >
                    {{ `#${log.conversation_id}` }}
                  </RouterLink>
                </td>
                <td class="p-4 text-n-slate-11">
                  {{ new Date(log.created_at).toLocaleString() }}
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </section>
    </main>
  </div>
</template>
