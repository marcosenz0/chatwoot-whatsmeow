<script setup>
import { computed, onBeforeUnmount, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import API from 'dashboard/api/marcosxAi';
import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import AudioPlayer from 'dashboard/components-next/audio/AudioPlayer.vue';

const props = defineProps({ agent: { type: Object, required: true } });
const { t } = useI18n();
const picker = ref(null);
const review = ref(null);
const preview = ref(null);
const rows = ref([]);
const total = ref(null);
const page = ref(1);
const search = ref('');
const selection = ref({});
const batch = ref(null);
const messages = ref([]);
const previewName = ref('');
const error = ref('');
const busy = ref(false);
const opened = ref(false);
let timer;
let refreshBatch;
let request = 0;
const count = computed(() => Object.keys(selection.value).length);
const running = computed(() =>
  ['preparing', 'running'].includes(batch.value?.status)
);
const ready = computed(
  () => batch.value?.items.filter(item => item.status === 'ready').length || 0
);
const text = key => t(`MARCOX_AI.PENDING.${key}`);
const fail = e => {
  error.value = e.response?.data?.error || t('MARCOX_AI.ERROR');
};
const poll = () => {
  clearTimeout(timer);
  if (running.value && opened.value) timer = setTimeout(refreshBatch, 2000);
};
refreshBatch = async () => {
  try {
    const { data } = await API.getReplyBatch(props.agent.id, batch.value.id);
    batch.value = data.batch;
  } catch (e) {
    fail(e);
  }
  poll();
};
const load = async () => {
  request += 1;
  const version = request;
  busy.value = true;
  error.value = '';
  try {
    const { data } = await API.getPendingReplies(props.agent.id, {
      page: page.value,
      search: search.value,
    });
    if (version !== request) return;
    rows.value = data.conversations;
    total.value = data.total;
    if (data.batch) batch.value = data.batch;
    poll();
  } catch (e) {
    fail(e);
  } finally {
    if (version === request) busy.value = false;
  }
};
const open = () => {
  opened.value = true;
  picker.value.open();
  load();
};
const close = () => {
  opened.value = false;
  clearTimeout(timer);
  picker.value.close();
};
const toggle = row => {
  const next = { ...selection.value };
  if (next[row.id]) delete next[row.id];
  else
    next[row.id] = { id: row.id, trigger_message_id: row.trigger_message_id };
  selection.value = next;
};
const start = async mode => {
  busy.value = true;
  error.value = '';
  try {
    const { data } = await API.createReplyBatch(props.agent.id, {
      mode,
      request_id: crypto.randomUUID(),
      selections: Object.values(selection.value),
    });
    batch.value = data.batch;
    selection.value = {};
    if (mode === 'review') review.value.open();
    poll();
  } catch (e) {
    fail(e);
  } finally {
    busy.value = false;
  }
};
const operation = async (action, itemId = undefined) => {
  busy.value = true;
  try {
    const { data } = await API.updateReplyBatch(
      props.agent.id,
      batch.value.id,
      { operation: action, item_id: itemId }
    );
    batch.value = data.batch;
    poll();
  } catch (e) {
    fail(e);
  } finally {
    busy.value = false;
  }
};
const showPreview = async row => {
  previewName.value = row.name;
  messages.value = [];
  preview.value.open();
  try {
    const { data } = await API.previewPendingReply(props.agent.id, row.id);
    messages.value = data.messages;
  } catch (e) {
    fail(e);
  }
};
onMounted(load);
onBeforeUnmount(() => {
  clearTimeout(timer);
  request += 1;
});
</script>

<template>
  <Button
    size="sm"
    variant="ghost"
    color="slate"
    icon="i-lucide-message-square-text"
    :label="`${text('TITLE')} ${total === null ? '…' : total}`"
    @click="open"
  />
  <Dialog
    ref="picker"
    :title="text('TITLE')"
    :description="text('BODY')"
    width="3xl"
    :show-confirm-button="false"
    :show-cancel-button="false"
    @close="close"
  >
    <div class="max-h-[65vh] space-y-4 overflow-y-auto p-1 text-n-slate-12">
      <p v-if="error" role="alert" class="text-sm text-n-ruby-11">
        {{ error }}
      </p>
      <div class="flex items-center gap-2">
        <input
          v-model="search"
          :placeholder="text('SEARCH')"
          :aria-label="text('SEARCH')"
          class="reset-base min-w-0 flex-1 rounded-lg border border-n-weak bg-n-background px-3 py-2 text-sm"
          @keydown.enter.prevent="
            page = 1;
            load();
          "
        />
        <Button
          variant="outline"
          color="slate"
          icon="i-lucide-search"
          :aria-label="text('SEARCH')"
          :disabled="busy"
          @click="
            page = 1;
            load();
          "
        />
      </div>
      <div class="flex flex-wrap items-center justify-between gap-2 text-sm">
        <p class="m-0">
          {{ text('TOTAL') }}: {{ total ?? '…' }} · {{ text('SELECTED') }}:
          {{ count }}
        </p>
        <div class="flex gap-2">
          <Button
            variant="link"
            :label="text('PAGE_SELECT')"
            :disabled="busy"
            @click="
              rows.forEach(row => {
                selection[row.id] = {
                  id: row.id,
                  trigger_message_id: row.trigger_message_id,
                };
              })
            "
          />
          <Button
            variant="link"
            :label="text('CLEAR')"
            @click="selection = {}"
          />
        </div>
      </div>
      <div class="divide-y divide-n-weak rounded-xl border border-n-weak">
        <div
          v-for="row in rows"
          :key="row.id"
          class="flex items-center gap-3 p-3"
        >
          <input
            type="checkbox"
            :aria-label="row.name"
            :checked="!!selection[row.id]"
            class="size-4 shrink-0 accent-n-blue-9"
            @change="toggle(row)"
          />
          <Avatar
            :name="row.name"
            :src="row.avatar_url"
            :size="36"
            rounded-full
          />
          <div class="min-w-0 flex-1">
            <p class="m-0 truncate text-sm font-semibold text-n-slate-12">
              {{ row.name }}
            </p>
            <p class="m-0 truncate text-xs text-n-slate-11">
              {{ row.inbox }} · {{ new Date(row.sent_at).toLocaleString() }}
            </p>
            <p class="mb-0 mt-1 truncate text-sm text-n-slate-11">
              {{ row.message }}
            </p>
          </div>
          <Button
            variant="ghost"
            color="slate"
            icon="i-lucide-eye"
            :aria-label="`${text('PREVIEW')} ${row.name}`"
            @click="showPreview(row)"
          />
        </div>
        <p
          v-if="!busy && !rows.length"
          class="p-5 text-center text-sm text-n-slate-11"
        >
          {{ text('EMPTY') }}
        </p>
      </div>
      <div class="flex items-center justify-between">
        <Button
          variant="ghost"
          color="slate"
          icon="i-lucide-chevron-left"
          :disabled="page <= 1 || busy"
          :aria-label="text('PREVIOUS')"
          @click="
            page--;
            load();
          "
        />
        <p class="m-0 text-xs text-n-slate-11">
          {{ page }} / {{ Math.max(1, Math.ceil((total || 0) / 25)) }}
        </p>
        <Button
          variant="ghost"
          color="slate"
          icon="i-lucide-chevron-right"
          :disabled="page * 25 >= total || busy"
          :aria-label="text('NEXT')"
          @click="
            page++;
            load();
          "
        />
      </div>
      <div
        v-if="batch"
        class="space-y-2 rounded-xl border border-n-weak bg-n-solid-2 p-4"
      >
        <div class="flex items-center justify-between gap-2">
          <p class="m-0 text-sm font-semibold">
            {{ text('BATCH') }} #{{ batch.id }} ·
            {{ text(`STATUS.${batch.status}`) }}
          </p>
          <Button variant="link" :label="text('VIEW')" @click="review.open()" />
        </div>
        <p class="m-0 text-xs text-n-slate-11">
          {{ text('PROGRESS') }}:
          {{
            (batch.counts.sent || 0) +
            (batch.counts.skipped || 0) +
            (batch.counts.failed || 0) +
            (batch.counts.discarded || 0)
          }}
          / {{ batch.items.length }}
        </p>
        <Button
          v-if="running || ready"
          variant="outline"
          color="ruby"
          icon="i-lucide-square"
          :label="text('STOP')"
          :disabled="busy"
          @click="operation('cancel')"
        />
      </div>
    </div>
    <template #footer>
      <div class="w-full space-y-3">
        <p class="m-0 text-xs text-n-slate-11">{{ text('DIRECT_HINT') }}</p>
        <div class="flex flex-wrap justify-end gap-2">
          <Button
            variant="faded"
            color="slate"
            :label="text('CLOSE')"
            @click="close"
          />
          <Button
            variant="outline"
            icon="i-lucide-scan-text"
            :label="text('ANALYZE')"
            :disabled="!count || busy || running || !!ready"
            @click="start('review')"
          />
          <Button
            icon="i-lucide-send"
            :label="text('DIRECT')"
            :disabled="!count || busy || running || !!ready"
            @click="start('direct')"
          />
        </div>
      </div>
    </template>
  </Dialog>
  <Dialog
    ref="review"
    :title="text('REVIEWS')"
    :description="text('REVIEW_HINT')"
    width="3xl"
    :show-confirm-button="false"
    :show-cancel-button="false"
  >
    <div class="max-h-[65vh] space-y-3 overflow-y-auto p-1 text-n-slate-12">
      <p v-if="error" role="alert" class="text-sm text-n-ruby-11">
        {{ error }}
      </p>
      <article
        v-for="item in batch?.items || []"
        :key="item.id"
        class="rounded-xl border border-n-weak bg-n-solid-2 p-4"
      >
        <div class="mb-3 flex items-center gap-3">
          <Avatar
            :name="item.name"
            :src="item.avatar_url"
            :size="32"
            rounded-full
          />
          <div class="min-w-0 flex-1">
            <p class="m-0 truncate text-sm font-semibold">{{ item.name }}</p>
            <p class="m-0 text-xs text-n-slate-11">
              {{ text(`STATUS.${item.status}`) }}
            </p>
          </div>
          <Button
            v-if="['ready', 'pending', 'analyzing'].includes(item.status)"
            color="ruby"
            variant="ghost"
            icon="i-lucide-trash-2"
            :aria-label="`${text('REMOVE')} ${item.name}`"
            :disabled="busy"
            @click="operation('discard', item.id)"
          />
        </div>
        <div
          v-if="!['discarded', 'failed', 'skipped'].includes(item.status)"
          class="space-y-2"
        >
          <p
            v-for="(part, index) in item.plan.messages || []"
            :key="index"
            class="m-0 whitespace-pre-wrap text-sm text-n-slate-12"
          >
            {{ part }}
          </p>
          <p
            v-if="item.plan.voice_text"
            class="whitespace-pre-wrap rounded-lg bg-n-alpha-1 p-3 text-sm"
          >
            {{ item.plan.voice_text }}
          </p>
          <AudioPlayer
            v-if="item.audio_url"
            :key="item.audio_url"
            :src="item.audio_url"
          />
          <p
            v-for="resource in item.resources"
            :key="resource.title"
            class="m-0 text-xs text-n-blue-11"
          >
            {{ resource.kind }} · {{ resource.title }}
          </p>
          <p v-if="item.pix" class="text-xs text-n-teal-11">
            {{ t('MARCOX_AI.WORKSPACE.PIX') }} · {{ item.pix }}
          </p>
          <p
            v-if="item.plan.handoff || item.plan.alert_rule_ids?.length"
            class="text-xs text-n-amber-11"
          >
            {{ text('ALERT') }} {{ item.plan.handoff_reason }}
          </p>
        </div>
        <p v-if="item.reason" class="m-0 text-sm text-n-slate-11">
          {{ item.reason }}
        </p>
      </article>
    </div>
    <template #footer>
      <div class="flex w-full flex-wrap justify-end gap-2">
        <Button
          variant="faded"
          color="slate"
          icon="i-lucide-arrow-left"
          :label="text('BACK')"
          @click="review.close()"
        />
        <Button
          v-if="ready && batch.status === 'ready'"
          icon="i-lucide-send"
          :label="`${text('SEND_REVIEWED')} (${ready})`"
          :disabled="busy"
          @click="operation('send')"
        />
      </div>
    </template>
  </Dialog>
  <Dialog
    ref="preview"
    :title="previewName"
    width="2xl"
    :show-confirm-button="false"
    :cancel-button-label="text('BACK')"
  >
    <div class="max-h-[60vh] space-y-3 overflow-y-auto p-1 text-n-slate-12">
      <div
        v-for="message in messages"
        :key="message.id"
        class="rounded-xl p-3"
        :class="message.incoming ? 'bg-n-solid-2' : 'bg-n-blue-3'"
      >
        <p class="m-0 whitespace-pre-wrap text-sm">{{ message.content }}</p>
        <p class="m-0 text-xs text-n-slate-11">
          {{ new Date(message.sent_at).toLocaleString() }}
        </p>
      </div>
    </div>
  </Dialog>
</template>
