<script setup>
import { computed, onBeforeUnmount, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useAbortableRequest } from 'dashboard/composables/useAbortableRequest';
import MarcosxAiAPI from 'dashboard/api/marcosxAi';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import AudioPlayer from 'dashboard/components-next/audio/AudioPlayer.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';

const props = defineProps({
  conversationId: { type: Number, required: true },
  assistantId: { type: Number, default: null },
});
const emit = defineEmits(['useAudio']);
const { t } = useI18n();
const request = useAbortableRequest();
const dialog = ref(null);
const content = ref('');
const assistantName = ref('');
const maxCharacters = ref(0);
const audio = ref(null);
const previewUrl = ref('');
const spokenText = ref('');
const visible = ref(false);
let generation = 0;
const canGenerate = computed(
  () => content.value.trim() && content.value.length <= maxCharacters.value
);
const canUse = computed(
  () => audio.value && spokenText.value === content.value.trim()
);

function clearPreview() {
  if (previewUrl.value) URL.revokeObjectURL(previewUrl.value);
  previewUrl.value = '';
  audio.value = null;
  spokenText.value = '';
}
function reset() {
  generation += 1;
  request.abort();
  clearPreview();
  visible.value = false;
  content.value = '';
  assistantName.value = '';
  maxCharacters.value = 0;
}
async function notifyError(error) {
  let data = error.response?.data;
  if (data instanceof Blob) {
    try {
      data = JSON.parse(await data.text());
    } catch {
      data = null;
    }
  }
  useAlert(data?.error || t('MARCOX_AI.CONVERSATION.ERROR'));
}
async function generateAudio() {
  if (!canGenerate.value) return;
  clearPreview();
  const currentGeneration = generation;
  const text = content.value.trim();
  try {
    const response = await request.run(signal =>
      MarcosxAiAPI.previewConversationVoice(props.conversationId, text, {
        signal,
      })
    );
    if (!response || currentGeneration !== generation || !visible.value) return;
    audio.value = response.data;
    previewUrl.value = URL.createObjectURL(response.data);
    spokenText.value = text;
  } catch (error) {
    if (currentGeneration === generation) await notifyError(error);
  }
}
async function open() {
  reset();
  visible.value = true;
  dialog.value.open();
  const currentGeneration = generation;
  try {
    const response = await request.run(signal =>
      MarcosxAiAPI.generateDraft(
        props.conversationId,
        { action: 'voice_reply' },
        { signal }
      )
    );
    if (!response || currentGeneration !== generation || !visible.value) return;
    content.value = response.data.content;
    assistantName.value = response.data.assistant_name;
    maxCharacters.value = response.data.max_characters;
    await generateAudio();
  } catch (error) {
    if (currentGeneration === generation) await notifyError(error);
  }
}
function useAudio() {
  if (!canUse.value) return;
  const file = new File([audio.value], 'agent-voice.mp3', {
    type: 'audio/mpeg',
  });
  emit('useAudio', { file, type: file.type, isRecordedAudio: true });
  dialog.value.close();
  reset();
}
watch(
  () => [props.conversationId, props.assistantId],
  () => {
    dialog.value?.close();
    reset();
  }
);
onBeforeUnmount(reset);
defineExpose({ open });
</script>

<template>
  <Dialog
    ref="dialog"
    width="xl"
    :title="t('MARCOX_AI.COMPOSER.VOICE_TITLE')"
    :description="t('MARCOX_AI.COMPOSER.VOICE_HINT')"
    :show-confirm-button="false"
    :show-cancel-button="false"
    @close="reset"
  >
    <div class="flex min-w-0 flex-col gap-4">
      <p v-if="assistantName" class="m-0 text-sm font-medium text-n-slate-12">
        {{ t('MARCOX_AI.DECISION.COMPOSER', { name: assistantName }) }}
      </p>
      <label class="flex min-w-0 flex-col gap-2 text-sm text-n-slate-12">
        {{ t('MARCOX_AI.COMPOSER.VOICE_TEXT') }}
        <textarea
          v-model="content"
          rows="4"
          class="!m-0 !min-h-28 !w-full !resize-y !rounded-lg !border !border-solid !border-n-weak !bg-n-solid-2 !p-3 focus:!border-n-blue-9"
          :disabled="request.isPending.value"
        />
      </label>
      <p v-if="maxCharacters" class="m-0 text-xs text-n-slate-11">
        {{
          t('MARCOX_AI.COMPOSER.VOICE_COUNT', {
            count: content.length,
            max: maxCharacters,
          })
        }}
      </p>
      <div
        v-if="request.isPending.value"
        class="flex items-center gap-2 text-sm text-n-blue-11"
        role="status"
      >
        <Spinner class="size-4" />
        {{ t('MARCOX_AI.COMPOSER.VOICE_WORKING') }}
      </div>
      <div
        v-if="previewUrl"
        class="rounded-xl border border-n-weak bg-n-solid-3 p-3"
      >
        <AudioPlayer :key="previewUrl" :src="previewUrl" />
      </div>
      <p v-if="previewUrl && !canUse" class="m-0 text-xs text-n-slate-11">
        {{ t('MARCOX_AI.COMPOSER.VOICE_CHANGED') }}
      </p>
      <div class="flex flex-wrap justify-end gap-2">
        <Button
          type="button"
          slate
          :label="t('MARCOX_AI.CANCEL')"
          @click="dialog.close()"
        />
        <Button
          type="button"
          outline
          icon="i-lucide-refresh-cw"
          :label="t('MARCOX_AI.COMPOSER.VOICE_GENERATE')"
          :disabled="!canGenerate || request.isPending.value"
          @click="generateAudio"
        />
        <Button
          type="button"
          icon="i-lucide-mic"
          :label="t('MARCOX_AI.COMPOSER.VOICE_USE')"
          :disabled="!canUse || request.isPending.value"
          @click="useAudio"
        />
      </div>
    </div>
  </Dialog>
</template>
