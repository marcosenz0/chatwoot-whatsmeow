import { ref } from 'vue';

const batches = ref({});
const dismissed = ref({});
const visibleUntil = ref({});
const operations = ref({});

export const useMarcosxAiBatches = () => {
  const rememberBatch = (batch, assistantId) => {
    const value = { ...batch, assistant_id: batch.assistant_id || assistantId };
    const previous = batches.value[value.id];
    const ongoing =
      ['preparing', 'running', 'ready'].includes(value.status) ||
      value.items.some(item => item.delivery_status === 'delivery_pending');
    if (ongoing) visibleUntil.value[value.id] = Infinity;
    else if (previous && visibleUntil.value[value.id] === Infinity)
      visibleUntil.value[value.id] = Date.now() + 6000;
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
    visibleUntil.value = {};
    operations.value = {};
  };
  const dismissBatch = id => {
    dismissed.value = { ...dismissed.value, [id]: true };
  };
  const revealBatch = id => {
    const next = { ...dismissed.value };
    delete next[id];
    dismissed.value = next;
    if (visibleUntil.value[id] !== Infinity)
      visibleUntil.value[id] = Date.now() + 6000;
  };
  const beginOperation = (id, name, label) => {
    operations.value = {
      ...operations.value,
      [id]: { id, name, label, error: '' },
    };
  };
  const finishOperation = (id, error = '') => {
    if (!operations.value[id]) return;
    if (error) operations.value[id] = { ...operations.value[id], error };
    else {
      const next = { ...operations.value };
      delete next[id];
      operations.value = next;
    }
  };
  const dismissOperation = id => finishOperation(id);
  return {
    batches,
    dismissed,
    rememberBatch,
    forgetBatch,
    resetBatches,
    dismissBatch,
    revealBatch,
    visibleUntil,
    operations,
    beginOperation,
    finishOperation,
    dismissOperation,
  };
};
