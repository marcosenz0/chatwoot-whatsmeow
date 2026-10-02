import { computed } from 'vue';
import { useStore } from 'vuex';
import { useUISettings } from './useUISettings';

export function useWhatsmeowPreferences() {
  const store = useStore();
  const { uiSettings, updateUISettings } = useUISettings();
  const key = computed(
    () => `whatsmeow_chats_${store.getters.getCurrentAccountId}`
  );
  const preferences = computed(() => uiSettings.value[key.value] || {});
  const get = id => preferences.value[id] || {};
  const set = (id, changes) =>
    updateUISettings({
      [key.value]: { ...preferences.value, [id]: { ...get(id), ...changes } },
    });
  return { get, set };
}
