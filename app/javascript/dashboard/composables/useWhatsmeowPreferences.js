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
  const lists = computed(() =>
    [
      ...new Set(
        Object.values(preferences.value)
          .map(p => p.list)
          .filter(Boolean)
      ),
    ].sort()
  );
  return { preferences, get, set, lists };
}
