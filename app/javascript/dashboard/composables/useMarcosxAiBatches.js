import { ref } from 'vue';

const batches = ref({});
const dismissed = ref({});

export const useMarcosxAiBatches = () => {
  const rememberBatch = (batch, assistantId) => {
    const value = { ...batch, assistant_id: batch.assistant_id || assistantId };
    if (JSON.stringify(batches.value[value.id]) !== JSON.stringify(value)) {
      batches.value = { ...batches.value, [value.id]: value };
    }
    return value;
  };
  const forgetBatch = id => {
    const next = { ...batches.value };
    delete next[id];
    batches.value = next;
  };
  const resetBatches = () => {
    batches.value = {};
    dismissed.value = {};
  };
  const dismissBatch = id => {
    dismissed.value = { ...dismissed.value, [id]: true };
  };
  const revealBatch = id => {
    const next = { ...dismissed.value };
    delete next[id];
    dismissed.value = next;
  };
  return {
    batches,
    dismissed,
    rememberBatch,
    forgetBatch,
    resetBatches,
    dismissBatch,
    revealBatch,
  };
};
