<script setup>
import Avatar from 'next/avatar/Avatar.vue';
import Button from 'next/button/Button.vue';

defineProps({
  member: { type: Object, required: true },
  canManage: { type: Boolean, default: false },
  selected: { type: Boolean, default: false },
});
const emit = defineEmits(['action', 'select']);
</script>

<template>
  <div
    class="flex items-center rounded-lg hover:bg-n-alpha-2 focus-within:bg-n-alpha-2"
  >
    <button
      type="button"
      class="reset-base flex min-w-0 flex-1 items-center gap-2 rounded-lg border-0 bg-transparent px-2 py-2 text-left text-n-slate-12 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-9"
      :class="{ '[anchor-name:--group-member]': selected }"
      aria-haspopup="menu"
      :aria-expanded="selected"
      @click="emit('select', member)"
    >
      <Avatar
        :name="member.name || member.phone_number"
        :src="member.profile_picture_url"
        :size="36"
        hide-offline-status
      />
      <div class="flex-1 min-w-0">
        <p class="m-0 truncate text-sm">
          {{
            member.is_self
              ? $t('WHATSMEOW_UI.YOU')
              : member.name || member.phone_number
          }}
        </p>
        <p
          v-if="member.name !== member.phone_number"
          class="m-0 text-xs text-n-slate-10 truncate"
        >
          {{ member.phone_number }}
        </p>
      </div>
      <span
        v-if="member.is_admin || member.is_super_admin"
        class="text-xxs rounded px-1.5 py-1 bg-n-teal-3 text-n-teal-11"
      >
        {{
          $t(
            member.is_super_admin ? 'WHATSMEOW_UI.OWNER' : 'WHATSMEOW_UI.ADMIN'
          )
        }}
      </span>
    </button>
    <details
      v-if="canManage && !member.is_self && !member.is_super_admin"
      class="relative"
    >
      <summary class="cursor-pointer list-none p-2">
        <span class="i-lucide-more-vertical size-4" />
      </summary>
      <div
        class="absolute right-0 z-20 w-44 bg-n-solid-2 rounded-lg border border-n-weak p-1 shadow-lg"
      >
        <Button
          type="button"
          :label="
            $t(member.is_admin ? 'WHATSMEOW_UI.DEMOTE' : 'WHATSMEOW_UI.PROMOTE')
          "
          ghost
          slate
          class="w-full justify-start"
          @click="
            emit('action', member.is_admin ? 'demote' : 'promote', member)
          "
        />
        <Button
          type="button"
          :label="$t('WHATSMEOW_UI.REMOVE')"
          ghost
          ruby
          class="w-full justify-start"
          @click="emit('action', 'remove', member)"
        />
      </div>
    </details>
  </div>
</template>
