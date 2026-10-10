<script setup>
import { computed, nextTick, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import MarcosxAiAPI from 'dashboard/api/marcosxAi';
import AiSelect from './AiSelect.vue';

const { t } = useI18n();
const dialog = ref(null);
const forgetDialog = ref(null);
const contactId = ref(null);
const conversationId = ref(null);
const data = ref(null);
const summary = ref('');
const busy = ref(false);
const error = ref('');
const more = ref(false);
let generation = 0;
const selected = computed(() =>
  data.value?.conversations.find(item => item.id === conversationId.value)
);
const fetchMemory = async (older = false) => {
  const currentGeneration = generation;
  busy.value = true;
  error.value = '';
  try {
    const { data: result } = await MarcosxAiAPI.getContactMemory(
      contactId.value,
      {
        conversation_id: conversationId.value,
        ...(older ? { before_id: data.value.messages.at(-1)?.id } : {}),
      }
    );
    if (currentGeneration !== generation) return;
    more.value = result.messages.length > 50;
    const entries = result.messages.slice(0, 50);
    result.messages = older ? [...data.value.messages, ...entries] : entries;
    data.value = result;
    conversationId.value = result.conversation_id;
    if (!older) summary.value = selected.value?.summary || '';
  } catch (failure) {
    if (currentGeneration === generation)
      error.value =
        failure.response?.data?.error || t('MARCOX_AI.CONVERSATION.ERROR');
  } finally {
    if (currentGeneration === generation) busy.value = false;
  }
};
const open = async (id, conversation = null) => {
  generation += 1;
  contactId.value = id;
  conversationId.value = conversation;
  data.value = null;
  summary.value = '';
  await nextTick();
  dialog.value.open();
  await fetchMemory();
};
const mutate = async action => {
  busy.value = true;
  error.value = '';
  try {
    await action();
    await fetchMemory();
  } catch (failure) {
    error.value =
      failure.response?.data?.error || t('MARCOX_AI.CONVERSATION.ERROR');
  } finally {
    busy.value = false;
  }
};
const save = () =>
  mutate(() =>
    MarcosxAiAPI.updateContactMemory(contactId.value, {
      conversation_id: conversationId.value,
      summary: summary.value,
    })
  );
const exclude = message =>
  mutate(() =>
    MarcosxAiAPI.updateContactMemory(contactId.value, {
      message_id: message.id,
      excluded: !message.excluded,
    })
  );
const forget = async () => {
  await mutate(() => MarcosxAiAPI.forgetContactMemory(contactId.value));
  if (!error.value) forgetDialog.value.close();
};
defineExpose({ open });
</script>

<template>
  <Dialog
    ref="dialog"
    width="3xl"
    :title="
      t('MARCOX_AI.WORKSPACE.CONTACT_MEMORY', {
        name: data?.contact.name || '',
      })
    "
    :show-confirm-button="false"
    :cancel-button-label="t('MARCOX_AI.WORKSPACE.CLOSE')"
    @close="generation += 1"
  >
    <div class="max-h-[65vh] space-y-5 overflow-y-auto">
      <p v-if="error" role="alert" class="text-sm text-n-ruby-11">
        {{ error }}
      </p>
      <p class="text-sm text-n-slate-11">
        {{ t('MARCOX_AI.WORKSPACE.MEMORY_HINT') }}
      </p>
      <div v-if="data" class="space-y-5">
        <div class="flex flex-wrap items-center justify-between gap-3">
          <p
            v-if="data.contact.forgotten_at"
            class="m-0 text-xs text-n-slate-11"
          >
            {{
              t('MARCOX_AI.WORKSPACE.RESET_AT', {
                date: new Date(data.contact.forgotten_at).toLocaleString(),
              })
            }}
          </p>
          <Button
            type="button"
            color="ruby"
            variant="outline"
            icon="i-lucide-eraser"
            :disabled="busy"
            :label="t('MARCOX_AI.WORKSPACE.FORGET')"
            @click="forgetDialog.open()"
          />
        </div>
        <label
          v-if="data.conversations.length"
          class="block text-sm text-n-slate-12"
        >
          {{ t('MARCOX_AI.WORKSPACE.CONVERSATION') }}
          <AiSelect
            v-model="conversationId"
            :options="
              data.conversations.map(item => ({
                value: item.id,
                label: `#${item.id} · ${item.inbox}`,
              }))
            "
            :label="t('MARCOX_AI.WORKSPACE.CONVERSATION')"
            class="mt-2"
            :disabled="busy"
            @update:model-value="fetchMemory()"
          />
        </label>
        <div
          v-if="selected?.editable"
          class="space-y-3 rounded-xl border border-n-weak p-4"
        >
          <label class="block text-sm font-medium text-n-slate-12"
            >{{ t('MARCOX_AI.WORKSPACE.SUMMARY') }}
            <textarea
              v-model="summary"
              rows="6"
              maxlength="30000"
              :disabled="busy"
              class="reset-base mt-2 w-full rounded-lg border border-n-weak bg-n-background p-3"
            />
          </label>
          <p class="text-xs text-n-slate-11">
            {{ t('MARCOX_AI.WORKSPACE.SUMMARY_HINT') }}
          </p>
          <p v-if="selected.updated_at" class="text-xs text-n-slate-11">
            {{ new Date(selected.updated_at).toLocaleString() }} ·
            {{ selected.summarized_count || 0 }}
          </p>
          <Button
            type="button"
            :disabled="busy || summary === (selected.summary || '')"
            :label="t('MARCOX_AI.SAVE')"
            @click="save"
          />
        </div>
        <div class="space-y-3">
          <h4 class="m-0 text-sm font-semibold text-n-slate-12">
            {{ t('MARCOX_AI.WORKSPACE.CONTEXT_MESSAGES') }}
          </h4>
          <p v-if="!data.messages.length" class="text-sm text-n-slate-11">
            {{ t('MARCOX_AI.WORKSPACE.NO_MEMORY') }}
          </p>
          <div
            v-for="entry in data.messages"
            :key="entry.id"
            class="flex items-start gap-3 rounded-xl border border-n-weak p-4"
            :class="{ 'opacity-60': entry.excluded }"
          >
            <div class="min-w-0 flex-1">
              <p class="m-0 text-xs text-n-slate-11">
                {{
                  entry.incoming
                    ? data.contact.name
                    : t('MARCOX_AI.WORKSPACE.REPLY')
                }}
                · {{ new Date(entry.created_at).toLocaleString() }}
              </p>
              <p
                class="mb-0 mt-2 whitespace-pre-wrap break-words text-sm text-n-slate-12"
              >
                {{ entry.content || t('MARCOX_AI.PLAYGROUND.ATTACH') }}
              </p>
              <p
                v-if="entry.excluded"
                class="mb-0 mt-2 text-xs text-n-amber-11"
              >
                {{ t('MARCOX_AI.WORKSPACE.EXCLUDED') }}
              </p>
            </div>
            <Button
              type="button"
              size="sm"
              variant="ghost"
              :color="entry.excluded ? 'slate' : 'ruby'"
              :disabled="busy"
              :label="
                t(
                  entry.excluded
                    ? 'MARCOX_AI.WORKSPACE.RESTORE'
                    : 'MARCOX_AI.WORKSPACE.EXCLUDE'
                )
              "
              @click="exclude(entry)"
            />
          </div>
          <Button
            v-if="more"
            type="button"
            variant="outline"
            :disabled="busy"
            :label="t('MARCOX_AI.WORKSPACE.OLDER')"
            @click="fetchMemory(true)"
          />
        </div>
      </div>
    </div>
  </Dialog>
  <Dialog
    ref="forgetDialog"
    type="alert"
    :title="t('MARCOX_AI.WORKSPACE.FORGET')"
    :description="t('MARCOX_AI.WORKSPACE.FORGET_CONFIRM')"
    :confirm-button-label="t('MARCOX_AI.WORKSPACE.FORGET')"
    :is-loading="busy"
    @confirm="forget"
  />
</template>
