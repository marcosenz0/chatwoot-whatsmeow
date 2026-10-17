<script setup>
import { computed, onBeforeUnmount, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import API from 'dashboard/api/marcosxAi';
import { useMarcosxAiBatches } from 'dashboard/composables/useMarcosxAiBatches';
import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import AudioPlayer from 'dashboard/components-next/audio/AudioPlayer.vue';

const props = defineProps({ batch: { type: Object, default: null } });
const emit = defineEmits(['updated']);
const { t } = useI18n();
const { rememberBatch, revealBatch } = useMarcosxAiBatches();
const dialog = ref(null);
const selectedItemId = ref(null);
const error = ref('');
const busy = ref(false);
let disposed = false;
const text = key => t(`MARCOX_AI.PENDING.${key}`);
const ready = computed(
  () => props.batch?.items.filter(item => item.status === 'ready').length || 0
);
const orderedItems = computed(() =>
  [...(props.batch?.items || [])].sort(
    (a, b) =>
      Number(b.id === selectedItemId.value) -
      Number(a.id === selectedItemId.value)
  )
);
const adopt = batch => {
  if (disposed) return;
  rememberBatch(batch, props.batch.assistant_id);
  emit('updated', batch);
};
const open = (itemId = null) => {
  selectedItemId.value = itemId;
  error.value = '';
  revealBatch(props.batch.id);
  dialog.value.open();
};
const operation = async (action, itemId = undefined) => {
  if (busy.value) return;
  busy.value = true;
  error.value = '';
  try {
    const { data } = await API.updateReplyBatch(
      props.batch.assistant_id,
      props.batch.id,
      { operation: action, item_id: itemId }
    );
    adopt(data.batch);
    if (!disposed && action === 'send') dialog.value.close();
  } catch (e) {
    if (!disposed)
      error.value = e.response?.data?.error || text('ACTION_ERROR');
  } finally {
    busy.value = false;
  }
};
onBeforeUnmount(() => {
  disposed = true;
});
defineExpose({ open, close: () => dialog.value.close() });
</script>

<template>
  <Dialog
    ref="dialog"
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
        v-for="item in orderedItems"
        :key="item.id"
        class="rounded-xl border border-n-weak bg-n-solid-2 p-4"
        :class="item.id === selectedItemId ? 'ring-2 ring-n-blue-9' : ''"
      >
        <div class="mb-3 flex flex-wrap items-center gap-3">
          <Avatar
            :name="item.name"
            :src="item.avatar_url"
            :size="32"
            rounded-full
          />
          <div class="min-w-0 flex-1">
            <p class="m-0 truncate text-sm font-semibold">{{ item.name }}</p>
            <p class="m-0 text-xs text-n-slate-11">
              {{ text(`STATUS.${item.delivery_status || item.status}`) }}
            </p>
          </div>
          <a
            v-if="batch.account_id && item.conversation_id"
            :href="`/app/accounts/${batch.account_id}/conversations/${item.conversation_id}`"
            target="_blank"
            rel="noopener noreferrer"
            class="text-xs text-n-blue-11 hover:underline"
            >{{ text('OPEN_CONVERSATION') }}</a
          >
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
          @click="dialog.close()"
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
</template>
