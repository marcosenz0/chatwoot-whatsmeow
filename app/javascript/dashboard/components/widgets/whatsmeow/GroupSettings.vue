<script setup>
import { computed } from 'vue';
import Input from 'next/input/Input.vue';
import Button from 'next/button/Button.vue';
import Avatar from 'next/avatar/Avatar.vue';
import { groupPhoto } from 'dashboard/helper/whatsmeowGroup';
import { useAlert } from 'dashboard/composables';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  modelValue: { type: Object, required: true },
  canEdit: { type: Boolean, default: true },
  canManage: { type: Boolean, default: true },
});
const emit = defineEmits(['update:modelValue']);
const { t } = useI18n();
const update = (key, value) =>
  emit('update:modelValue', { ...props.modelValue, [key]: value });
const photoUrl = computed(() =>
  props.modelValue.photo
    ? `data:image/jpeg;base64,${props.modelValue.photo}`
    : props.modelValue.profile_picture_url
);
const permissions = [
  'allow_member_edit',
  'allow_member_send',
  'allow_member_add',
  'require_approval',
];
async function upload(event) {
  try {
    update('photo', await groupPhoto(event.target.files[0]));
  } catch {
    useAlert(t('WHATSMEOW_UI.PHOTO_ERROR'));
  }
}
</script>

<template>
  <div class="flex flex-col gap-4">
    <div class="flex flex-col items-center gap-2">
      <Avatar
        :name="modelValue.name"
        :src="photoUrl"
        :size="80"
        hide-offline-status
      />
      <label
        v-if="canEdit"
        class="cursor-pointer text-sm text-n-blue-11 hover:underline"
      >
        {{ $t('WHATSMEOW_UI.GROUP_PHOTO') }}
        <input type="file" accept="image/*" class="hidden" @change="upload" />
      </label>
      <Button
        v-if="canEdit && photoUrl"
        ghost
        slate
        xs
        :label="$t('WHATSMEOW_UI.REMOVE_PHOTO')"
        @click="update('photo', '')"
      />
    </div>
    <Input
      :model-value="modelValue.name"
      :disabled="!canEdit"
      :label="$t('WHATSMEOW_UI.GROUP_NAME')"
      :maxlength="100"
      @update:model-value="update('name', $event)"
    />
    <label class="flex flex-col gap-1 text-sm">
      {{ $t('WHATSMEOW_UI.DESCRIPTION') }}
      <textarea
        :value="modelValue.topic"
        :disabled="!canEdit"
        maxlength="2048"
        rows="3"
        class="reset-base rounded-lg bg-n-surface-1 border border-n-weak p-3"
        @input="update('topic', $event.target.value)"
      />
    </label>
    <label class="flex flex-col gap-1 text-sm">
      {{ $t('WHATSMEOW_UI.DISAPPEARING_MESSAGES') }}
      <select
        :value="modelValue.disappearing_timer"
        :disabled="!canEdit"
        class="reset-base rounded-lg bg-n-surface-1 border border-n-weak p-2"
        @change="update('disappearing_timer', Number($event.target.value))"
      >
        <option
          v-for="duration in [0, 86400, 604800, 7776000]"
          :key="duration"
          :value="duration"
        >
          {{ $t(`WHATSMEOW_UI.DURATION_${duration}`) }}
        </option>
      </select>
    </label>
    <details open class="rounded-lg border border-n-weak p-3">
      <summary class="cursor-pointer text-sm font-semibold">
        {{ $t('WHATSMEOW_UI.GROUP_PERMISSIONS') }}
      </summary>
      <div class="flex flex-col gap-4 pt-4">
        <label
          v-for="permission in permissions"
          :key="permission"
          class="flex gap-3 items-start text-sm"
        >
          <input
            :checked="modelValue[permission]"
            :disabled="!canManage"
            type="checkbox"
            class="reset-base mt-1 size-4 rounded accent-n-brand"
            @change="update(permission, $event.target.checked)"
          />
          <span>
            {{ $t(`WHATSMEOW_UI.${permission.toUpperCase()}`) }}
            <span class="block text-xs text-n-slate-11 mt-1">
              {{ $t(`WHATSMEOW_UI.${permission.toUpperCase()}_HELP`) }}
            </span>
          </span>
        </label>
      </div>
    </details>
  </div>
</template>
