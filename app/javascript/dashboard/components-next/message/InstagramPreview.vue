<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import MessageAPI from 'dashboard/api/inbox/message';
import { getInstagramPreviewUrl } from 'dashboard/helper/instagramMediaHelper';
import Icon from 'next/icon/Icon.vue';

const props = defineProps({
  url: { type: String, required: true },
  conversationId: { type: Number, required: true },
  messageId: { type: Number, required: true },
  expanded: { type: Boolean, default: false },
});
const emit = defineEmits(['expand']);
const { t } = useI18n();
const target = computed(() => getInstagramPreviewUrl(props.url));
const preview = ref({});
const loading = ref(true);
const mediaError = ref(false);
const platformPlayer = ref(false);
const selectedPost = ref(null);
const imageUrl = computed(
  () => selectedPost.value?.image_url || preview.value.image_url
);

watch(
  () => [props.url, props.conversationId, props.messageId],
  async (_, __, onCleanup) => {
    let active = true;
    onCleanup(() => {
      active = false;
    });
    preview.value = {};
    loading.value = true;
    mediaError.value = false;
    platformPlayer.value = false;
    selectedPost.value = null;
    try {
      const { data } = await MessageAPI.instagramPreview(
        props.conversationId,
        props.messageId,
        target.value.permalink
      );
      if (active) preview.value = data;
    } catch {
      // Keep the original link usable even when public metadata cannot be fetched.
    } finally {
      if (active) loading.value = false;
    }
  },
  { immediate: true }
);

const expand = () => emit('expand');
const selectPost = post => {
  selectedPost.value = post;
  if (!props.expanded) emit('expand', post);
};
</script>

<template>
  <section
    class="flex min-h-36 w-full flex-col overflow-hidden rounded-lg bg-n-background text-n-slate-12"
    :class="
      expanded ? 'max-h-full max-w-3xl overflow-y-auto' : 'w-80 max-w-full'
    "
    data-instagram-preview
  >
    <div class="flex shrink-0 items-center gap-3 border-b border-n-weak p-3">
      <img
        v-if="preview.avatar_url"
        :src="preview.avatar_url"
        alt=""
        class="size-10 shrink-0 rounded-full object-cover"
        referrerpolicy="no-referrer"
      />
      <Icon
        v-else
        icon="i-lucide-instagram"
        class="size-8 shrink-0 text-n-slate-11"
      />
      <div class="min-w-0 flex-1">
        <p class="m-0 truncate text-sm font-semibold">
          {{
            preview.username || target.username || t('INSTAGRAM_PREVIEW.MEDIA')
          }}
        </p>
        <p v-if="preview.title" class="m-0 truncate text-xs text-n-slate-11">
          {{ preview.title }}
        </p>
      </div>
      <button
        v-if="!expanded"
        type="button"
        :aria-label="t('GALLERY_VIEW.EXPAND')"
        class="grid size-8 shrink-0 place-content-center rounded-lg hover:bg-n-alpha-2"
        @click.stop="expand"
      >
        <Icon icon="i-lucide-expand" />
      </button>
    </div>
    <p v-if="loading" role="status" class="m-0 p-4 text-sm text-n-slate-11">
      {{ t('INSTAGRAM_PREVIEW.LOADING') }}
    </p>
    <template v-else>
      <video
        v-if="preview.video_url && !mediaError"
        :src="preview.video_url"
        :poster="preview.image_url"
        controls
        playsinline
        preload="metadata"
        class="max-h-[65dvh] w-full bg-black object-contain"
        @click.stop
        @error="mediaError = true"
      />
      <button
        v-else-if="imageUrl && !expanded"
        type="button"
        class="relative w-full overflow-hidden bg-black"
        :aria-label="t('GALLERY_VIEW.EXPAND')"
        @click.stop="expand"
      >
        <img
          :src="imageUrl"
          alt=""
          class="max-h-96 w-full object-contain"
          referrerpolicy="no-referrer"
        />
        <span
          class="absolute bottom-3 right-3 rounded-lg bg-black/70 px-3 py-2 text-xs text-white"
        >
          {{ t('GALLERY_VIEW.EXPAND') }}
        </span>
      </button>
      <img
        v-else-if="imageUrl"
        :src="imageUrl"
        alt=""
        class="max-h-[65dvh] w-full object-contain"
        referrerpolicy="no-referrer"
      />
      <p
        v-if="preview.bio || preview.description"
        class="m-0 whitespace-pre-line p-3 text-sm"
        :class="{ 'line-clamp-3': !expanded }"
      >
        {{ preview.bio || preview.description }}
      </p>
      <div v-if="preview.posts?.length" class="grid grid-cols-3 gap-0.5">
        <button
          v-for="post in preview.posts"
          :key="post.url"
          type="button"
          :aria-label="t('GALLERY_VIEW.EXPAND')"
          @click.stop="selectPost(post)"
        >
          <img
            :src="post.image_url"
            alt=""
            class="aspect-square w-full object-cover"
            referrerpolicy="no-referrer"
          />
        </button>
      </div>
      <p
        v-if="target.kind === 'media' && (!preview.video_url || mediaError)"
        class="m-0 p-3 text-xs leading-5 text-n-slate-11"
      >
        {{ t('INSTAGRAM_PREVIEW.VIDEO_LIMIT') }}
      </p>
      <p
        v-if="target.kind === 'profile' && preview.status !== 'available'"
        class="m-0 p-3 text-xs leading-5 text-n-slate-11"
      >
        {{ t('INSTAGRAM_PREVIEW.PROFILE_LIMIT') }}
      </p>
      <template
        v-if="
          expanded &&
          target.kind === 'media' &&
          (!preview.video_url || mediaError)
        "
      >
        <button
          type="button"
          class="m-3 rounded-lg border border-n-weak px-3 py-2 text-sm hover:bg-n-alpha-2"
          :aria-expanded="platformPlayer"
          @click.stop="platformPlayer = !platformPlayer"
        >
          {{ t('INSTAGRAM_PREVIEW.PLATFORM_PLAYER') }}
        </button>
        <iframe
          v-if="platformPlayer"
          :src="target.embedUrl"
          :title="t('GALLERY_VIEW.INSTAGRAM_PREVIEW')"
          class="h-[70dvh] w-full shrink-0 border-0"
          scrolling="no"
          allow="autoplay; encrypted-media; picture-in-picture; fullscreen"
          allowfullscreen
        />
      </template>
    </template>
    <a
      :href="selectedPost?.url || target.permalink"
      target="_blank"
      rel="noopener noreferrer"
      class="block border-t border-n-weak p-3 text-xs text-n-blue-text"
    >
      {{ t('GALLERY_VIEW.OPEN_INSTAGRAM') }}
    </a>
  </section>
</template>
