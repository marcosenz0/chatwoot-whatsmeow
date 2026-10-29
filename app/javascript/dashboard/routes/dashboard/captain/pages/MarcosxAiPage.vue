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
import { useMarcosxAiBatches } from 'dashboard/composables/useMarcosxAiBatches';
import AgentEditor from '../components/AgentEditor.vue';
import PendingReplies from '../components/PendingReplies.vue';

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
const loading = ref(true);
const saving = ref(false);
const togglingId = ref(null);
const busyProvider = ref('');
const editing = ref(null);
const search = ref('');
const dirty = ref(false);
const actionError = ref('');
const { beginOperation, finishOperation } = useMarcosxAiBatches();
const errorMessage = error =>
  error.response?.data?.error || t('MARCOX_AI.ERROR');
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
const selectAgent = (agent, section = undefined) =>
  reviewNavigation(() => {
    editing.value = agent;
    router.replace({
      query: { ...route.query, agent: agent.id, section },
    });
    dirty.value = false;
  });
const backToAgents = () =>
  reviewNavigation(() => {
    editing.value = null;
    dirty.value = false;
    router.replace({
      query: { ...route.query, agent: undefined, section: undefined },
    });
  });
const cancelAgent = () => {
  const saved =
    agents.value.find(agent => agent.id === editing.value?.id) ||
    agents.value[0];
  editing.value = saved ? { ...saved } : null;
  dirty.value = false;
};
const inboxes = computed(() => store.getters['inboxes/getInboxes'] || []);
const initialSection = computed(
  () =>
    ({ activity: canEdit.value ? 'activity' : 'identity', playground: 'test' })[
      route.params.navigationPath
    ] ||
    route.query.section ||
    'identity'
);
const visibleAgents = computed(() =>
  agents.value.filter(item =>
    `${item.name} ${item.description || ''}`
      .toLowerCase()
      .includes(search.value.toLowerCase())
  )
);
const assignedInboxCount = computed(
  () => new Set(agents.value.flatMap(agent => agent.inbox_ids)).size
);
const enabledAgentCount = computed(
  () => agents.value.filter(agent => agent.config.auto_response_enabled).length
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
      agents.value.find(agent => agent.id === Number(route.query.agent)) ||
      null;
    if (canEdit.value) {
      Promise.all(
        Object.keys(settings.data.providers).map(provider =>
          loadModels(provider)
        )
      );
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
      config: {
        ...preferences.value.agent_defaults,
        timezone: Intl.DateTimeFormat().resolvedOptions().timeZone,
      },
      response_guidelines: [],
      guardrails: [],
    };
    dirty.value = false;
  });
const saveAgent = async (form, connections = []) => {
  if (saving.value) return;
  saving.value = true;
  actionError.value = '';
  const operationId = `save-${form.id || 'new'}`;
  beginOperation(operationId, form.name, t('MARCOX_AI.OPERATIONS.SAVING'));
  try {
    await Promise.all(
      connections.map(connection =>
        MarcosxAiAPI.saveCredential(connection.id, {
          credential: {
            provider: connection.provider,
            api_key: connection.api_key,
            api_base: connection.api_base,
            model: connection.model,
            enabled: connection.enabled,
          },
        })
      )
    );
    if (connections.length) {
      const { data } = await MarcosxAiAPI.getCredentials();
      credentials.value = data.credentials;
      connections.forEach(connection => loadModels(connection.provider, true));
    }
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
    router.replace({ query: { ...route.query, agent: data.assistant.id } });
    dirty.value = false;
    useAlert(t('MARCOX_AI.SAVED'));
    finishOperation(operationId);
  } catch (error) {
    actionError.value = errorMessage(error);
    finishOperation(operationId, actionError.value);
    notifyError(error);
  } finally {
    saving.value = false;
  }
};
const connectionReady = agent =>
  credentials.value.some(
    item =>
      item.provider === agent.config.provider && item.enabled && item.configured
  );
const toggleManual = async agent => {
  if (togglingId.value !== null) return;
  togglingId.value = agent.id;
  const operationId = `manual-${agent.id}`;
  beginOperation(operationId, agent.name, t('MARCOX_AI.OPERATIONS.MANUAL'));
  try {
    const { data } = await MarcosxAiAPI.updateAssistant(agent.id, {
      assistant: {
        config: {
          manual_sessions_enabled:
            agent.config.manual_sessions_enabled === false,
        },
      },
    });
    agents.value = agents.value.map(item =>
      item.id === agent.id ? data.assistant : item
    );
    finishOperation(operationId);
  } catch (error) {
    finishOperation(operationId, errorMessage(error));
    notifyError(error);
  } finally {
    togglingId.value = null;
  }
};
const toggleAgent = async agent => {
  if (togglingId.value !== null) return;
  togglingId.value = agent.id;
  const operationId = `toggle-${agent.id}`;
  beginOperation(
    operationId,
    agent.name,
    t(
      agent.config.auto_response_enabled
        ? 'MARCOX_AI.OPERATIONS.DISABLING'
        : 'MARCOX_AI.OPERATIONS.ENABLING'
    )
  );
  try {
    const { data } = await MarcosxAiAPI.updateAssistant(agent.id, {
      assistant: {
        config: { auto_response_enabled: !agent.config.auto_response_enabled },
      },
    });
    agents.value = agents.value.map(item =>
      item.id === agent.id ? data.assistant : item
    );
    if (editing.value?.id === agent.id) {
      // Keep unsaved instructions and model choices while updating the saved switch.
      editing.value.config.auto_response_enabled =
        data.assistant.config.auto_response_enabled;
    }
    useAlert(
      t(
        data.assistant.config.auto_response_enabled
          ? 'MARCOX_AI.COVERAGE.ENABLED'
          : 'MARCOX_AI.COVERAGE.DISABLED'
      )
    );
    finishOperation(operationId);
  } catch (error) {
    finishOperation(operationId, errorMessage(error));
    notifyError(error);
  } finally {
    togglingId.value = null;
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
    editing.value = null;
    dirty.value = false;
    router.replace({
      query: { ...route.query, agent: undefined, section: undefined },
    });
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
</script>

<template>
  <div class="flex h-full min-h-0 min-w-0 flex-1 flex-col bg-n-solid-1">
    <h1 class="sr-only">{{ t('MARCOX_AI.TITLE') }}</h1>
    <div v-if="loading" class="flex flex-1 items-center justify-center">
      <Spinner />
    </div>
    <main v-else class="flex min-h-0 min-w-0 flex-1 flex-col md:flex-row">
      <aside
        v-if="!editing && agents.length"
        class="min-w-0 w-full overflow-y-auto p-4 sm:p-6"
      >
        <div class="mx-auto w-full max-w-6xl space-y-6">
          <header class="flex flex-wrap items-start justify-between gap-4">
            <div>
              <h2 class="m-0 text-xl font-semibold text-n-slate-12">
                {{ t('MARCOX_AI.TITLE') }}
              </h2>
              <p class="mb-0 mt-2 text-sm leading-6 text-n-slate-11">
                {{ t('MARCOX_AI.DESIGN.BODY') }}
              </p>
            </div>
            <Button
              v-if="canEdit"
              icon="i-lucide-plus"
              :label="t('MARCOX_AI.NEW_AGENT')"
              @click="newAgent"
            />
          </header>
          <div class="grid gap-3 sm:grid-cols-3">
            <div
              v-for="metric in [
                {
                  label: t('MARCOX_AI.TABS.AGENTS'),
                  value: agents.length,
                  icon: 'i-lucide-bot',
                },
                {
                  label: t('MARCOX_AI.DESIGN.OVERVIEW_INBOXES'),
                  value: assignedInboxCount,
                  icon: 'i-lucide-inbox',
                },
                {
                  label: t('MARCOX_AI.DESIGN.OVERVIEW_ENABLED'),
                  value: enabledAgentCount,
                  icon: 'i-lucide-messages-square',
                },
              ]"
              :key="metric.label"
              class="flex items-center gap-3 rounded-xl border border-n-weak bg-n-solid-2 p-4"
            >
              <div
                class="flex size-10 shrink-0 items-center justify-center rounded-lg bg-n-alpha-2 text-n-slate-11"
              >
                <span :class="metric.icon" class="size-5" />
              </div>
              <div class="min-w-0">
                <p class="m-0 text-xs text-n-slate-11">{{ metric.label }}</p>
                <p class="mb-0 mt-1 text-xl font-semibold text-n-slate-12">
                  {{ metric.value }}
                </p>
              </div>
            </div>
          </div>
          <div
            class="flex flex-wrap items-center justify-between gap-3 border-b border-n-weak pb-4"
          >
            <h3 class="m-0 text-base font-semibold text-n-slate-12">
              {{ t('MARCOX_AI.TABS.AGENTS') }}
              <span class="ms-1 text-sm font-normal text-n-slate-11">{{
                agents.length
              }}</span>
            </h3>
            <label class="relative block w-full sm:w-72">
              <span
                aria-hidden="true"
                class="i-lucide-search absolute start-3 top-2.5 size-4 text-n-slate-11"
              />
              <input
                v-model="search"
                :placeholder="t('MARCOX_AI.SEARCH_AGENTS')"
                :aria-label="t('MARCOX_AI.SEARCH_AGENTS')"
                class="reset-base !mb-0 h-9 w-full rounded-lg border border-n-weak bg-n-background !ps-9 !pe-3 text-sm"
              />
            </label>
          </div>
          <div class="grid items-start gap-4 md:grid-cols-2 2xl:grid-cols-3">
            <article
              v-for="agent in visibleAgents"
              :key="agent.id"
              class="min-w-0 rounded-xl border border-n-weak bg-n-solid-2"
            >
              <div class="flex items-start gap-3 p-5">
                <button
                  type="button"
                  class="flex min-w-0 flex-1 items-start gap-3 text-start"
                  @click="selectAgent(agent)"
                >
                  <div
                    aria-hidden="true"
                    class="flex size-10 shrink-0 items-center justify-center rounded-xl bg-n-blue-3 text-n-blue-11"
                  >
                    <span class="i-lucide-bot size-5" />
                  </div>
                  <span class="min-w-0 flex-1">
                    <span
                      class="block truncate text-sm font-semibold text-n-slate-12"
                      >{{ agent.name }}</span
                    >
                    <span class="mt-1 block truncate text-xs text-n-slate-11">{{
                      agent.config.model
                    }}</span>
                  </span>
                </button>
                <button
                  v-if="canEdit"
                  type="button"
                  role="switch"
                  :aria-checked="agent.config.auto_response_enabled"
                  :aria-label="
                    t('MARCOX_AI.COVERAGE.TOGGLE', { name: agent.name })
                  "
                  :title="t('MARCOX_AI.COVERAGE.TOGGLE_HINT')"
                  :disabled="
                    saving ||
                    togglingId !== null ||
                    (!agent.config.auto_response_enabled &&
                      !connectionReady(agent))
                  "
                  class="relative mt-0.5 inline-flex h-5 w-9 shrink-0 items-center rounded-full !p-0 transition-colors focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-9 disabled:opacity-40"
                  :class="
                    agent.config.auto_response_enabled
                      ? 'bg-n-blue-9'
                      : 'bg-n-slate-6'
                  "
                  @click="toggleAgent(agent)"
                >
                  <span
                    class="size-4 rounded-full bg-white shadow transition-transform"
                    :class="
                      agent.config.auto_response_enabled
                        ? 'translate-x-[18px]'
                        : 'translate-x-0.5'
                    "
                  />
                </button>
              </div>
              <div class="space-y-3 px-5 pb-5">
                <p
                  v-if="agent.description"
                  class="m-0 line-clamp-2 text-sm leading-6 text-n-slate-11"
                >
                  {{ agent.description }}
                </p>
                <p class="m-0 flex items-center gap-2 text-xs text-n-slate-11">
                  <span aria-hidden="true" class="i-lucide-inbox size-3.5" />{{
                    t(
                      agent.inboxes_count
                        ? 'MARCOX_AI.INBOX_COUNT'
                        : 'MARCOX_AI.NO_INBOX',
                      { count: agent.inboxes_count }
                    )
                  }}
                </p>
                <p
                  class="m-0 flex items-center gap-2 text-xs"
                  :class="
                    agent.config.auto_response_enabled
                      ? 'text-n-teal-11'
                      : 'text-n-slate-11'
                  "
                >
                  <span
                    class="size-1.5 rounded-full"
                    :class="
                      agent.config.auto_response_enabled
                        ? 'bg-n-teal-9'
                        : 'bg-n-slate-7'
                    "
                  />{{
                    t(
                      agent.config.auto_response_enabled
                        ? 'MARCOX_AI.DESIGN.GENERAL_ON'
                        : 'MARCOX_AI.DESIGN.GENERAL_OFF'
                    )
                  }}
                </p>
              </div>
              <div
                class="flex flex-wrap items-center gap-2 border-t border-n-weak px-4 py-3"
              >
                <Button
                  size="sm"
                  variant="ghost"
                  color="slate"
                  icon="i-lucide-settings-2"
                  :label="t('MARCOX_AI.DESIGN.CONFIGURE')"
                  @click="selectAgent(agent)"
                />
                <Button
                  size="sm"
                  variant="ghost"
                  color="slate"
                  icon="i-lucide-flask-conical"
                  :aria-label="t('MARCOX_AI.EDITOR.TEST')"
                  :title="t('MARCOX_AI.EDITOR.TEST')"
                  @click="selectAgent(agent, 'test')"
                />
                <Button
                  v-if="canEdit"
                  size="sm"
                  variant="ghost"
                  color="slate"
                  icon="i-lucide-brain"
                  :aria-label="t('MARCOX_AI.WORKSPACE.MEMORIES')"
                  @click="selectAgent(agent, 'memories')"
                />
              </div>
              <div
                v-if="canEdit"
                class="mt-3 flex flex-wrap items-center gap-2 border-t border-n-weak pt-3"
              >
                <PendingReplies :agent="agent" />
                <button
                  type="button"
                  role="switch"
                  :aria-checked="agent.config.manual_sessions_enabled !== false"
                  :aria-label="t('MARCOX_AI.PENDING.MANUAL')"
                  :disabled="togglingId === agent.id"
                  class="reset-base flex items-center gap-2 rounded-lg px-2 py-2 text-xs text-n-slate-11 hover:bg-n-alpha-1"
                  :title="t('MARCOX_AI.PENDING.MANUAL_HINT')"
                  @click="toggleManual(agent)"
                >
                  <span
                    aria-hidden="true"
                    class="i-lucide-mouse-pointer-2 size-4"
                  />
                  {{ t('MARCOX_AI.PENDING.MANUAL') }} ({{
                    agent.manual_sessions_count || 0
                  }})
                  <span
                    class="relative h-5 w-9 rounded-full"
                    :class="
                      agent.config.manual_sessions_enabled === false
                        ? 'bg-n-slate-5'
                        : 'bg-n-blue-9'
                    "
                  >
                    <span
                      class="absolute top-0.5 size-4 rounded-full bg-white"
                      :class="
                        agent.config.manual_sessions_enabled === false
                          ? 'start-0.5'
                          : 'end-0.5'
                      "
                    />
                  </span>
                </button>
              </div>
            </article>
          </div>
          <p
            v-if="!visibleAgents.length"
            class="rounded-xl border border-n-weak p-8 text-center text-sm text-n-slate-11"
          >
            {{ t('COMBOBOX.EMPTY_STATE') }}
          </p>
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
        :error="actionError"
        :default-prompt="preferences.default_prompt"
        :can-edit="canEdit"
        :saving="saving || togglingId !== null"
        :initial-section="initialSection"
        @save="saveAgent"
        @cancel="cancelAgent"
        @delete="deleteAgent"
        @change="
          form => (dirty = JSON.stringify(form) !== JSON.stringify(editing))
        "
        @save-connection="saveConnection"
        @test-connection="testConnection"
        @refresh-models="provider => loadModels(provider, true)"
        @back="backToAgents"
      />
      <div
        v-else-if="!agents.length"
        class="flex flex-1 flex-col items-center justify-center p-8 text-center"
      >
        <div
          aria-hidden="true"
          class="flex size-16 items-center justify-center rounded-2xl bg-n-blue-3 text-n-blue-11"
        >
          <span class="i-lucide-bot size-8" />
        </div>
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
