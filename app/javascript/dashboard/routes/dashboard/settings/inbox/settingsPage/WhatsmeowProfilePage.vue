<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import WhatsappProfileAPI from 'dashboard/api/whatsappProfile';
import Avatar from 'next/avatar/Avatar.vue';
import Button from 'next/button/Button.vue';
import Dialog from 'next/dialog/Dialog.vue';
import Spinner from 'next/spinner/Spinner.vue';
import DropdownContainer from 'next/dropdown-menu/base/DropdownContainer.vue';
import DropdownBody from 'next/dropdown-menu/base/DropdownBody.vue';
import DropdownItem from 'next/dropdown-menu/base/DropdownItem.vue';
import ProfilePhotoViewer from 'next/avatar/ProfilePhotoViewer.vue';
import ProfilePhotoEditor from 'next/avatar/ProfilePhotoEditor.vue';
import ProfileCamera from 'next/avatar/ProfileCamera.vue';
import AiSelect from 'dashboard/routes/dashboard/captain/components/AiSelect.vue';
import WhatsmeowBusinessProfile from './WhatsmeowBusinessProfile.vue';

const props = defineProps({ inbox: { type: Object, required: true } });
const { t } = useI18n();
const profile = ref(null);
const loading = ref(false);
const error = ref(false);
const saving = ref(false);
const editing = ref('');
const draft = ref('');
const aboutDuration = ref(86400);
const durations = computed(() =>
  [3600, 28800, 86400, 259200, 604800].map(value => ({
    value,
    label: t(`WHATSAPP_PROFILE.DURATIONS.${value}`),
  }))
);
const uploadInput = ref(null);
const removalDialog = ref(null);
const showPhoto = ref(false);
const showCamera = ref(false);
const pendingFile = ref(null);
let requestId = 0;
const hasPhoto = computed(() => Boolean(profile.value?.photo_url));
const load = async () => {
  requestId += 1;
  const request = requestId;
  loading.value = true;
  error.value = false;
  try {
    const { data } = await WhatsappProfileAPI.show(props.inbox.id);
    if (request === requestId) {
      profile.value = data;
      editing.value = '';
    }
  } catch {
    if (request === requestId) error.value = true;
  } finally {
    if (request === requestId) loading.value = false;
  }
};
const edit = field => {
  draft.value = profile.value[field];
  aboutDuration.value = profile.value.about_duration || 86400;
  editing.value = field;
};
const save = async payload => {
  saving.value = true;
  try {
    await WhatsappProfileAPI.update(props.inbox.id, payload);
    useAlert(t('WHATSAPP_PROFILE.SAVED'));
    await load();
  } catch {
    useAlert(t('WHATSAPP_PROFILE.SAVE_ERROR'));
  } finally {
    saving.value = false;
  }
};
const saveField = field => {
  const payload = { [field]: draft.value };
  if (field === 'about') payload.about_duration = aboutDuration.value;
  return save(payload);
};
const pickPhoto = file => {
  if (
    !file ||
    !['image/jpeg', 'image/png', 'image/webp', 'image/gif'].includes(
      file.type
    ) ||
    file.size > 15 * 1024 * 1024
  ) {
    useAlert(t('WHATSAPP_PROFILE.FILE_ERROR'));
    return;
  }
  pendingFile.value = file;
};
const upload = event => {
  const file = event.target.files?.[0];
  if (file) pickPhoto(file);
  event.target.value = '';
};
const capture = file => {
  showCamera.value = false;
  pickPhoto(file);
};
const savePhoto = async photo => {
  saving.value = true;
  try {
    const { data } = await WhatsappProfileAPI.updatePhoto(
      props.inbox.id,
      photo
    );
    Object.assign(profile.value, data);
    pendingFile.value = null;
    useAlert(t('WHATSAPP_PROFILE.PHOTO_SAVED'));
  } catch {
    useAlert(t('WHATSAPP_PROFILE.SAVE_ERROR'));
  } finally {
    saving.value = false;
  }
};
const removePhoto = async () => {
  saving.value = true;
  try {
    const { data } = await WhatsappProfileAPI.removePhoto(props.inbox.id);
    Object.assign(profile.value, data);
    removalDialog.value.close();
    useAlert(t('WHATSAPP_PROFILE.PHOTO_REMOVED'));
  } catch {
    useAlert(t('WHATSAPP_PROFILE.SAVE_ERROR'));
  } finally {
    saving.value = false;
  }
};
watch(
  () => props.inbox.id,
  () => {
    profile.value = null;
    load();
  }
);
onMounted(load);
</script>

<template>
  <section class="mx-6 max-w-4xl space-y-6 py-6">
    <header class="flex flex-wrap items-start justify-between gap-4">
      <div>
        <h2 class="mb-1 text-lg font-medium text-n-slate-12">
          {{ t('WHATSAPP_PROFILE.TITLE') }}
        </h2>
        <p class="mb-0 text-sm text-n-slate-11">
          {{ t('WHATSAPP_PROFILE.DESCRIPTION_HELP') }}
        </p>
      </div>
      <Button
        :label="t('WHATSAPP_PROFILE.REFRESH')"
        icon="i-lucide-refresh-cw"
        slate
        outline
        :disabled="loading || saving"
        @click="load"
      />
    </header>
    <div v-if="loading" class="flex justify-center py-12"><Spinner /></div>
    <div
      v-else-if="error"
      role="alert"
      class="flex flex-col items-start gap-4 rounded-xl border border-n-weak p-6"
    >
      <p class="mb-0 text-sm text-n-slate-11">
        {{ t('WHATSAPP_PROFILE.LOAD_ERROR') }}
      </p>
      <Button
        :label="t('WHATSAPP_PROFILE.RETRY')"
        slate
        outline
        @click="load"
      />
    </div>
    <div
      v-else-if="profile"
      class="grid gap-8 md:grid-cols-[13rem_minmax(0,1fr)]"
    >
      <div
        class="flex flex-col items-center gap-4 rounded-xl border border-n-weak p-6 md:self-start"
      >
        <DropdownContainer class="z-10">
          <template #trigger="{ toggle, isOpen }">
            <button
              type="button"
              :aria-label="t('WHATSAPP_PROFILE.CHANGE_PHOTO')"
              :aria-expanded="isOpen"
              aria-haspopup="menu"
              class="reset-base group relative rounded-full p-0 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-9"
              :disabled="saving"
              @click="toggle"
            >
              <Avatar
                :src="profile.photo_url"
                :name="profile.name"
                :size="128"
                rounded-full
              />
              <span
                class="absolute inset-0 flex items-center justify-center rounded-full bg-black/50 text-white opacity-0 transition-opacity group-hover:opacity-100 group-focus-visible:opacity-100"
                :class="{ 'opacity-100': isOpen }"
                ><span class="i-lucide-camera size-9"
              /></span>
            </button>
          </template>
          <DropdownBody class="!start-0 w-48" role="menu">
            <DropdownItem
              v-if="hasPhoto"
              :label="t('WHATSAPP_PROFILE.VIEW_PHOTO')"
              icon="i-lucide-eye"
              :click="() => (showPhoto = true)"
              role="menuitem"
            />
            <DropdownItem
              :label="t('WHATSAPP_PROFILE.TAKE_PHOTO')"
              icon="i-lucide-camera"
              :click="() => (showCamera = true)"
              role="menuitem"
            />
            <DropdownItem
              :label="t('WHATSAPP_PROFILE.UPLOAD_PHOTO')"
              icon="i-lucide-folder-open"
              :click="() => uploadInput.click()"
              role="menuitem"
            />
            <DropdownItem
              v-if="hasPhoto"
              :label="t('WHATSAPP_PROFILE.REMOVE_PHOTO')"
              icon="i-lucide-trash-2"
              :click="() => removalDialog.open()"
              role="menuitem"
              class="border-t border-n-weak pt-1"
            />
          </DropdownBody>
        </DropdownContainer>
        <input
          ref="uploadInput"
          type="file"
          accept="image/jpeg,image/png,image/webp,image/gif"
          class="hidden"
          :aria-label="t('WHATSAPP_PROFILE.UPLOAD_PHOTO')"
          @change="upload"
        />
        <p class="mb-0 text-center text-xs text-n-slate-11">
          {{ t('WHATSAPP_PROFILE.PHOTO_HELP') }}
        </p>
        <span
          class="rounded-full bg-n-alpha-2 px-3 py-1 text-xs text-n-slate-11"
          >{{
            t(
              profile.is_business
                ? 'WHATSAPP_PROFILE.BUSINESS'
                : 'WHATSAPP_PROFILE.PERSONAL'
            )
          }}</span
        >
      </div>
      <div class="min-w-0 space-y-6">
        <section
          v-for="field in ['name', 'about']"
          :key="field"
          class="border-b border-n-weak pb-6"
        >
          <h3 class="mb-3 text-sm font-medium text-n-slate-11">
            {{ t(`WHATSAPP_PROFILE.${field.toUpperCase()}`) }}
          </h3>
          <form
            v-if="editing === field"
            class="space-y-3"
            @submit.prevent="saveField(field)"
          >
            <input
              v-if="field === 'name'"
              v-model="draft"
              required
              maxlength="25"
              :aria-label="t('WHATSAPP_PROFILE.NAME')"
              :disabled="saving"
              class="!mb-0 w-full rounded-lg bg-n-solid-1"
            />
            <div v-if="field === 'about'" class="space-y-2">
              <label class="text-sm text-n-slate-11">{{
                t('WHATSAPP_PROFILE.ABOUT_DURATION')
              }}</label>
              <AiSelect
                v-model="aboutDuration"
                :options="durations"
                :label="t('WHATSAPP_PROFILE.ABOUT_DURATION')"
                :disabled="saving"
              />
              <p class="mb-0 text-xs text-n-slate-11">
                {{ t('WHATSAPP_PROFILE.ABOUT_DURATION_HELP') }}
              </p>
            </div>
            <textarea
              v-if="field === 'about'"
              v-model="draft"
              maxlength="139"
              rows="3"
              :aria-label="t('WHATSAPP_PROFILE.ABOUT')"
              :disabled="saving"
              class="!mb-0 w-full rounded-lg bg-n-solid-1"
            />
            <div class="flex items-center gap-2">
              <Button
                type="submit"
                :label="t('WHATSAPP_PROFILE.SAVE')"
                icon="i-lucide-check"
                :disabled="saving"
                :is-loading="saving"
              />
              <Button
                type="button"
                :label="t('WHATSAPP_PROFILE.CANCEL')"
                slate
                ghost
                :disabled="saving"
                @click="editing = ''"
              />
              <span class="ms-auto text-xs text-n-slate-11">{{
                t('WHATSAPP_PROFILE.CHARACTER_COUNT', {
                  count: draft.length,
                  max: field === 'name' ? 25 : 139,
                })
              }}</span>
            </div>
          </form>
          <div v-else class="flex items-start justify-between gap-4">
            <p
              class="mb-0 whitespace-pre-wrap break-words text-sm text-n-slate-12"
            >
              {{ field === 'about' ? profile.about_emoji : '' }}
              {{ profile[field] || t('WHATSAPP_PROFILE.NOT_SET') }}
            </p>
            <Button
              v-tooltip="
                t('WHATSAPP_PROFILE.EDIT_FIELD', {
                  field: t(`WHATSAPP_PROFILE.${field.toUpperCase()}`),
                })
              "
              :aria-label="
                t('WHATSAPP_PROFILE.EDIT_FIELD', {
                  field: t(`WHATSAPP_PROFILE.${field.toUpperCase()}`),
                })
              "
              icon="i-lucide-pencil"
              slate
              ghost
              :disabled="saving"
              @click="edit(field)"
            />
          </div>
        </section>
        <section class="space-y-3">
          <h3 class="text-sm font-medium text-n-slate-11">
            {{ t('WHATSAPP_PROFILE.PHONE') }}
          </h3>
          <p class="mb-0 text-sm text-n-slate-12">{{ profile.phone }}</p>
        </section>
        <WhatsmeowBusinessProfile
          v-if="profile.is_business && profile.business"
          :profile="profile.business"
          :saving="saving"
          class="border-t border-n-weak pt-6"
          @save="business => save({ business })"
        />
      </div>
    </div>
    <ProfilePhotoViewer
      v-if="profile"
      :show="showPhoto"
      :name="profile.name"
      :src="profile.photo_url"
      :photo-status="profile.photo_status"
      @close="showPhoto = false"
      @retry="load"
    />
    <ProfilePhotoEditor
      v-if="pendingFile"
      :file="pendingFile"
      :saving="saving"
      @close="pendingFile = null"
      @confirm="savePhoto"
    />
    <ProfileCamera
      v-if="showCamera"
      @close="showCamera = false"
      @capture="capture"
    />
    <Dialog
      ref="removalDialog"
      type="alert"
      :title="t('WHATSAPP_PROFILE.REMOVE_TITLE')"
      :description="t('WHATSAPP_PROFILE.REMOVE_HELP')"
      :confirm-button-label="t('WHATSAPP_PROFILE.REMOVE_PHOTO')"
      :is-loading="saving"
      :prevent-close="saving"
      @confirm="removePhoto"
    />
  </section>
</template>
