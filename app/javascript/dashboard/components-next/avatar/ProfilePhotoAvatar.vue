<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'vuex';
import WhatsappProfileAPI from 'dashboard/api/whatsappProfile';
import Avatar from './Avatar.vue';
import ProfilePhotoViewer from './ProfilePhotoViewer.vue';

const props = defineProps({
  name: { type: String, default: '' },
  src: { type: String, default: '' },
  size: { type: Number, default: 32 },
  status: { type: String, default: '' },
  hideOfflineStatus: { type: Boolean, default: false },
  contactId: { type: Number, default: null },
  inboxId: { type: Number, default: null },
  ownProfile: { type: Boolean, default: false },
});
const { t } = useI18n();
const store = useStore();
const show = ref(false);
const loading = ref(false);
const error = ref(false);
const photo = ref({ photo_url: '', photo_status: 'none' });
let requestId = 0;
const isWhatsmeow = computed(
  () =>
    store.getters['inboxes/getInbox'](props.inboxId)?.channel_type ===
    'Channel::Whatsmeow'
);
const canOpen = computed(() =>
  Boolean(
    props.src || (isWhatsmeow.value && (props.contactId || props.ownProfile))
  )
);
const loadPhoto = async () => {
  requestId += 1;
  const request = requestId;
  loading.value = true;
  error.value = false;
  photo.value = { photo_url: '', photo_status: 'none' };
  try {
    let data;
    if (props.contactId)
      ({ data } = await WhatsappProfileAPI.contactPhoto(
        props.contactId,
        props.inboxId
      ));
    else if (props.ownProfile && isWhatsmeow.value)
      ({ data } = await WhatsappProfileAPI.photo(props.inboxId));
    else data = { photo_url: props.src, photo_status: 'available' };
    if (request === requestId && show.value) photo.value = data;
  } catch {
    if (request === requestId) error.value = true;
  } finally {
    if (request === requestId) loading.value = false;
  }
};
const open = () => {
  show.value = true;
  loadPhoto();
};
const close = () => {
  show.value = false;
  requestId += 1;
  loading.value = false;
};
</script>

<template>
  <span class="inline-flex shrink-0">
    <button
      v-tooltip="canOpen ? t('WHATSAPP_PROFILE.VIEW_PHOTO') : undefined"
      type="button"
      :aria-label="t('WHATSAPP_PROFILE.VIEW_PHOTO')"
      :disabled="!canOpen"
      class="reset-base rounded-lg p-0 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-9 disabled:cursor-default"
      @click.stop="open"
    >
      <Avatar
        :name="name"
        :src="src"
        :size="size"
        :status="status"
        :hide-offline-status="hideOfflineStatus"
      />
    </button>
    <ProfilePhotoViewer
      v-if="show"
      :show="show"
      :name="name"
      :src="photo.photo_url"
      :photo-status="photo.photo_status"
      :loading="loading"
      :error="error"
      @close="close"
      @retry="loadPhoto"
    />
  </span>
</template>
