<script setup>
import { computed, nextTick, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import DropdownContainer from 'dashboard/components-next/dropdown-menu/base/DropdownContainer.vue';
import DropdownBody from 'dashboard/components-next/dropdown-menu/base/DropdownBody.vue';
import DropdownItem from 'dashboard/components-next/dropdown-menu/base/DropdownItem.vue';
import { provideDropdownTeleport } from 'dashboard/components-next/dropdown-menu/base/provider';

const props = defineProps({
  modelValue: { type: [String, Number], default: '' },
  options: { type: Array, required: true },
  label: { type: String, required: true },
  placeholder: { type: String, default: '' },
  disabled: { type: Boolean, default: false },
  searchable: { type: Boolean, default: false },
  teleport: { type: Boolean, default: true },
});
const emit = defineEmits(['update:modelValue']);
const { t } = useI18n();
const container = ref(null);
const trigger = ref(null);
const searchInput = ref(null);
const menu = ref(null);
const search = ref('');
if (props.teleport) provideDropdownTeleport();
const selected = computed(() =>
  props.options.find(item => item.value === props.modelValue)
);
const filtered = computed(() =>
  props.options.filter(item =>
    `${item.label} ${item.description || ''}`
      .toLowerCase()
      .includes(search.value.toLowerCase())
  )
);
const choose = option => {
  if (!option.disabled) {
    emit('update:modelValue', option.value);
    nextTick(() => trigger.value?.$el.focus());
  }
};
const focusMenu = async () => {
  search.value = '';
  await nextTick();
  if (props.searchable) searchInput.value?.focus();
  else menu.value?.querySelector('[role="option"]:not(:disabled)')?.focus();
};
const openWithKeyboard = async event => {
  if (props.disabled) return;
  event.preventDefault();
  container.value.open();
  await focusMenu();
};
const menuKeys = event => {
  if (event.key === 'Escape') {
    event.preventDefault();
    container.value.close();
    trigger.value?.$el.focus();
    return;
  }
  if (!['ArrowDown', 'ArrowUp', 'Enter'].includes(event.key)) return;
  const buttons = [
    ...menu.value.querySelectorAll('[role="option"]:not(:disabled)'),
  ];
  const current = buttons.indexOf(document.activeElement);
  if (event.key === 'Enter' && current === -1 && buttons.length) {
    event.preventDefault();
    buttons[0].click();
  } else if (event.key !== 'Enter' && buttons.length) {
    event.preventDefault();
    const step = event.key === 'ArrowDown' ? 1 : -1;
    buttons[(current + step + buttons.length) % buttons.length].focus();
  }
};
</script>

<template>
  <DropdownContainer ref="container" class="w-full min-w-0">
    <template #trigger="{ toggle, isOpen }">
      <Button
        ref="trigger"
        type="button"
        variant="outline"
        color="slate"
        :label="selected?.label || placeholder || t('COMBOBOX.PLACEHOLDER')"
        :icon="isOpen ? 'i-lucide-chevron-up' : 'i-lucide-chevron-down'"
        trailing-icon
        :disabled="disabled"
        :aria-label="label"
        :aria-expanded="isOpen"
        aria-haspopup="listbox"
        class="!h-10 w-full min-w-0 !justify-between !px-3 !font-normal [&>span]:truncate"
        @click="
          toggle();
          focusMenu();
        "
        @keydown.down="openWithKeyboard"
        @keydown.up="openWithKeyboard"
      />
    </template>
    <div ref="menu" class="relative z-50" @keydown="menuKeys">
      <DropdownBody
        class="!static w-80 max-w-[calc(100vw-2rem)] [&>ul]:gap-0.5"
      >
        <li v-if="searchable" class="mb-1 border-b border-n-weak pb-2">
          <label class="relative block">
            <span
              class="i-lucide-search absolute start-2.5 top-2.5 size-4 text-n-slate-11"
            />
            <input
              ref="searchInput"
              v-model="search"
              type="search"
              :aria-label="t('COMBOBOX.SEARCH_PLACEHOLDER')"
              :placeholder="t('COMBOBOX.SEARCH_PLACEHOLDER')"
              class="reset-base !mb-0 h-9 w-full rounded-lg border-0 bg-n-alpha-1 !ps-9 !pe-3 text-sm text-n-slate-12"
            />
          </label>
        </li>
        <li class="max-h-64 overflow-y-auto" role="listbox" :aria-label="label">
          <ul class="m-0 list-none space-y-0.5 p-0">
            <DropdownItem
              v-for="option in filtered"
              :key="option.value"
              :click="() => choose(option)"
              type="button"
              role="option"
              :aria-selected="option.value === modelValue"
              :disabled="option.disabled"
              class="!gap-3 rounded-lg hover:bg-n-alpha-2 disabled:opacity-50"
              :class="{ 'bg-n-alpha-2': option.value === modelValue }"
            >
              <span
                v-if="option.icon"
                :class="option.icon"
                class="size-4 shrink-0 text-n-slate-11"
              />
              <span class="min-w-0 flex-1">
                <span class="block truncate">{{ option.label }}</span>
                <span
                  v-if="option.description"
                  class="mt-0.5 block truncate text-xs text-n-slate-11"
                  >{{ option.description }}</span
                >
              </span>
              <span
                v-if="option.value === modelValue"
                class="i-lucide-check size-4 shrink-0 text-n-blue-11"
              />
            </DropdownItem>
            <li
              v-if="!filtered.length"
              class="px-3 py-4 text-sm text-n-slate-11"
            >
              {{ t('COMBOBOX.EMPTY_STATE') }}
            </li>
          </ul>
        </li>
      </DropdownBody>
    </div>
  </DropdownContainer>
</template>
