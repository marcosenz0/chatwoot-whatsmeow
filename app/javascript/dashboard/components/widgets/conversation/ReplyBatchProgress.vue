<script setup>
import { computed, nextTick, onBeforeUnmount, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import API from 'dashboard/api/marcosxAi';
import Button from 'dashboard/components-next/button/Button.vue';
import { useMarcosxAiBatches } from 'dashboard/composables/useMarcosxAiBatches';
import ReplyBatchReview from './ReplyBatchReview.vue';

const { t } = useI18n();
const { batches, dismissed, rememberBatch, resetBatches, dismissBatch } =
  useMarcosxAiBatches();
const minimized = ref(false);
const error = ref('');
const stopping = ref(null);
const sending = ref(null);
const review = ref(null);
const reviewBatchId = ref(null);
const reviewBatch = computed(() => batches.value[reviewBatchId.value] || null);
const errorDismissed = ref(false);
let timer;
let closed = false;
let lastDiscovery = 0;
const records = computed(() =>
  Object.values(batches.value)
    .filter(batch => !dismissed.value[batch.id])
    .sort((a, b) => b.id - a.id)
);
const text = key => t(`MARCOX_AI.PENDING.${key}`);
const active = batch =>
  ['preparing', 'running'].includes(batch.status) ||
  batch.items.some(item => item.delivery_status === 'delivery_pending');
const readyCount = batch =>
  batch.items.filter(item => item.status === 'ready').length;
const finished = batch =>
  batch.items.filter(
    item =>
      ['sent', 'skipped', 'failed', 'discarded'].includes(item.status) &&
      item.delivery_status !== 'delivery_pending'
  ).length;
const progress = batch =>
  batch.status === 'ready' || batch.status === 'preparing'
    ? readyCount(batch) + finished(batch)
    : finished(batch);
const openReview = async (batch, itemId = null) => {
  reviewBatchId.value = batch.id;
  await nextTick();
  review.value.open(itemId);
};
const closeMonitor = () => {
  records.value.forEach(batch => dismissBatch(batch.id));
  errorDismissed.value = true;
  minimized.value = false;
};
const current = batch =>
  batch.items.find(
    item =>
      ['analyzing', 'sending'].includes(item.status) ||
      item.delivery_status === 'delivery_pending'
  );
const status = batch => {
  if (batch.status !== 'completed') return batch.status;
  if (batch.items.some(item => item.delivery_status === 'delivery_pending'))
    return 'delivery_pending';
  if (
    batch.items.some(item =>
      ['failed', 'delivery_failed'].includes(
        item.delivery_status || item.status
      )
    )
  )
    return 'completed_errors';
  if (batch.items.some(item => item.delivery_status === 'delivery_unconfirmed'))
    return 'delivery_unconfirmed';
  return batch.status;
};
async function recover() {
  lastDiscovery = Date.now();
  try {
    const { data } = await API.getActiveReplyBatches();
    if (closed) return;
    data.batches.forEach(batch => rememberBatch(batch));
    error.value = '';
  } catch {
    if (!closed) error.value = text('CONNECTION_ERROR');
  }
}
const poll = async () => {
  if (Date.now() - lastDiscovery >= 15000) {
    await recover();
  }
  const results = await Promise.allSettled(
    Object.values(batches.value)
      .filter(batch => active(batch) || batch.status === 'ready')
      .map(async batch => {
        const { data } = await API.getReplyBatch(batch.assistant_id, batch.id);
        if (!closed) rememberBatch(data.batch, batch.assistant_id);
      })
  );
  if (closed) return;
  if (results.length) {
    error.value = results.some(result => result.status === 'rejected')
      ? text('CONNECTION_ERROR')
      : '';
  }
  timer = setTimeout(poll, 2000);
};
const stop = async batch => {
  stopping.value = batch.id;
  try {
    const { data } = await API.updateReplyBatch(batch.assistant_id, batch.id, {
      operation: 'cancel',
    });
    if (!closed) rememberBatch(data.batch, batch.assistant_id);
  } catch {
    if (!closed) error.value = text('STOP_ERROR');
  } finally {
    stopping.value = null;
  }
};
const send = async batch => {
  if (sending.value === batch.id) return;
  sending.value = batch.id;
  error.value = '';
  try {
    const { data } = await API.updateReplyBatch(batch.assistant_id, batch.id, {
      operation: 'send',
    });
    if (!closed) rememberBatch(data.batch, batch.assistant_id);
  } catch (e) {
    if (!closed) {
      errorDismissed.value = false;
      error.value = e.response?.data?.error || text('ACTION_ERROR');
    }
  } finally {
    sending.value = null;
  }
};
onMounted(async () => {
  await recover();
  if (!closed) poll();
});
onBeforeUnmount(() => {
  closed = true;
  clearTimeout(timer);
  resetBatches();
});
</script>

<template>
  <aside
    v-if="records.length || (error && !errorDismissed)"
    class="fixed bottom-4 end-4 z-50 max-w-[calc(100vw-2rem)] text-n-slate-12"
    :aria-label="text('MONITOR')"
  >
    <Button
      v-if="minimized"
      size="sm"
      :icon="
        records.some(active)
          ? 'i-lucide-loader-circle'
          : 'i-lucide-message-square-text'
      "
      :label="`${text('MONITOR')} (${records.length})`"
      @click="minimized = false"
    />
    <div
      v-else
      class="w-80 max-w-full overflow-hidden rounded-xl border border-n-weak bg-n-solid-1 shadow-lg"
    >
      <header
        class="flex items-center justify-between gap-2 border-b border-n-weak px-3 py-2"
      >
        <p class="m-0 text-sm font-semibold">{{ text('MONITOR') }}</p>
        <div class="flex items-center gap-1">
          <Button
            size="xs"
            variant="ghost"
            color="slate"
            icon="i-lucide-minus"
            :aria-label="text('MINIMIZE')"
            @click="minimized = true"
          />
          <Button
            size="xs"
            variant="ghost"
            color="slate"
            icon="i-lucide-x"
            :aria-label="text('CLOSE_MONITOR')"
            :title="text('CLOSE_MONITOR_HINT')"
            @click="closeMonitor"
          />
        </div>
      </header>
      <div v-if="error" role="alert" class="p-3 text-xs text-n-ruby-11">
        {{ error }}
        <Button
          size="xs"
          variant="link"
          :label="text('RECONNECT')"
          @click="recover"
        />
      </div>
      <div class="max-h-[50vh] divide-y divide-n-weak overflow-y-auto">
        <section v-for="batch in records" :key="batch.id" class="space-y-2 p-3">
          <div class="flex items-start justify-between gap-2">
            <p class="m-0 text-xs font-semibold">
              {{ batch.assistant_name }} · #{{ batch.id }}
            </p>
            <Button
              v-if="
                records.length > 1 ||
                !['preparing', 'running', 'ready'].includes(batch.status)
              "
              size="xs"
              variant="ghost"
              color="slate"
              icon="i-lucide-x"
              :aria-label="text('DISMISS')"
              @click="dismissBatch(batch.id)"
            />
          </div>
          <p class="m-0 text-xs" role="status" aria-live="polite">
            {{ text(`STATUS.${status(batch)}`) }} · {{ progress(batch) }}/{{
              batch.items.length
            }}
          </p>
          <progress
            class="h-1.5 w-full accent-n-blue-9"
            :value="progress(batch)"
            :max="Math.max(1, batch.items.length)"
            :aria-label="
              text(
                batch.status === 'ready' || batch.status === 'preparing'
                  ? 'PREPARED'
                  : 'PROGRESS'
              )
            "
          />
          <p
            v-if="batch.status === 'ready'"
            class="m-0 text-xs text-n-slate-11"
          >
            {{ text('READY_HINT') }}
          </p>
          <div class="flex flex-wrap gap-2">
            <Button
              size="xs"
              variant="outline"
              icon="i-lucide-eye"
              :label="text('REVIEWS')"
              @click="openReview(batch)"
            />
            <Button
              v-if="batch.status === 'ready' && readyCount(batch)"
              size="xs"
              icon="i-lucide-send"
              :label="`${text('SEND_ALL')} (${readyCount(batch)})`"
              :disabled="sending === batch.id || stopping === batch.id"
              @click="send(batch)"
            />
          </div>
          <p v-if="current(batch)" class="m-0 truncate text-xs text-n-blue-11">
            {{
              text(
                `STATUS.${current(batch).delivery_status || current(batch).status}`
              )
            }}:
            {{ current(batch).name }}
          </p>
          <details class="text-xs">
            <summary class="cursor-pointer text-n-slate-11">
              {{ text('RESULTS') }}
            </summary>
            <ul class="m-0 mt-2 list-none space-y-2 p-0">
              <li
                v-for="item in batch.items"
                :key="item.id"
                class="space-y-0.5"
              >
                <p
                  class="m-0"
                  :class="
                    ['failed', 'delivery_failed'].includes(
                      item.delivery_status || item.status
                    )
                      ? 'text-n-ruby-11'
                      : 'text-n-slate-12'
                  "
                >
                  <button
                    type="button"
                    class="text-start font-medium text-n-blue-11 hover:underline"
                    :aria-label="`${text('REVIEW_CONTACT')} ${item.name}`"
                    @click="openReview(batch, item.id)"
                  >
                    {{ item.name }}
                  </button>
                  ·
                  {{ text(`STATUS.${item.delivery_status || item.status}`) }}
                </p>
                <a
                  v-if="batch.account_id && item.conversation_id"
                  :href="`/app/accounts/${batch.account_id}/conversations/${item.conversation_id}`"
                  target="_blank"
                  rel="noopener noreferrer"
                  class="text-n-blue-11 hover:underline"
                  >{{ text('OPEN_CONVERSATION') }}</a
                >
                <p v-if="item.reason" class="m-0 text-n-slate-11">
                  {{ item.reason }}
                </p>
              </li>
            </ul>
          </details>
          <Button
            v-if="['preparing', 'running', 'ready'].includes(batch.status)"
            size="xs"
            variant="outline"
            color="ruby"
            :label="text('STOP')"
            :disabled="stopping === batch.id"
            @click="stop(batch)"
          />
        </section>
      </div>
    </div>
  </aside>
  <ReplyBatchReview ref="review" :batch="reviewBatch" />
</template>
