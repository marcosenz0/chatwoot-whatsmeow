import { ref, watch } from 'vue';
import { useStore } from 'vuex';
import WhatsappProfileAPI from 'dashboard/api/whatsappProfile';

const photos = new Map();
const PHOTO_CACHE_MS = 5 * 60 * 1000;

export function useInboxProfilePhoto(inboxId, enabled) {
  const store = useStore();
  const src = ref('');
  watch(
    [inboxId, enabled],
    async ([id, active], _, onCleanup) => {
      let current = true;
      onCleanup(() => {
        current = false;
      });
      src.value = '';
      const inbox = store.getters['inboxes/getInbox'](id);
      if (!active || inbox?.channel_type !== 'Channel::Whatsmeow') return;
      const key = `${store.getters.getCurrentAccountId}:${id}`;
      let cached = photos.get(key);
      if (!cached || Date.now() - cached.createdAt > PHOTO_CACHE_MS) {
        cached = {
          createdAt: Date.now(),
          request: WhatsappProfileAPI.photo(id)
            .then(({ data }) => data.photo_url || '')
            .catch(() => ''),
        };
        photos.set(key, cached);
      }
      const photo = await cached.request;
      if (current) src.value = photo || inbox.avatar_url || '';
    },
    { immediate: true }
  );
  return src;
}
