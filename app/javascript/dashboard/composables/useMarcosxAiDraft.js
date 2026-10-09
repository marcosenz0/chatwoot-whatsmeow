import { ref, computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { useAbortableRequest } from 'dashboard/composables/useAbortableRequest';
import MarcosxAiAPI from 'dashboard/api/marcosxAi';

export function useMarcosxAiDraft() {
  const { t } = useI18n();
  const currentChat = useMapGetter('getSelectedChat');
  const request = useAbortableRequest();
  const showEditor = ref(false);
  const isContentReady = ref(false);
  const generatedContent = ref('');
  let generation = 0;

  function reset() {
    generation += 1;
    request.abort();
    showEditor.value = false;
    isContentReady.value = false;
    generatedContent.value = '';
  }

  watch(() => currentChat.value?.id, reset);

  async function execute(action, content, instruction) {
    const conversationId = currentChat.value?.id;
    reset();
    const currentGeneration = generation;
    try {
      const response = await request.run(signal =>
        MarcosxAiAPI.generateDraft(
          conversationId,
          { action, content, instruction },
          { signal }
        )
      );
      if (!response || currentGeneration !== generation) return;
      generatedContent.value = response.data.content;
      showEditor.value = true;
      isContentReady.value = true;
    } catch (error) {
      if (currentGeneration !== generation) return;
      useAlert(
        error.response?.data?.error || t('MARCOX_AI.CONVERSATION.ERROR')
      );
    }
  }

  function accept() {
    const content = generatedContent.value;
    reset();
    return content;
  }

  async function sendFollowUp(instruction) {
    if (!instruction.trim()) return;
    await execute('refine', generatedContent.value, instruction);
  }

  return {
    showEditor,
    isGenerating: request.isPending,
    isContentReady,
    generatedContent,
    isActive: computed(() => showEditor.value || request.isPending.value),
    isButtonDisabled: computed(
      () => request.isPending.value || !isContentReady.value
    ),
    editorTransitionKey: computed(() =>
      showEditor.value || request.isPending.value ? 'copilot' : 'rich'
    ),
    reset,
    toggleEditor: () => {
      showEditor.value = !showEditor.value;
    },
    setContentReady: () => {
      isContentReady.value = true;
    },
    execute,
    sendFollowUp,
    accept,
  };
}
