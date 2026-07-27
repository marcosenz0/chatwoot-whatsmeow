<script setup>
import { computed, onBeforeUnmount, reactive, ref, toRaw, watch } from 'vue';
import { useI18n } from 'vue-i18n';

import Button from 'dashboard/components-next/button/Button.vue';
import TeleportWithDirection from 'dashboard/components-next/TeleportWithDirection.vue';
import StudioSelect from './StudioSelect.vue';
import StudioTemplateParameterFields from './StudioTemplateParameterFields.vue';
import {
  hydrateStudioTemplateParameters,
  isStudioTemplateSupported,
  templateParametersComplete,
  templateQuickReplies,
} from './templateParameterUtils';

const props = defineProps({
  flow: { type: Object, required: true },
  templates: { type: Array, default: () => [] },
  isSaving: { type: Boolean, default: false },
  isPublishing: { type: Boolean, default: false },
});

const emit = defineEmits(['close', 'save', 'publish']);
const { t } = useI18n();

const cloneFlow = flow => JSON.parse(JSON.stringify(toRaw(flow)));
const draft = reactive(cloneFlow(props.flow));
const selectedNodeId = ref(
  draft.definition.nodes.find(node => node.type === 'trigger')?.id || null
);
const pendingConnection = ref(null);
const dragging = ref(null);
const svgRef = ref(null);

const nodeTypes = [
  { type: 'message', icon: 'i-lucide-message-square-text' },
  { type: 'wait', icon: 'i-lucide-timer' },
  { type: 'condition', icon: 'i-lucide-git-branch' },
  { type: 'action', icon: 'i-lucide-zap' },
  { type: 'end', icon: 'i-lucide-circle-stop' },
];

const selectedNode = computed(() =>
  draft.definition.nodes.find(node => node.id === selectedNodeId.value)
);

const approvedTemplates = computed(() =>
  props.templates.filter(
    template => template.status?.toLowerCase() === 'approved'
  )
);

const configuredTemplate = computed(() =>
  approvedTemplates.value.find(
    template =>
      template.name === selectedNode.value?.config?.template_name &&
      template.language === selectedNode.value?.config?.language
  )
);

const selectedTemplate = computed(() =>
  isStudioTemplateSupported(configuredTemplate.value)
    ? configuredTemplate.value
    : null
);

const selectedTemplateKey = computed(() => {
  if (!selectedNode.value?.config?.template_name) return '';
  return `${selectedNode.value.config.template_name}|${selectedNode.value.config.language}`;
});

const selectedTemplateUnsupported = computed(
  () =>
    selectedNode.value?.config?.mode === 'template' &&
    selectedNode.value?.config?.template_name &&
    !isStudioTemplateSupported(configuredTemplate.value)
);

watch(
  [selectedNode, selectedTemplate],
  ([node, template]) => {
    if (!node || node.config?.mode !== 'template' || !template) return;
    node.config.processed_params = hydrateStudioTemplateParameters(
      template,
      node.config.processed_params,
      { quickReplies: node.config.buttons || [] }
    );
  },
  { immediate: true }
);

const flowHasUnsupportedTemplates = computed(() =>
  draft.definition.nodes.some(node => {
    if (node.type !== 'message' || node.config?.mode !== 'template') {
      return false;
    }
    const template = approvedTemplates.value.find(
      record =>
        record.name === node.config.template_name &&
        record.language === node.config.language
    );
    return node.config.template_name && !isStudioTemplateSupported(template);
  })
);

const templateParametersForNode = (node, template) =>
  hydrateStudioTemplateParameters(template, node.config?.processed_params, {
    quickReplies: node.config?.buttons || [],
  });

const flowHasIncompleteTemplateParameters = computed(() =>
  draft.definition.nodes.some(node => {
    if (node.type !== 'message' || node.config?.mode !== 'template') {
      return false;
    }
    const template = approvedTemplates.value.find(
      record =>
        record.name === node.config.template_name &&
        record.language === node.config.language
    );
    return (
      isStudioTemplateSupported(template) &&
      !templateParametersComplete(templateParametersForNode(node, template))
    );
  })
);

const selectedTemplateParametersIncomplete = computed(
  () =>
    selectedNode.value?.config?.mode === 'template' &&
    selectedTemplate.value &&
    !templateParametersComplete(
      templateParametersForNode(selectedNode.value, selectedTemplate.value)
    )
);

watch(
  () => props.flow,
  flow => {
    const clonedFlow = cloneFlow(flow);
    Object.assign(draft, clonedFlow);
    selectedNodeId.value =
      clonedFlow.definition.nodes.find(node => node.type === 'trigger')?.id ||
      null;
  }
);

const nodeHeight = node => {
  if (node.type === 'message') {
    return Math.max(150, 122 + (node.config?.buttons?.length || 0) * 30);
  }
  return 126;
};

const nodeTypeLabel = type => {
  const labels = {
    trigger: t('WHATSAPP_CLOUD_STUDIO.FLOWS.NODE_TYPES.TRIGGER'),
    message: t('WHATSAPP_CLOUD_STUDIO.FLOWS.NODE_TYPES.MESSAGE'),
    wait: t('WHATSAPP_CLOUD_STUDIO.FLOWS.NODE_TYPES.WAIT'),
    condition: t('WHATSAPP_CLOUD_STUDIO.FLOWS.NODE_TYPES.CONDITION'),
    action: t('WHATSAPP_CLOUD_STUDIO.FLOWS.NODE_TYPES.ACTION'),
    end: t('WHATSAPP_CLOUD_STUDIO.FLOWS.NODE_TYPES.END'),
  };
  return labels[type];
};

const flowStatusLabel = status => {
  const labels = {
    draft: t('WHATSAPP_CLOUD_STUDIO.FLOWS.STATUS.DRAFT'),
    active: t('WHATSAPP_CLOUD_STUDIO.FLOWS.STATUS.ACTIVE'),
    paused: t('WHATSAPP_CLOUD_STUDIO.FLOWS.STATUS.PAUSED'),
  };
  return labels[status];
};

const actionLabel = action => {
  const labels = {
    add_label: t('WHATSAPP_CLOUD_STUDIO.FLOWS.ACTIONS.ADD_LABEL'),
    remove_label: t('WHATSAPP_CLOUD_STUDIO.FLOWS.ACTIONS.REMOVE_LABEL'),
    open_conversation: t(
      'WHATSAPP_CLOUD_STUDIO.FLOWS.ACTIONS.OPEN_CONVERSATION'
    ),
    resolve_conversation: t(
      'WHATSAPP_CLOUD_STUDIO.FLOWS.ACTIONS.RESOLVE_CONVERSATION'
    ),
  };
  return labels[action];
};

const conditionHandleLabel = handle =>
  handle === 'true'
    ? t('WHATSAPP_CLOUD_STUDIO.FLOWS.EDITOR.TRUE_HANDLE')
    : t('WHATSAPP_CLOUD_STUDIO.FLOWS.EDITOR.FALSE_HANDLE');

const templateOptionLabel = template =>
  `${template.name} - ${template.language}`;

const selectableTemplateLabel = template => {
  const label = templateOptionLabel(template);
  return isStudioTemplateSupported(template)
    ? label
    : `${label} - ${t(
        'WHATSAPP_CLOUD_STUDIO.TEMPLATE_PARAMETERS.UNSUPPORTED_OPTION'
      )}`;
};

const nodeTitle = node => nodeTypeLabel(node.type);

const nodeSubtitle = node => {
  if (node.type === 'trigger') {
    return draft.trigger_type === 'keyword'
      ? draft.trigger_config.keywords?.join(', ')
      : t('WHATSAPP_CLOUD_STUDIO.FLOWS.EDITOR.ANY_MESSAGE');
  }
  if (node.type === 'message') {
    return node.config.mode === 'template'
      ? node.config.template_name ||
          t('WHATSAPP_CLOUD_STUDIO.FLOWS.EDITOR.SELECT_TEMPLATE')
      : node.config.text ||
          t('WHATSAPP_CLOUD_STUDIO.FLOWS.EDITOR.EMPTY_MESSAGE');
  }
  if (node.type === 'wait') {
    return t('WHATSAPP_CLOUD_STUDIO.FLOWS.EDITOR.WAIT_MINUTES', {
      count: node.config.duration || 1,
    });
  }
  if (node.type === 'condition') {
    return node.config.field
      ? `${node.config.field} - ${node.config.operator}`
      : t('WHATSAPP_CLOUD_STUDIO.FLOWS.EDITOR.CONFIGURE_CONDITION');
  }
  if (node.type === 'action') {
    return node.config.action
      ? actionLabel(node.config.action)
      : t('WHATSAPP_CLOUD_STUDIO.FLOWS.EDITOR.CONFIGURE_ACTION');
  }
  return t('WHATSAPP_CLOUD_STUDIO.FLOWS.EDITOR.END_DESCRIPTION');
};

const nodeIcon = node => {
  if (node.type === 'trigger') return 'i-lucide-play';
  return nodeTypes.find(item => item.type === node.type)?.icon;
};

const nodeTone = node => {
  const tones = {
    trigger: 'bg-n-teal-3 text-n-teal-11',
    message: 'bg-n-blue-3 text-n-blue-11',
    wait: 'bg-n-amber-3 text-n-amber-11',
    condition: 'bg-n-iris-3 text-n-iris-11',
    action: 'bg-n-ruby-3 text-n-ruby-11',
    end: 'bg-n-slate-3 text-n-slate-11',
  };
  return tones[node.type];
};

const handleY = (node, handle = 'default') => {
  if (handle === 'default') return node.position.y + 58;
  if (handle === 'true') return node.position.y + 82;
  if (handle === 'false') return node.position.y + 108;
  const buttonIndex = node.config?.buttons?.findIndex(
    button => button.id === handle
  );
  return node.position.y + 122 + Math.max(0, buttonIndex) * 30;
};

const edgePath = edge => {
  const source = draft.definition.nodes.find(node => node.id === edge.source);
  const target = draft.definition.nodes.find(node => node.id === edge.target);
  if (!source || !target) return '';
  const sourceX = source.position.x + 260;
  const sourceY = handleY(source, edge.source_handle || 'default');
  const targetX = target.position.x;
  const targetY = target.position.y + 58;
  const controlOffset = Math.max(80, Math.abs(targetX - sourceX) / 2);
  return `M ${sourceX} ${sourceY} C ${sourceX + controlOffset} ${sourceY}, ${targetX - controlOffset} ${targetY}, ${targetX} ${targetY}`;
};

const createId = prefix =>
  `${prefix}_${Date.now()}_${Math.random().toString(36).slice(2, 7)}`;

const defaultConfig = type => {
  if (type === 'message') {
    return { mode: 'session', text: '', buttons: [], processed_params: {} };
  }
  if (type === 'wait') return { duration: 5 };
  if (type === 'condition') {
    return { field: 'last_button_id', operator: 'equals', value: '' };
  }
  if (type === 'action') return { action: 'add_label', value: '' };
  return {};
};

const addNode = type => {
  const count = draft.definition.nodes.length;
  const node = {
    id: createId(type),
    type,
    position: {
      x: 360 + (count % 3) * 300,
      y: 120 + Math.floor(count / 3) * 190,
    },
    config: defaultConfig(type),
  };
  draft.definition.nodes.push(node);
  selectedNodeId.value = node.id;
};

const deleteSelectedNode = () => {
  if (!selectedNode.value || selectedNode.value.type === 'trigger') return;
  const id = selectedNode.value.id;
  draft.definition.nodes = draft.definition.nodes.filter(
    node => node.id !== id
  );
  draft.definition.edges = draft.definition.edges.filter(
    edge => edge.source !== id && edge.target !== id
  );
  selectedNodeId.value =
    draft.definition.nodes.find(node => node.type === 'trigger')?.id || null;
};

const startConnection = (nodeId, sourceHandle = 'default') => {
  pendingConnection.value = { source: nodeId, sourceHandle };
};

const finishConnection = targetId => {
  if (!pendingConnection.value || pendingConnection.value.source === targetId) {
    pendingConnection.value = null;
    return;
  }
  const { source, sourceHandle } = pendingConnection.value;
  draft.definition.edges = draft.definition.edges.filter(
    edge =>
      !(
        edge.source === source &&
        (edge.source_handle || 'default') === sourceHandle
      )
  );
  draft.definition.edges.push({
    id: createId('edge'),
    source,
    target: targetId,
    source_handle: sourceHandle,
  });
  pendingConnection.value = null;
};

const removeOutgoingEdge = (sourceId, sourceHandle = 'default') => {
  draft.definition.edges = draft.definition.edges.filter(
    edge =>
      !(
        edge.source === sourceId &&
        (edge.source_handle || 'default') === sourceHandle
      )
  );
};

const svgPoint = event => {
  const point = svgRef.value.createSVGPoint();
  point.x = event.clientX;
  point.y = event.clientY;
  return point.matrixTransform(svgRef.value.getScreenCTM().inverse());
};

function dragNode(event) {
  if (!dragging.value) return;
  const node = draft.definition.nodes.find(
    item => item.id === dragging.value.nodeId
  );
  const point = svgPoint(event);
  node.position.x = Math.max(
    20,
    Math.min(1300, point.x - dragging.value.offsetX)
  );
  node.position.y = Math.max(
    20,
    Math.min(760, point.y - dragging.value.offsetY)
  );
}

function stopDragging() {
  dragging.value = null;
  window.removeEventListener('pointermove', dragNode);
}

const startDragging = (event, node) => {
  if (event.button !== 0) return;
  const point = svgPoint(event);
  dragging.value = {
    nodeId: node.id,
    offsetX: point.x - node.position.x,
    offsetY: point.y - node.position.y,
  };
  selectedNodeId.value = node.id;
  window.addEventListener('pointermove', dragNode);
  window.addEventListener('pointerup', stopDragging, { once: true });
};

onBeforeUnmount(() => {
  window.removeEventListener('pointermove', dragNode);
});

const updateTemplate = templateKey => {
  const [templateName, language] = templateKey.split('|');
  const template = approvedTemplates.value.find(
    item => item.name === templateName && item.language === language
  );
  if (!selectedNode.value) return;
  const previousButtonIds = (selectedNode.value.config.buttons || []).map(
    button => button.id
  );
  draft.definition.edges = draft.definition.edges.filter(
    edge =>
      edge.source !== selectedNode.value.id ||
      !previousButtonIds.includes(edge.source_handle)
  );

  if (!template || !isStudioTemplateSupported(template)) {
    Object.assign(selectedNode.value.config, {
      template_name: '',
      language: '',
      category: '',
      preview_text: '',
      buttons: [],
      processed_params: {},
    });
    return;
  }
  const body = template.components?.find(
    component => component.type === 'BODY'
  );
  const buttons = templateQuickReplies(template);
  Object.assign(selectedNode.value.config, {
    template_name: template.name,
    language: template.language,
    category: template.category,
    preview_text: body?.text || template.name,
    buttons,
    processed_params: hydrateStudioTemplateParameters(
      template,
      {},
      {
        quickReplies: buttons,
      }
    ),
  });
};

const addReplyButton = () => {
  if (!selectedNode.value || selectedNode.value.config.buttons.length >= 3) {
    return;
  }
  selectedNode.value.config.buttons.push({
    id: createId('reply'),
    title: '',
  });
};

const removeReplyButton = index => {
  const button = selectedNode.value.config.buttons[index];
  removeOutgoingEdge(selectedNode.value.id, button.id);
  selectedNode.value.config.buttons.splice(index, 1);
};

const preparePayload = () => ({
  name: draft.name,
  description: draft.description,
  inbox_id: draft.inbox_id,
  trigger_type: draft.trigger_type,
  trigger_config: draft.trigger_config,
  definition: draft.definition,
});
</script>

<template>
  <TeleportWithDirection to="body">
    <div
      class="fixed inset-0 z-[100] flex flex-col bg-n-surface-1"
      role="dialog"
      aria-modal="true"
      :aria-label="t('WHATSAPP_CLOUD_STUDIO.FLOWS.EDITOR.TITLE')"
    >
      <header
        class="flex min-h-16 flex-wrap items-center justify-between gap-3 border-b border-n-weak px-4 py-3 sm:px-5"
      >
        <div class="flex min-w-0 items-center gap-3">
          <button
            type="button"
            class="flex size-10 shrink-0 items-center justify-center rounded-lg text-n-slate-10 hover:bg-n-alpha-2 hover:text-n-slate-12 disabled:cursor-not-allowed disabled:opacity-50"
            :disabled="isSaving || isPublishing"
            :aria-label="t('WHATSAPP_CLOUD_STUDIO.CLOSE')"
            @click="emit('close')"
          >
            <span class="i-lucide-arrow-left size-5" aria-hidden="true" />
          </button>
          <div class="min-w-0">
            <input
              v-model="draft.name"
              class="reset-base !mb-0 h-8 w-full max-w-md border-0 bg-transparent text-lg font-semibold text-n-slate-12 outline-none"
              :aria-label="t('WHATSAPP_CLOUD_STUDIO.FLOWS.EDITOR.FLOW_NAME')"
            />
            <div class="flex items-center gap-2 text-xs text-n-slate-9">
              <span
                class="size-2 rounded-full"
                :class="
                  draft.status === 'active' ? 'bg-n-teal-9' : 'bg-n-slate-8'
                "
                aria-hidden="true"
              />
              <span>
                {{ flowStatusLabel(draft.status) }}
              </span>
            </div>
          </div>
        </div>
        <div class="flex w-full items-center justify-end gap-2 sm:w-auto">
          <Button
            :label="t('WHATSAPP_CLOUD_STUDIO.FLOWS.EDITOR.SAVE_DRAFT')"
            color="slate"
            variant="outline"
            :is-loading="isSaving"
            :disabled="isSaving || isPublishing"
            @click="emit('save', preparePayload())"
          />
          <Button
            :label="t('WHATSAPP_CLOUD_STUDIO.FLOWS.EDITOR.PUBLISH')"
            icon="i-lucide-rocket"
            :is-loading="isPublishing"
            :disabled="
              isSaving ||
              isPublishing ||
              flowHasUnsupportedTemplates ||
              flowHasIncompleteTemplateParameters
            "
            @click="emit('publish', preparePayload())"
          />
        </div>
      </header>

      <div
        class="grid min-h-0 flex-1 grid-cols-1 grid-rows-[auto_minmax(34rem,1fr)_auto] overflow-auto lg:grid-cols-[13rem_minmax(40rem,1fr)_18rem] lg:grid-rows-1 xl:grid-cols-[15rem_minmax(0,1fr)_20rem]"
      >
        <aside
          class="overflow-x-auto border-b border-n-weak bg-n-alpha-1 p-4 lg:overflow-y-auto lg:border-b-0 lg:border-r"
        >
          <h2
            class="text-xs font-semibold uppercase tracking-wide text-n-slate-9"
          >
            {{ t('WHATSAPP_CLOUD_STUDIO.FLOWS.EDITOR.BLOCKS') }}
          </h2>
          <div
            class="mt-3 grid min-w-[38rem] grid-cols-5 gap-2 lg:min-w-0 lg:grid-cols-1"
          >
            <button
              v-for="nodeType in nodeTypes"
              :key="nodeType.type"
              type="button"
              class="flex min-h-11 w-full items-center gap-3 rounded-xl border border-n-weak bg-n-alpha-1 px-3 text-left text-sm font-medium text-n-slate-12 transition hover:border-n-strong hover:bg-n-alpha-2 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
              @click="addNode(nodeType.type)"
            >
              <span
                class="flex size-8 items-center justify-center rounded-lg bg-n-blue-3 text-n-blue-11"
              >
                <span
                  class="size-4"
                  :class="nodeType.icon"
                  aria-hidden="true"
                />
              </span>
              <span>
                {{ nodeTypeLabel(nodeType.type) }}
              </span>
            </button>
          </div>

          <div
            class="mt-4 rounded-xl border border-n-weak bg-n-alpha-2 p-3 lg:mt-6"
          >
            <h3
              class="flex items-center gap-2 text-xs font-semibold text-n-slate-12"
            >
              <span class="i-lucide-link-2 size-3.5" aria-hidden="true" />
              {{ t('WHATSAPP_CLOUD_STUDIO.FLOWS.EDITOR.CONNECT_HELP_TITLE') }}
            </h3>
            <p class="mt-1 text-xs leading-5 text-n-slate-9">
              {{ t('WHATSAPP_CLOUD_STUDIO.FLOWS.EDITOR.CONNECT_HELP') }}
            </p>
          </div>
        </aside>

        <div
          class="relative min-h-[34rem] min-w-0 overflow-auto bg-n-surface-2 lg:min-h-0"
        >
          <div
            v-if="pendingConnection"
            class="sticky left-4 top-4 z-10 inline-flex items-center gap-2 rounded-lg bg-n-blue-9 px-3 py-2 text-xs font-medium text-white shadow-lg"
          >
            <span
              class="i-lucide-mouse-pointer-click size-4"
              aria-hidden="true"
            />
            {{ t('WHATSAPP_CLOUD_STUDIO.FLOWS.EDITOR.SELECT_TARGET') }}
            <button
              type="button"
              class="ml-1 rounded p-0.5 hover:bg-white/20"
              :aria-label="t('WHATSAPP_CLOUD_STUDIO.CANCEL')"
              @click="pendingConnection = null"
            >
              <span class="i-lucide-x size-3" aria-hidden="true" />
            </button>
          </div>

          <svg
            ref="svgRef"
            viewBox="0 0 1600 900"
            class="block min-h-[50rem] min-w-[90rem] select-none"
            :aria-label="t('WHATSAPP_CLOUD_STUDIO.FLOWS.EDITOR.CANVAS')"
          >
            <defs>
              <pattern
                id="whatsapp-flow-grid"
                width="24"
                height="24"
                patternUnits="userSpaceOnUse"
              >
                <circle cx="1" cy="1" r="1" class="fill-n-slate-5" />
              </pattern>
              <marker
                id="whatsapp-flow-arrow"
                markerWidth="8"
                markerHeight="8"
                refX="7"
                refY="4"
                orient="auto"
              >
                <path d="M 0 0 L 8 4 L 0 8 z" class="fill-n-slate-8" />
              </marker>
            </defs>
            <rect width="1600" height="900" fill="url(#whatsapp-flow-grid)" />

            <path
              v-for="edge in draft.definition.edges"
              :key="edge.id"
              :d="edgePath(edge)"
              fill="none"
              class="stroke-n-slate-8"
              stroke-width="2"
              marker-end="url(#whatsapp-flow-arrow)"
            />

            <g v-for="node in draft.definition.nodes" :key="node.id">
              <foreignObject
                :x="node.position.x"
                :y="node.position.y"
                width="260"
                :height="nodeHeight(node)"
              >
                <div
                  class="h-full overflow-hidden rounded-xl border-2 bg-n-solid-1 shadow-md"
                  :data-test-id="`flow-node-${node.id}`"
                  :class="
                    selectedNodeId === node.id
                      ? 'border-n-brand'
                      : 'border-n-weak'
                  "
                  @click="selectedNodeId = node.id"
                >
                  <button
                    type="button"
                    class="flex h-14 w-full cursor-grab items-center gap-3 border-b border-n-weak px-3 text-left active:cursor-grabbing"
                    @pointerdown.prevent="startDragging($event, node)"
                  >
                    <span
                      class="flex size-8 shrink-0 items-center justify-center rounded-lg"
                      :class="nodeTone(node)"
                    >
                      <span
                        class="size-4"
                        :class="nodeIcon(node)"
                        aria-hidden="true"
                      />
                    </span>
                    <span class="min-w-0">
                      <span class="block text-sm font-semibold text-n-slate-12">
                        {{ nodeTitle(node) }}
                      </span>
                      <span class="block truncate text-xs text-n-slate-9">
                        {{ nodeSubtitle(node) }}
                      </span>
                    </span>
                  </button>
                  <div
                    v-if="
                      node.type === 'message' && node.config.buttons?.length
                    "
                    class="space-y-1 p-2"
                  >
                    <div
                      v-for="button in node.config.buttons"
                      :key="button.id"
                      class="flex h-7 items-center rounded-md bg-n-alpha-2 px-2 text-xs text-n-slate-11"
                    >
                      <span
                        class="i-lucide-reply mr-1.5 size-3"
                        aria-hidden="true"
                      />
                      <span class="truncate">
                        {{
                          button.title ||
                          t(
                            'WHATSAPP_CLOUD_STUDIO.FLOWS.EDITOR.UNTITLED_BUTTON'
                          )
                        }}
                      </span>
                    </div>
                  </div>
                  <div
                    v-else
                    class="line-clamp-3 px-3 py-3 text-xs leading-5 text-n-slate-10"
                  >
                    {{ nodeSubtitle(node) }}
                  </div>
                </div>
              </foreignObject>

              <circle
                :cx="node.position.x"
                :cy="node.position.y + 58"
                r="7"
                class="cursor-pointer fill-n-solid-1 stroke-n-brand hover:fill-n-blue-3"
                stroke-width="3"
                role="button"
                :aria-label="
                  t('WHATSAPP_CLOUD_STUDIO.FLOWS.EDITOR.TARGET_HANDLE')
                "
                tabindex="0"
                @click="finishConnection(node.id)"
                @keydown.enter="finishConnection(node.id)"
              />
              <circle
                v-if="
                  node.type !== 'end' &&
                  node.type !== 'condition' &&
                  !(node.type === 'message' && node.config.buttons?.length)
                "
                :cx="node.position.x + 260"
                :cy="node.position.y + 58"
                r="7"
                class="cursor-pointer fill-n-solid-1 stroke-n-brand hover:fill-n-blue-3"
                stroke-width="3"
                role="button"
                :aria-label="
                  t('WHATSAPP_CLOUD_STUDIO.FLOWS.EDITOR.SOURCE_HANDLE')
                "
                tabindex="0"
                @click="startConnection(node.id)"
                @keydown.enter="startConnection(node.id)"
              />
              <circle
                v-for="conditionHandle in node.type === 'condition'
                  ? ['true', 'false']
                  : []"
                :key="`${node.id}-${conditionHandle}`"
                :cx="node.position.x + 260"
                :cy="handleY(node, conditionHandle)"
                r="6"
                class="cursor-pointer fill-n-solid-1 stroke-n-brand hover:fill-n-blue-3"
                stroke-width="3"
                role="button"
                :aria-label="conditionHandleLabel(conditionHandle)"
                tabindex="0"
                @click="startConnection(node.id, conditionHandle)"
                @keydown.enter="startConnection(node.id, conditionHandle)"
              />
              <circle
                v-for="button in node.type === 'message'
                  ? node.config.buttons || []
                  : []"
                :key="`${node.id}-${button.id}`"
                :cx="node.position.x + 260"
                :cy="handleY(node, button.id)"
                r="6"
                class="cursor-pointer fill-n-solid-1 stroke-n-brand hover:fill-n-blue-3"
                stroke-width="3"
                role="button"
                :aria-label="
                  t('WHATSAPP_CLOUD_STUDIO.FLOWS.EDITOR.BUTTON_HANDLE', {
                    title: button.title,
                  })
                "
                tabindex="0"
                @click="startConnection(node.id, button.id)"
                @keydown.enter="startConnection(node.id, button.id)"
              />
            </g>
          </svg>
        </div>

        <aside
          class="overflow-y-auto border-t border-n-weak bg-n-alpha-1 p-4 lg:border-l lg:border-t-0"
        >
          <template v-if="selectedNode">
            <div class="flex items-start justify-between gap-2">
              <div>
                <h2 class="text-sm font-semibold text-n-slate-12">
                  {{ nodeTitle(selectedNode) }}
                </h2>
                <p class="mt-1 text-xs text-n-slate-9">
                  {{ t('WHATSAPP_CLOUD_STUDIO.FLOWS.EDITOR.NODE_SETTINGS') }}
                </p>
              </div>
              <button
                v-if="selectedNode.type !== 'trigger'"
                type="button"
                class="flex size-9 items-center justify-center rounded-lg text-n-ruby-11 hover:bg-n-ruby-3"
                :aria-label="
                  t('WHATSAPP_CLOUD_STUDIO.FLOWS.EDITOR.DELETE_NODE')
                "
                @click="deleteSelectedNode"
              >
                <span class="i-lucide-trash-2 size-4" aria-hidden="true" />
              </button>
            </div>

            <div v-if="selectedNode.type === 'trigger'" class="mt-5 space-y-4">
              <label
                class="flex flex-col gap-1 text-xs font-medium text-n-slate-11"
              >
                {{ t('WHATSAPP_CLOUD_STUDIO.FLOWS.EDITOR.TRIGGER') }}
                <StudioSelect v-model="draft.trigger_type">
                  <option value="keyword">
                    {{ t('WHATSAPP_CLOUD_STUDIO.FLOWS.EDITOR.KEYWORD') }}
                  </option>
                  <option value="any_message">
                    {{ t('WHATSAPP_CLOUD_STUDIO.FLOWS.EDITOR.ANY_MESSAGE') }}
                  </option>
                </StudioSelect>
              </label>
              <label
                v-if="draft.trigger_type === 'keyword'"
                class="flex flex-col gap-1 text-xs font-medium text-n-slate-11"
              >
                {{ t('WHATSAPP_CLOUD_STUDIO.FLOWS.EDITOR.KEYWORDS') }}
                <input
                  :value="draft.trigger_config.keywords?.join(', ')"
                  class="reset-base !mb-0 h-11 rounded-xl border border-n-strong bg-n-alpha-1 px-3 text-sm text-n-slate-12 outline-none focus:border-n-brand focus:ring-1 focus:ring-n-brand"
                  :placeholder="
                    t('WHATSAPP_CLOUD_STUDIO.FLOWS.EDITOR.KEYWORDS_PLACEHOLDER')
                  "
                  @input="
                    draft.trigger_config.keywords = $event.target.value
                      .split(',')
                      .map(item => item.trim())
                      .filter(Boolean)
                  "
                />
              </label>
            </div>

            <div
              v-else-if="selectedNode.type === 'message'"
              class="mt-5 space-y-4"
            >
              <label
                class="flex flex-col gap-1 text-xs font-medium text-n-slate-11"
              >
                {{ t('WHATSAPP_CLOUD_STUDIO.FLOWS.EDITOR.MESSAGE_MODE') }}
                <StudioSelect v-model="selectedNode.config.mode">
                  <option value="session">
                    {{
                      t('WHATSAPP_CLOUD_STUDIO.FLOWS.EDITOR.SESSION_MESSAGE')
                    }}
                  </option>
                  <option value="template">
                    {{
                      t('WHATSAPP_CLOUD_STUDIO.FLOWS.EDITOR.TEMPLATE_MESSAGE')
                    }}
                  </option>
                </StudioSelect>
              </label>
              <div
                class="rounded-lg border p-3 text-xs leading-5"
                :class="
                  selectedNode.config.mode === 'session'
                    ? 'border-n-amber-7 bg-n-amber-2 text-n-amber-11'
                    : 'border-n-teal-7 bg-n-teal-2 text-n-teal-11'
                "
              >
                {{
                  selectedNode.config.mode === 'session'
                    ? t('WHATSAPP_CLOUD_STUDIO.FLOWS.EDITOR.SESSION_WARNING')
                    : t('WHATSAPP_CLOUD_STUDIO.FLOWS.EDITOR.TEMPLATE_INFO')
                }}
              </div>
              <label
                v-if="selectedNode.config.mode === 'session'"
                class="flex flex-col gap-1 text-xs font-medium text-n-slate-11"
              >
                {{ t('WHATSAPP_CLOUD_STUDIO.FLOWS.EDITOR.MESSAGE_TEXT') }}
                <textarea
                  v-model="selectedNode.config.text"
                  rows="6"
                  class="reset-base !mb-0 min-h-32 resize-y rounded-xl border border-n-strong bg-n-alpha-1 px-3 py-2 text-sm text-n-slate-12 outline-none focus:border-n-brand focus:ring-1 focus:ring-n-brand"
                />
              </label>
              <label
                v-else
                class="flex flex-col gap-1 text-xs font-medium text-n-slate-11"
              >
                {{ t('WHATSAPP_CLOUD_STUDIO.FLOWS.EDITOR.TEMPLATE') }}
                <StudioSelect
                  :model-value="selectedTemplateKey"
                  @update:model-value="updateTemplate"
                >
                  <option value="">
                    {{
                      t('WHATSAPP_CLOUD_STUDIO.FLOWS.EDITOR.SELECT_TEMPLATE')
                    }}
                  </option>
                  <option
                    v-for="template in approvedTemplates"
                    :key="`${template.name}-${template.language}`"
                    :value="`${template.name}|${template.language}`"
                    :disabled="!isStudioTemplateSupported(template)"
                  >
                    {{ selectableTemplateLabel(template) }}
                  </option>
                </StudioSelect>
              </label>

              <div
                v-if="selectedTemplateUnsupported"
                class="rounded-lg border border-n-amber-7 bg-n-amber-2 p-3 text-xs leading-5 text-n-amber-11"
              >
                {{
                  t(
                    'WHATSAPP_CLOUD_STUDIO.TEMPLATE_PARAMETERS.UNSUPPORTED_SELECTED'
                  )
                }}
              </div>

              <StudioTemplateParameterFields
                v-if="
                  selectedNode.config.mode === 'template' && selectedTemplate
                "
                v-model="selectedNode.config.processed_params"
                :template="selectedTemplate"
              />

              <div
                v-if="selectedTemplateParametersIncomplete"
                class="rounded-lg border border-n-ruby-7 bg-n-ruby-2 p-3 text-xs leading-5 text-n-ruby-11"
              >
                {{
                  t(
                    'WHATSAPP_CLOUD_STUDIO.TEMPLATE_PARAMETERS.INCOMPLETE_SELECTED'
                  )
                }}
              </div>

              <div v-if="selectedNode.config.mode === 'session'">
                <div class="flex items-center justify-between gap-2">
                  <span class="text-xs font-medium text-n-slate-11">
                    {{ t('WHATSAPP_CLOUD_STUDIO.FLOWS.EDITOR.REPLY_BUTTONS') }}
                  </span>
                  <button
                    v-if="selectedNode.config.buttons.length < 3"
                    type="button"
                    class="text-xs font-medium text-n-blue-11 hover:underline"
                    @click="addReplyButton"
                  >
                    {{ t('WHATSAPP_CLOUD_STUDIO.FLOWS.EDITOR.ADD_BUTTON') }}
                  </button>
                </div>
                <div class="mt-2 space-y-2">
                  <div
                    v-for="(button, index) in selectedNode.config.buttons"
                    :key="button.id"
                    class="grid grid-cols-[1fr_auto] gap-2 rounded-lg border border-n-weak bg-n-alpha-2 p-2"
                  >
                    <input
                      v-model="button.title"
                      class="reset-base !mb-0 h-9 rounded-md border border-n-strong bg-n-alpha-1 px-2 text-sm text-n-slate-12 outline-none focus:border-n-brand focus:ring-1 focus:ring-n-brand"
                      :placeholder="
                        t('WHATSAPP_CLOUD_STUDIO.FLOWS.EDITOR.BUTTON_TITLE')
                      "
                    />
                    <button
                      type="button"
                      class="flex size-9 items-center justify-center rounded-md text-n-ruby-11 hover:bg-n-ruby-3"
                      :aria-label="
                        t('WHATSAPP_CLOUD_STUDIO.FLOWS.EDITOR.REMOVE_BUTTON')
                      "
                      @click="removeReplyButton(index)"
                    >
                      <span class="i-lucide-x size-4" aria-hidden="true" />
                    </button>
                    <code
                      class="col-span-2 truncate text-[0.65rem] text-n-slate-9"
                    >
                      {{ button.id }}
                    </code>
                  </div>
                </div>
              </div>
            </div>

            <div v-else-if="selectedNode.type === 'wait'" class="mt-5">
              <label
                class="flex flex-col gap-1 text-xs font-medium text-n-slate-11"
              >
                {{ t('WHATSAPP_CLOUD_STUDIO.FLOWS.EDITOR.DURATION_MINUTES') }}
                <input
                  v-model.number="selectedNode.config.duration"
                  type="number"
                  min="1"
                  max="43200"
                  class="reset-base !mb-0 h-11 rounded-xl border border-n-strong bg-n-alpha-1 px-3 text-sm text-n-slate-12 outline-none focus:border-n-brand focus:ring-1 focus:ring-n-brand"
                />
              </label>
            </div>

            <div
              v-else-if="selectedNode.type === 'condition'"
              class="mt-5 space-y-3"
            >
              <label
                class="flex flex-col gap-1 text-xs font-medium text-n-slate-11"
              >
                {{ t('WHATSAPP_CLOUD_STUDIO.FLOWS.EDITOR.FIELD') }}
                <StudioSelect v-model="selectedNode.config.field">
                  <option value="last_button_id">
                    {{ t('WHATSAPP_CLOUD_STUDIO.FLOWS.EDITOR.LAST_BUTTON') }}
                  </option>
                  <option value="name">
                    {{ t('WHATSAPP_CLOUD_STUDIO.FLOWS.EDITOR.CONTACT_NAME') }}
                  </option>
                  <option value="email">
                    {{ t('WHATSAPP_CLOUD_STUDIO.FLOWS.EDITOR.CONTACT_EMAIL') }}
                  </option>
                  <option value="phone_number">
                    {{ t('WHATSAPP_CLOUD_STUDIO.FLOWS.EDITOR.CONTACT_PHONE') }}
                  </option>
                </StudioSelect>
              </label>
              <label
                class="flex flex-col gap-1 text-xs font-medium text-n-slate-11"
              >
                {{ t('WHATSAPP_CLOUD_STUDIO.FLOWS.EDITOR.OPERATOR') }}
                <StudioSelect v-model="selectedNode.config.operator">
                  <option value="equals">
                    {{ t('WHATSAPP_CLOUD_STUDIO.FLOWS.EDITOR.EQUALS') }}
                  </option>
                  <option value="not_equals">
                    {{ t('WHATSAPP_CLOUD_STUDIO.FLOWS.EDITOR.NOT_EQUALS') }}
                  </option>
                  <option value="contains">
                    {{ t('WHATSAPP_CLOUD_STUDIO.FLOWS.EDITOR.CONTAINS') }}
                  </option>
                  <option value="present">
                    {{ t('WHATSAPP_CLOUD_STUDIO.FLOWS.EDITOR.PRESENT') }}
                  </option>
                </StudioSelect>
              </label>
              <label
                class="flex flex-col gap-1 text-xs font-medium text-n-slate-11"
              >
                {{ t('WHATSAPP_CLOUD_STUDIO.FLOWS.EDITOR.VALUE') }}
                <input
                  v-model="selectedNode.config.value"
                  class="reset-base !mb-0 h-11 rounded-xl border border-n-strong bg-n-alpha-1 px-3 text-sm text-n-slate-12 outline-none focus:border-n-brand focus:ring-1 focus:ring-n-brand"
                />
              </label>
              <div class="grid grid-cols-2 gap-2 pt-1 text-xs">
                <button
                  type="button"
                  class="rounded-lg border border-n-teal-7 bg-n-teal-2 px-2 py-2 font-medium text-n-teal-11"
                  @click="startConnection(selectedNode.id, 'true')"
                >
                  {{ t('WHATSAPP_CLOUD_STUDIO.FLOWS.EDITOR.TRUE_BRANCH') }}
                </button>
                <button
                  type="button"
                  class="rounded-lg border border-n-ruby-7 bg-n-ruby-2 px-2 py-2 font-medium text-n-ruby-11"
                  @click="startConnection(selectedNode.id, 'false')"
                >
                  {{ t('WHATSAPP_CLOUD_STUDIO.FLOWS.EDITOR.FALSE_BRANCH') }}
                </button>
              </div>
            </div>

            <div
              v-else-if="selectedNode.type === 'action'"
              class="mt-5 space-y-3"
            >
              <label
                class="flex flex-col gap-1 text-xs font-medium text-n-slate-11"
              >
                {{ t('WHATSAPP_CLOUD_STUDIO.FLOWS.EDITOR.ACTION') }}
                <StudioSelect v-model="selectedNode.config.action">
                  <option value="add_label">
                    {{ t('WHATSAPP_CLOUD_STUDIO.FLOWS.ACTIONS.ADD_LABEL') }}
                  </option>
                  <option value="remove_label">
                    {{ t('WHATSAPP_CLOUD_STUDIO.FLOWS.ACTIONS.REMOVE_LABEL') }}
                  </option>
                  <option value="open_conversation">
                    {{
                      t('WHATSAPP_CLOUD_STUDIO.FLOWS.ACTIONS.OPEN_CONVERSATION')
                    }}
                  </option>
                  <option value="resolve_conversation">
                    {{
                      t(
                        'WHATSAPP_CLOUD_STUDIO.FLOWS.ACTIONS.RESOLVE_CONVERSATION'
                      )
                    }}
                  </option>
                </StudioSelect>
              </label>
              <label
                v-if="
                  ['add_label', 'remove_label'].includes(
                    selectedNode.config.action
                  )
                "
                class="flex flex-col gap-1 text-xs font-medium text-n-slate-11"
              >
                {{ t('WHATSAPP_CLOUD_STUDIO.FLOWS.EDITOR.LABEL') }}
                <input
                  v-model="selectedNode.config.value"
                  class="reset-base !mb-0 h-11 rounded-xl border border-n-strong bg-n-alpha-1 px-3 text-sm text-n-slate-12 outline-none focus:border-n-brand focus:ring-1 focus:ring-n-brand"
                />
              </label>
            </div>

            <div class="mt-6 border-t border-n-weak pt-4">
              <label
                class="flex flex-col gap-1 text-xs font-medium text-n-slate-11"
              >
                {{ t('WHATSAPP_CLOUD_STUDIO.FLOWS.EDITOR.DESCRIPTION') }}
                <textarea
                  v-model="draft.description"
                  rows="3"
                  class="reset-base !mb-0 min-h-24 resize-y rounded-xl border border-n-strong bg-n-alpha-1 px-3 py-2 text-sm text-n-slate-12 outline-none focus:border-n-brand focus:ring-1 focus:ring-n-brand"
                />
              </label>
            </div>
          </template>
        </aside>
      </div>
    </div>
  </TeleportWithDirection>
</template>
