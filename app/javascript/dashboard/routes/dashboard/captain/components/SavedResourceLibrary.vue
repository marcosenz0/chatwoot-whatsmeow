<script setup>
import { computed, nextTick, ref, useId, watch } from 'vue';
import { useDebounceFn } from '@vueuse/core';
import { useI18n } from 'vue-i18n';
import API from 'dashboard/api/marcosxAi';
import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import ContextMenu from 'dashboard/components/ui/ContextMenu.vue';
import DropdownBody from 'dashboard/components-next/dropdown-menu/base/DropdownBody.vue';
import AudienceBadge from './AudienceBadge.vue';
import ResourceVideoPlayer from './ResourceVideoPlayer.vue';
import { audiencePayload, defaultAudience } from './audience';

const props = defineProps({
  agentId: { type: Number, required: true },
  conversationId: { type: Number, default: null },
  disabled: { type: Boolean, default: false },
});
const emit = defineEmits(['updated']);
const { t } = useI18n();
const libraryId = `resource-library-${useId()}`;
const items = ref([]);
const total = ref(0);
const page = ref(1);
const pageSize = ref(24);
const search = ref('');
const busy = ref(false);
const saving = ref(false);
const error = ref('');
const preview = ref(null);
const selected = ref(null);
const menu = ref(null);
const menuSurface = ref(null);
let menuTrigger = null;
let generation = 0;
const icons = {
  image: 'i-lucide-image',
  video: 'i-lucide-video',
  file: 'i-lucide-file-text',
  link: 'i-lucide-link',
};
const load = async () => {
  generation += 1;
  const current = generation;
  busy.value = true;
  try {
    const { data } = await API.getResources(props.agentId, {
      search: search.value,
      page: page.value,
    });
    if (current !== generation) return;
    items.value = data.resources;
    total.value = data.total;
    pageSize.value = data.per_page;
    error.value = '';
  } catch (failure) {
    if (current === generation)
      error.value =
        failure.response?.data?.error || t('MARCOX_AI.RESOURCES.ERROR');
  } finally {
    if (current === generation) busy.value = false;
  }
};
watch(
  () => props.agentId,
  () => {
    items.value = [];
    page.value = 1;
    load();
  },
  { immediate: true }
);
watch(page, load);
watch(
  search,
  useDebounceFn(() => {
    if (page.value === 1) load();
    else page.value = 1;
  }, 250)
);
const showPreview = item => {
  selected.value = item;
  preview.value.open();
};
const closeMenu = () => {
  menu.value = null;
  nextTick(() => menuTrigger?.focus());
};
const openMenu = async (event, item) => {
  if (saving.value || props.disabled) return;
  menuTrigger = event.currentTarget;
  const bounds = menuTrigger.getBoundingClientRect();
  menu.value = {
    item,
    x:
      event.type === 'contextmenu' && event.clientX
        ? event.clientX
        : bounds.left,
    y:
      event.type === 'contextmenu' && event.clientY
        ? event.clientY
        : bounds.bottom,
  };
  await nextTick();
  menuSurface.value?.focus();
};
const menuOptions = computed(() => [
  {
    value: 'global',
    label: t('MARCOX_AI.AUDIENCE.GLOBAL'),
    icon: 'i-lucide-globe',
  },
  ...(props.conversationId
    ? [
        {
          value: 'conversation',
          label: t('MARCOX_AI.AUDIENCE.CONVERSATION', {
            id: props.conversationId,
          }),
          icon: 'i-lucide-message-circle',
        },
      ]
    : []),
]);
const isCurrentScope = option =>
  (menu.value?.item.audience === option &&
    (option !== 'conversation' ||
      menu.value.item.conversation_id === props.conversationId)) ||
  (option === 'global' && !menu.value?.item.audience);
const changeAudience = async audience => {
  const { item } = menu.value;
  closeMenu();
  saving.value = true;
  error.value = '';
  try {
    const { data } = await API.saveResource(props.agentId, item.id, {
      resource: audiencePayload(
        defaultAudience(audience === 'global', props.conversationId)
      ),
    });
    items.value = items.value.map(entry =>
      entry.id === item.id ? data.resource : entry
    );
    emit('updated');
  } catch (failure) {
    error.value =
      failure.response?.data?.error || t('MARCOX_AI.RESOURCES.ERROR');
  } finally {
    saving.value = false;
  }
};
const menuKeys = event => {
  if (event.key === 'Escape') {
    event.preventDefault();
    event.stopPropagation();
    closeMenu();
  } else if (['ArrowDown', 'ArrowUp', 'Home', 'End'].includes(event.key)) {
    event.preventDefault();
    const buttons = [...menuSurface.value.querySelectorAll('button')];
    const index = buttons.indexOf(document.activeElement);
    let target =
      (index + (event.key === 'ArrowUp' ? -1 : 1) + buttons.length) %
      buttons.length;
    if (event.key === 'Home') target = 0;
    if (event.key === 'End') target = buttons.length - 1;
    buttons[target]?.focus();
  }
};
</script>

<template>
  <section
    :id="libraryId"
    class="space-y-3 border-b border-n-weak pb-5"
    :aria-label="t('MARCOX_AI.RESOURCES.YOUR_FILES')"
  >
    <div class="flex items-center justify-between gap-3">
      <h4 class="m-0 text-sm font-semibold text-n-slate-12">
        {{ t('MARCOX_AI.RESOURCES.YOUR_FILES') }}
      </h4>
      <span class="text-xs text-n-slate-11">{{
        t('MARCOX_AI.RESOURCES.COUNT', { count: total })
      }}</span>
    </div>
    <p class="m-0 text-xs leading-5 text-n-slate-11">
      {{ t('MARCOX_AI.RESOURCES.LIBRARY_HINT') }}
    </p>
    <input
      v-model="search"
      type="search"
      :aria-label="t('MARCOX_AI.RESOURCES.LIBRARY_SEARCH')"
      :placeholder="t('MARCOX_AI.RESOURCES.LIBRARY_SEARCH')"
      class="reset-base h-9 w-full rounded-lg border border-n-weak bg-n-background px-3 text-sm"
    />
    <p v-if="error" role="alert" class="m-0 text-sm text-n-ruby-11">
      {{ error }}
    </p>
    <p v-if="busy" role="status" class="m-0 text-xs text-n-slate-11">
      {{ t('MARCOX_AI.RESOURCES.LOADING') }}
    </p>
    <div v-else-if="items.length" class="grid grid-cols-4 gap-2 sm:grid-cols-6">
      <button
        v-for="item in items"
        :key="item.id"
        type="button"
        :title="item.title"
        :aria-label="
          t('MARCOX_AI.RESOURCES.PREVIEW_ITEM', { name: item.title })
        "
        :disabled="disabled"
        class="reset-base group relative aspect-square min-w-0 overflow-hidden rounded-lg border border-n-weak bg-n-solid-2 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-blue-9 hover:border-n-blue-9"
        data-testid="saved-resource"
        @click="showPreview(item)"
        @contextmenu.prevent.stop="openMenu($event, item)"
        @keydown.shift.f10.prevent.stop="openMenu($event, item)"
        @keydown.context-menu.prevent.stop="openMenu($event, item)"
      >
        <img
          v-if="item.thumb_url || item.kind === 'image'"
          :src="item.thumb_url || item.file_url"
          :alt="item.title"
          loading="lazy"
          class="pointer-events-none h-full w-full object-cover"
        />
        <video
          v-else-if="item.kind === 'video'"
          :src="`${item.file_url}#t=0.001`"
          :aria-label="item.title"
          preload="metadata"
          muted
          playsinline
          class="pointer-events-none h-full w-full object-cover"
        />
        <span
          v-else
          :class="icons[item.kind]"
          class="absolute start-1/2 top-1/2 size-7 -translate-x-1/2 -translate-y-1/2 text-n-slate-10"
        />
        <span
          v-if="item.kind === 'video'"
          class="i-lucide-play absolute start-2 top-2 size-4 text-white drop-shadow"
        />
        <span
          v-if="!item.enabled"
          :title="t('MARCOX_AI.RESOURCES.DISABLED')"
          class="i-lucide-circle-slash absolute start-1 top-1 size-4 text-n-ruby-11"
        />
        <AudienceBadge :item="item" icon-only class="absolute bottom-1 end-1" />
      </button>
    </div>
    <p v-else class="m-0 text-xs text-n-slate-11">
      {{ t('MARCOX_AI.RESOURCES.EMPTY') }}
    </p>
    <div
      v-if="total > pageSize"
      class="flex items-center justify-end gap-2 text-xs text-n-slate-11"
    >
      <Button
        type="button"
        variant="ghost"
        size="sm"
        icon="i-lucide-chevron-left"
        :aria-label="t('MARCOX_AI.WORKSPACE.PREVIOUS')"
        :disabled="busy || page === 1"
        @click="page -= 1"
      />
      <span>{{ page }} / {{ Math.ceil(total / pageSize) }}</span>
      <Button
        type="button"
        variant="ghost"
        size="sm"
        icon="i-lucide-chevron-right"
        :aria-label="t('MARCOX_AI.WORKSPACE.NEXT')"
        :disabled="busy || page >= Math.ceil(total / pageSize)"
        @click="page += 1"
      />
    </div>
    <ContextMenu
      v-if="menu"
      :x="menu.x"
      :y="menu.y"
      :teleport-to="`#${libraryId}`"
      top-layer
      @close="closeMenu"
    >
      <div
        ref="menuSurface"
        role="menu"
        tabindex="-1"
        :aria-label="t('MARCOX_AI.AUDIENCE.TITLE')"
        class="w-72 max-w-[calc(100vw-2rem)] outline-none"
        @keydown="menuKeys"
      >
        <DropdownBody class="!static">
          <li
            v-for="option in menuOptions"
            :key="option.value"
            class="list-none"
          >
            <button
              type="button"
              role="menuitemradio"
              :aria-checked="isCurrentScope(option.value)"
              class="reset-base flex w-full items-center gap-2 rounded-lg border-0 p-2 text-start text-sm text-n-slate-12 hover:bg-n-blue-9 hover:text-white focus-visible:bg-n-blue-9 focus-visible:text-white focus-visible:outline-none"
              @click.stop="changeAudience(option.value)"
            >
              <span :class="option.icon" class="size-4 shrink-0" />
              <span class="min-w-0 flex-1">{{ option.label }}</span>
              <span
                v-if="isCurrentScope(option.value)"
                class="i-lucide-check size-4 shrink-0"
              />
            </button>
          </li>
        </DropdownBody>
      </div>
    </ContextMenu>
    <Dialog
      ref="preview"
      width="3xl"
      :title="selected?.title || ''"
      :show-confirm-button="false"
      :cancel-button-label="t('MARCOX_AI.ANALYSIS.CLOSE')"
      @close="selected = null"
    >
      <div v-if="selected" class="max-h-[60vh] space-y-3 overflow-y-auto">
        <img
          v-if="selected.kind === 'image'"
          :src="selected.file_url"
          :alt="selected.title"
          class="max-h-[55vh] w-full rounded-lg object-contain"
        />
        <ResourceVideoPlayer
          v-else-if="selected.kind === 'video'"
          :src="selected.file_url"
          :name="selected.title"
        />
        <div
          v-else
          class="flex flex-col items-center gap-3 rounded-lg bg-n-solid-2 p-6"
        >
          <span :class="icons[selected.kind]" class="size-9 text-n-blue-11" />
          <p class="m-0 break-all text-sm text-n-slate-11">
            {{ selected.file_name || selected.url }}
          </p>
        </div>
        <a
          :href="selected.kind === 'link' ? selected.url : selected.file_url"
          target="_blank"
          rel="noopener noreferrer"
          class="inline-flex items-center gap-1.5 text-sm text-n-blue-11"
        >
          <span class="i-lucide-external-link size-4" />
          {{ t('MARCOX_AI.RESOURCES.OPEN') }}
        </a>
      </div>
    </Dialog>
  </section>
</template>
