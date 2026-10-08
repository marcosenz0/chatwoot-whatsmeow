<script setup>
import { computed, onMounted, ref } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import MarcosxAiAPI from 'dashboard/api/marcosxAi';
import AgentEditor from '../components/AgentEditor.vue';
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
const dirty = ref(false);
const discardDialog = ref(null);
const deleteDialog = ref(null);
const deletingId = ref(null);
let pendingNavigation = null;
const reviewNavigation = action => {
  if (dirty.value) {
    pendingNavigation = action;
    discardDialog.value.open();
  } else action();
};
const discardChanges = () => {
  dirty.value = false;
  pendingNavigation?.();
  pendingNavigation = null;
  discardDialog.value.close();
};
const selectAgent = agent =>
  reviewNavigation(() => {
    editing.value = agent;
    dirty.value = false;
  });
const cancelAgent = () => {
  const saved =
    agents.value.find(agent => agent.id === editing.value?.id) ||
    agents.value[0];
  editing.value = saved ? { ...saved } : null;
  dirty.value = false;
};
const inboxes = computed(() => store.getters['inboxes/getInboxes'] || []);
const tabs = [
  { id: 'overview', key: 'AGENTS', icon: 'i-lucide-bot' },
  { id: 'activity', key: 'ACTIVITY', icon: 'i-lucide-activity' },
];
const activeTab = computed(() =>
  route.params.navigationPath === 'playground' ||
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
const navigate = id =>
  reviewNavigation(() => {
    router.replace({
      name: 'captain_assistants_index',
      params: { accountId: route.params.accountId, navigationPath: id },
    });
    dirty.value = false;
  });
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
    editing.value =
      agents.value.find(agent => agent.id === editing.value?.id) ||
      agents.value[0] ||
      null;
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
const newAgent = () =>
  reviewNavigation(() => {
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
    dirty.value = false;
  });
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
    editing.value = data.assistant;
    dirty.value = false;
    useAlert(t('MARCOX_AI.SAVED'));
  } catch (error) {
    notifyError(error);
  } finally {
    saving.value = false;
  }
};
const deleteAgent = id => {
  deletingId.value = id;
  deleteDialog.value.open();
};
const confirmDelete = async () => {
  try {
    await MarcosxAiAPI.deleteAssistant(deletingId.value);
    agents.value = agents.value.filter(item => item.id !== deletingId.value);
    editing.value = agents.value[0] || null;
    dirty.value = false;
    deleteDialog.value.close();
  } catch (error) {
    notifyError(error);
  }
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
    analysis_ready: 'ANALYSIS',
  })[event] || 'EVENT';
</script>

<template>
  <div class="flex h-full min-h-0 min-w-0 flex-1 flex-col bg-n-solid-2">
    <header
      class="flex shrink-0 items-center justify-between gap-4 border-b border-n-weak bg-n-solid-1 px-5 py-3"
    >
      <div class="flex min-w-0 items-center gap-3">
        <span
          class="flex size-9 shrink-0 items-center justify-center rounded-xl bg-n-blue-3 text-n-blue-11"
          ><span class="i-lucide-bot size-5"
        /></span>
        <div class="min-w-0">
          <h1 class="m-0 text-lg font-semibold text-n-slate-12">
            {{ t('MARCOX_AI.TITLE') }}
          </h1>
          <p class="m-0 hidden truncate text-xs text-n-slate-11 sm:block">
            {{ t('MARCOX_AI.SUBTITLE') }}
          </p>
        </div>
      </div>
      <nav class="flex items-center gap-1" :aria-label="t('MARCOX_AI.TITLE')">
        <Button
          v-for="item in tabs.filter(item => canEdit || item.id !== 'activity')"
          :key="item.id"
          variant="ghost"
          color="slate"
          size="sm"
          :icon="item.icon"
          :label="t(`MARCOX_AI.TABS.${item.key}`)"
          :class="{ 'bg-n-alpha-2': activeTab === item.id }"
          @click="navigate(item.id)"
        />
      </nav>
    </header>
    <div v-if="loading" class="flex flex-1 items-center justify-center">
      <Spinner />
    </div>
    <main
      v-else-if="activeTab === 'overview'"
      class="flex min-h-0 min-w-0 flex-1 flex-col md:flex-row"
    >
      <aside
        class="flex shrink-0 flex-col border-b border-n-weak bg-n-solid-1 md:w-64 md:border-b-0 md:border-e"
      >
        <div class="space-y-3 border-b border-n-weak p-4">
          <div class="flex items-center justify-between gap-3">
            <h2 class="m-0 text-sm font-semibold text-n-slate-12">
              {{ t('MARCOX_AI.TABS.AGENTS') }}
              <span class="ms-1 text-xs text-n-slate-11">{{
                agents.length
              }}</span>
            </h2>
            <Button
              v-if="canEdit"
              icon="i-lucide-plus"
              variant="ghost"
              color="slate"
              size="sm"
              :aria-label="t('MARCOX_AI.NEW_AGENT')"
              @click="newAgent"
            />
          </div>
          <label class="relative block">
            <span
              class="i-lucide-search absolute start-3 top-2.5 size-4 text-n-slate-11"
            />
            <input
              v-model="search"
              :aria-label="t('MARCOX_AI.SEARCH_AGENTS')"
              :placeholder="t('MARCOX_AI.SEARCH_AGENTS')"
              class="reset-base !mb-0 h-9 w-full rounded-lg border border-n-weak bg-n-solid-2 !ps-9 !pe-3 text-sm"
            />
          </label>
        </div>
        <div
          class="flex max-h-52 min-h-0 gap-1 overflow-auto p-2 md:max-h-none md:flex-1 md:flex-col"
        >
          <button
            v-for="agent in visibleAgents"
            :key="agent.id"
            type="button"
            class="flex min-w-48 shrink-0 items-start gap-3 rounded-lg p-3 text-start transition-colors md:min-w-0"
            :class="
              editing?.id === agent.id ? 'bg-n-alpha-2' : 'hover:bg-n-alpha-1'
            "
            @click="selectAgent(agent)"
          >
            <span
              class="mt-0.5 flex size-8 shrink-0 items-center justify-center rounded-lg bg-n-blue-3 text-n-blue-11"
              ><span class="i-lucide-bot size-4"
            /></span>
            <span class="min-w-0 flex-1">
              <span class="flex items-center gap-2"
                ><span class="truncate text-sm font-semibold text-n-slate-12">{{
                  agent.name
                }}</span>
                <span
                  class="size-1.5 shrink-0 rounded-full"
                  :class="
                    agent.config.auto_response_enabled
                      ? 'bg-n-teal-9'
                      : 'bg-n-slate-8'
                  "
                  :title="
                    t(
                      agent.config.auto_response_enabled
                        ? 'MARCOX_AI.ACTIVE'
                        : 'MARCOX_AI.DRAFT'
                    )
                  "
              /></span>
              <span class="mt-1 block truncate text-xs text-n-slate-11">{{
                agent.config.model
              }}</span>
              <span class="mt-1.5 block text-xs text-n-slate-10">{{
                t(
                  agent.inboxes_count
                    ? 'MARCOX_AI.INBOX_COUNT'
                    : 'MARCOX_AI.NO_INBOX',
                  { count: agent.inboxes_count }
                )
              }}</span>
            </span>
          </button>
          <Button
            v-if="canEdit"
            class="mt-2 !justify-start"
            variant="ghost"
            color="slate"
            icon="i-lucide-plus"
            :label="t('MARCOX_AI.NEW_AGENT')"
            @click="newAgent"
          />
        </div>
      </aside>
      <AgentEditor
        v-if="editing"
        :agent="editing"
        :agents="agents"
        :inboxes="inboxes"
        :credentials="credentials"
        :catalogs="catalogs"
        :providers="preferences.providers"
        :busy-provider="busyProvider"
        :default-prompt="preferences.default_prompt"
        :can-edit="canEdit"
        :saving="saving"
        @save="saveAgent"
        @cancel="cancelAgent"
        @delete="deleteAgent"
        @change="
          form => (dirty = JSON.stringify(form) !== JSON.stringify(editing))
        "
        @save-connection="saveConnection"
        @test-connection="testConnection"
        @refresh-models="provider => loadModels(provider, true)"
      />
      <div
        v-else
        class="flex flex-1 flex-col items-center justify-center p-8 text-center"
      >
        <span
          class="flex size-16 items-center justify-center rounded-2xl bg-n-blue-3 text-n-blue-11"
          ><span class="i-lucide-bot size-8"
        /></span>
        <h2 class="mt-6 text-xl font-semibold text-n-slate-12">
          {{ t('MARCOX_AI.EMPTY_TITLE') }}
        </h2>
        <p class="mt-2 max-w-lg text-sm leading-6 text-n-slate-11">
          {{ t('MARCOX_AI.EMPTY_BODY') }}
        </p>
        <Button
          v-if="canEdit"
          class="mt-5"
          icon="i-lucide-plus"
          :label="t('MARCOX_AI.EMPTY_CTA')"
          @click="newAgent"
        />
      </div>
    </main>
    <main v-else-if="activeTab === 'playground'" class="min-h-0 flex-1 p-6">
      <AiPlayground :agents="agents" />
    </main>
    <main
      v-else-if="activeTab === 'activity' && canEdit"
      class="min-h-0 flex-1 overflow-y-auto p-6"
    >
      <div class="mb-6 flex items-center justify-between gap-4">
        <div>
          <h2 class="text-lg font-semibold text-n-slate-12">
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
      <div class="overflow-x-auto rounded-xl border border-n-weak bg-n-solid-1">
        <p v-if="!logs.length" class="p-12 text-center text-sm text-n-slate-11">
          {{ t('MARCOX_AI.ACTIVITY.EMPTY') }}
        </p>
        <table v-else class="w-full text-start text-sm">
          <thead class="border-b border-n-weak text-n-slate-11">
            <tr>
              <th
                v-for="key in ['EVENT', 'AGENT', 'CONVERSATION', 'WHEN']"
                :key="key"
                class="p-4 text-start font-medium"
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
                  >{{ t(`MARCOX_AI.ACTIVITY.${eventLabel(log.event)}`) }}</span
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
    </main>
    <Dialog
      ref="discardDialog"
      :title="t('MARCOX_AI.EDITOR.UNSAVED')"
      :description="t('MARCOX_AI.EDITOR.DISCARD_HINT')"
      :confirm-button-label="t('MARCOX_AI.EDITOR.DISCARD')"
      @confirm="discardChanges"
    />
    <Dialog
      ref="deleteDialog"
      :title="t('MARCOX_AI.DELETE')"
      :description="t('MARCOX_AI.EDITOR.CONFIRM_DELETE')"
      @confirm="confirmDelete"
    />
  </div>
</template>
