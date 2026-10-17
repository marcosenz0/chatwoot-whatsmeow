<script setup>
import { computed, onBeforeUnmount, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import API from 'dashboard/api/marcosxAi';
import Button from 'dashboard/components-next/button/Button.vue';
import { useMarcosxAiBatches } from 'dashboard/composables/useMarcosxAiBatches';

const { t } = useI18n();
const { batches, rememberBatch, forgetBatch, resetBatches } =
  useMarcosxAiBatches();
const minimized = ref(false);
const error = ref('');
const stopping = ref(null);
let timer;
let closed = false;
let lastDiscovery = 0;
const records = computed(() =>
  Object.values(batches.value).sort((a, b) => b.id - a.id)
);
const text = key => t(`MARCOX_AI.PENDING.${key}`);
const active = batch =>
  ['preparing', 'running'].includes(batch.status) ||
  batch.items.some(item => item.delivery_status === 'delivery_pending');
const finished = batch =>
  batch.items.filter(
    item =>
      ['sent', 'skipped', 'failed', 'discarded', 'ready'].includes(
        item.status
      ) && item.delivery_status !== 'delivery_pending'
  ).length;
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
    records.value.filter(active).map(async batch => {
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
    v-if="records.length || error"
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
        <Button
          size="xs"
          variant="ghost"
          color="slate"
          icon="i-lucide-minus"
          :aria-label="text('MINIMIZE')"
          @click="minimized = true"
        />
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
              v-if="!active(batch) && batch.status !== 'ready'"
              size="xs"
              variant="ghost"
              color="slate"
              icon="i-lucide-x"
              :aria-label="text('DISMISS')"
              @click="forgetBatch(batch.id)"
            />
          </div>
          <p class="m-0 text-xs" role="status" aria-live="polite">
            {{ text(`STATUS.${status(batch)}`) }} · {{ finished(batch) }}/{{
              batch.items.length
            }}
          </p>
          <progress
            class="h-1.5 w-full accent-n-blue-9"
            :value="finished(batch)"
            :max="Math.max(1, batch.items.length)"
            :aria-label="text('PROGRESS')"
          />
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
                  {{ item.name }} ·
                  {{ text(`STATUS.${item.delivery_status || item.status}`) }}
                </p>
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
</template>
