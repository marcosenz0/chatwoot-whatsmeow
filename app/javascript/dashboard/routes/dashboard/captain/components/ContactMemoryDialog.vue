<script setup>
import { computed, nextTick, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import MarcosxAiAPI from 'dashboard/api/marcosxAi';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';

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
    :title="t('MARCOX_AI.WORKSPACE.MEMORIES')"
    :show-confirm-button="false"
    :cancel-button-label="t('MARCOX_AI.WORKSPACE.CLOSE')"
    @close="generation += 1"
  >
    <template #description>
      <div v-if="data" class="flex min-w-0 items-center gap-3">
        <Avatar
          :src="data.contact.avatar_url || ''"
          :name="data.contact.name || ''"
          :size="40"
        />
        <div class="min-w-0 flex-1">
          <p class="m-0 truncate text-sm font-semibold text-n-slate-12">
            {{ data.contact.name }}
          </p>
          <p class="mb-0 mt-1 text-xs leading-5 text-n-slate-11">
            {{ t('MARCOX_AI.WORKSPACE.MEMORY_HINT') }}
          </p>
        </div>
      </div>
    </template>
    <div
      class="max-h-[calc(100dvh-16rem)] min-h-0 min-w-0 space-y-5 overflow-y-auto pe-2"
    >
      <div v-if="busy && !data" class="flex justify-center py-10">
        <Spinner />
      </div>
      <p v-if="error" role="alert" class="text-sm text-n-ruby-11">
        {{ error }}
      </p>
      <div v-if="data" class="space-y-5">
        <div
          v-if="data.contact.forgotten_at"
          class="flex flex-wrap items-center justify-between gap-3"
        >
          <p class="m-0 text-xs text-n-slate-11">
            {{
              t('MARCOX_AI.WORKSPACE.RESET_AT', {
                date: new Date(data.contact.forgotten_at).toLocaleString(),
              })
            }}
          </p>
        </div>
        <label
          v-if="data.conversations.length"
          class="block text-sm text-n-slate-12"
        >
          {{ t('MARCOX_AI.WORKSPACE.CONVERSATION') }}
          <select
            v-model.number="conversationId"
            :aria-label="t('MARCOX_AI.WORKSPACE.CONVERSATION')"
            :disabled="busy"
            class="reset-base mt-2 h-10 w-full min-w-0 rounded-lg border border-n-weak bg-n-solid-2 px-3 text-sm"
            @change="fetchMemory()"
          >
            <option
              v-for="item in data.conversations"
              :key="item.id"
              :value="item.id"
            >
              {{ `#${item.id} · ${item.inbox}` }}
            </option>
          </select>
        </label>
        <div class="grid items-start gap-4 md:grid-cols-2">
          <div
            v-if="selected?.editable"
            class="min-w-0 space-y-3 rounded-xl border border-n-weak bg-n-solid-2 p-4"
          >
            <label class="block text-sm font-medium text-n-slate-12"
              >{{ t('MARCOX_AI.WORKSPACE.SUMMARY') }}
              <textarea
                v-model="summary"
                rows="6"
                maxlength="30000"
                :disabled="busy"
                class="reset-base mt-2 min-h-36 w-full rounded-lg border border-n-weak bg-n-background p-3"
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
          <div
            class="min-w-0 space-y-3"
            :class="{ 'md:col-span-2': !selected?.editable }"
          >
            <h4 class="m-0 text-sm font-semibold text-n-slate-12">
              {{ t('MARCOX_AI.WORKSPACE.CONTEXT_MESSAGES') }}
            </h4>
            <p v-if="!data.messages.length" class="text-sm text-n-slate-11">
              {{ t('MARCOX_AI.WORKSPACE.NO_MEMORY') }}
            </p>
            <div
              v-for="entry in data.messages"
              :key="entry.id"
              class="flex min-w-0 flex-col items-start gap-2 rounded-xl border border-n-weak bg-n-solid-2 p-3"
              :class="{ 'opacity-60': entry.excluded }"
            >
              <div class="min-w-0 w-full">
                <p class="m-0 text-xs text-n-slate-11">
                  {{
                    entry.incoming
                      ? data.contact.name
                      : t('MARCOX_AI.WORKSPACE.REPLY')
                  }}
                  · {{ new Date(entry.created_at).toLocaleString() }}
                </p>
                <p
                  class="mb-0 mt-2 whitespace-pre-wrap break-words [overflow-wrap:anywhere] text-sm text-n-slate-12"
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
    </div>
    <template #footer>
      <div
        class="flex flex-wrap items-center justify-between gap-3 border-t border-n-weak pt-4"
      >
        <Button
          type="button"
          color="ruby"
          variant="outline"
          icon="i-lucide-eraser"
          :disabled="busy || !data"
          :label="t('MARCOX_AI.WORKSPACE.FORGET')"
          @click="forgetDialog.open()"
        />
        <Button
          type="button"
          variant="faded"
          color="slate"
          :label="t('MARCOX_AI.WORKSPACE.CLOSE')"
          @click="dialog.close()"
        />
      </div>
    </template>
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
