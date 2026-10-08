<script setup>
import { computed, onMounted, ref } from 'vue';
import { useRoute } from 'vue-router';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import MarcosxAiAPI from 'dashboard/api/marcosxAi';
import AgentEditor from '../components/AgentEditor.vue';

const store = useStore();
const route = useRoute();
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
const initialSection = computed(
  () =>
    ({ activity: canEdit.value ? 'activity' : 'identity', playground: 'test' })[
      route.params.navigationPath
    ] || 'identity'
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
const connectionReady = agent =>
  credentials.value.some(
    item =>
      item.provider === agent.config.provider && item.enabled && item.configured
  );
const toggleAgent = async agent => {
  togglingId.value = agent.id;
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
  } catch (error) {
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
</script>

<template>
  <div class="flex h-full min-h-0 min-w-0 flex-1 flex-col bg-n-solid-1">
    <h1 class="sr-only">{{ t('MARCOX_AI.TITLE') }}</h1>
    <div v-if="loading" class="flex flex-1 items-center justify-center">
      <Spinner />
    </div>
    <main v-else class="flex min-h-0 min-w-0 flex-1 flex-col md:flex-row">
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
          <div
            v-for="agent in visibleAgents"
            :key="agent.id"
            class="flex min-w-48 shrink-0 items-start gap-2 rounded-lg p-3 transition-colors md:min-w-0"
            :class="
              editing?.id === agent.id ? 'bg-n-alpha-2' : 'hover:bg-n-alpha-1'
            "
          >
            <button
              type="button"
              class="flex min-w-0 flex-1 items-start gap-3 text-start"
              @click="selectAgent(agent)"
            >
              <span
                class="mt-0.5 flex size-8 shrink-0 items-center justify-center rounded-lg bg-n-blue-3 text-n-blue-11"
                ><span class="i-lucide-bot size-4"
              /></span>
              <span class="min-w-0 flex-1">
                <span
                  class="block truncate text-sm font-semibold text-n-slate-12"
                >
                  {{ agent.name }}
                </span>
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
            <button
              v-if="canEdit"
              type="button"
              role="switch"
              :aria-checked="agent.config.auto_response_enabled"
              :aria-label="t('MARCOX_AI.COVERAGE.TOGGLE', { name: agent.name })"
              :title="t('MARCOX_AI.COVERAGE.TOGGLE_HINT')"
              :disabled="
                saving ||
                togglingId !== null ||
                (!agent.config.auto_response_enabled && !connectionReady(agent))
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
