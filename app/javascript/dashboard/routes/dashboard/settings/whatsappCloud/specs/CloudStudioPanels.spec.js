import { config, flushPromises, mount } from '@vue/test-utils';
import { defineComponent, h, nextTick, reactive, ref } from 'vue';
import { createI18n } from 'vue-i18n';

import BroadcastsPanel from '../BroadcastsPanel.vue';
import FlowEditor from '../FlowEditor.vue';
import TemplatesPanel from '../TemplatesPanel.vue';
import englishMessages from 'dashboard/i18n/locale/en/whatsappCloudStudio.json';
import portugueseMessages from 'dashboard/i18n/locale/pt/whatsappCloudStudio.json';
import brazilianPortugueseMessages from 'dashboard/i18n/locale/pt_BR/whatsappCloudStudio.json';
import {
  whatsappCloudAudienceImportsAPI,
  whatsappCloudTemplatesAPI,
} from 'dashboard/api/whatsappCloudStudio';
import { templateParametersComplete } from '../templateParameterUtils';

vi.mock('dashboard/api/whatsappCloudStudio', () => ({
  whatsappCloudTemplatesAPI: {
    createForInbox: vi.fn(),
    deleteForInbox: vi.fn(),
    sync: vi.fn(),
  },
  whatsappCloudAudienceEstimateAPI: {
    getEstimate: vi.fn(),
  },
  whatsappCloudAudienceImportsAPI: {
    create: vi.fn(),
  },
}));

vi.mock('dashboard/composables', () => ({
  useAlert: vi.fn(),
}));

vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch: vi.fn() }),
}));

const buttonByText = (wrapper, label) =>
  wrapper.findAll('button').find(button => button.text().includes(label));

const TeleportStub = {
  setup(_, { slots }) {
    return () => h('div', slots.default?.());
  },
};

const DialogStub = defineComponent({
  emits: ['close', 'confirm'],
  setup(_, { emit, expose, slots }) {
    const isOpen = ref(false);
    expose({
      open: () => {
        isOpen.value = true;
      },
      close: () => {
        isOpen.value = false;
        emit('close');
      },
    });
    return () =>
      isOpen.value
        ? h(
            'form',
            {
              role: 'dialog',
              onSubmit: event => {
                event.preventDefault();
                emit('confirm');
              },
            },
            slots.default?.()
          )
        : undefined;
  },
});

const translationKeys = (object, prefix = '') =>
  Object.entries(object).flatMap(([key, value]) => {
    const path = prefix ? `${prefix}.${key}` : key;
    return typeof value === 'object' ? translationKeys(value, path) : [path];
  });

describe('WhatsApp Cloud Studio panels', () => {
  beforeAll(() => {
    HTMLDialogElement.prototype.showModal = function showModal() {
      this.setAttribute('open', '');
    };
    HTMLDialogElement.prototype.close = function close() {
      this.removeAttribute('open');
      this.dispatchEvent(new Event('close'));
    };
  });

  afterEach(() => {
    vi.clearAllMocks();
    document.body.innerHTML = '';
  });

  it.each([
    ['en', englishMessages],
    ['pt', portugueseMessages],
    ['pt_BR', brazilianPortugueseMessages],
  ])('compiles every %s translation without message-syntax errors', locale => {
    const messages = {
      en: englishMessages,
      pt: portugueseMessages,
      pt_BR: brazilianPortugueseMessages,
    };
    const i18n = createI18n({
      legacy: false,
      locale,
      missingWarn: false,
      fallbackWarn: false,
      messages,
    });

    translationKeys(messages[locale]).forEach(key => {
      // eslint-disable-next-line @intlify/vue-i18n/no-dynamic-keys
      expect(() => i18n.global.t(key)).not.toThrow();
    });
  });

  it('validates media URLs and copy-code values before enabling a send', () => {
    expect(
      templateParametersComplete({
        header: { media_type: 'image', media_url: 'not-a-url' },
      })
    ).toBe(false);
    expect(
      templateParametersComplete({
        header: {
          media_type: 'image',
          media_url: 'https://example.com/header.png',
        },
      })
    ).toBe(true);
    expect(
      templateParametersComplete(
        {
          header: {
            media_type: 'image',
            media_url: '{{ contact.custom_attributes.header_url }}',
          },
        },
        { allowLiquid: true }
      )
    ).toBe(true);
    expect(
      templateParametersComplete({
        buttons: [{ type: 'copy_code', index: 0, parameter: '' }],
      })
    ).toBe(false);
  });

  it('opens the template form and renders numbered-variable syntax safely', async () => {
    const wrapper = mount(TemplatesPanel, {
      attachTo: document.body,
      props: {
        inbox: { id: 29 },
        templates: [],
      },
      global: {
        stubs: {
          Dialog: DialogStub,
        },
      },
    });

    await buttonByText(wrapper, 'New template').trigger('click');
    await nextTick();

    const bodyInput = document.body.querySelector('textarea');
    expect(bodyInput).not.toBeNull();
    expect(bodyInput.placeholder).toContain('{{1}}');
    expect(document.body.textContent).toContain('Create message template');

    wrapper.unmount();
  });

  it('submits a valid template from the visible Meta action', async () => {
    whatsappCloudTemplatesAPI.createForInbox.mockResolvedValue({
      data: { templates: [] },
    });
    const wrapper = mount(TemplatesPanel, {
      props: {
        inbox: { id: 29 },
        templates: [],
      },
      global: {
        stubs: {
          Dialog: DialogStub,
        },
      },
    });

    await buttonByText(wrapper, 'New template').trigger('click');
    await nextTick();
    await wrapper.find('input[pattern]').setValue('order_update');
    await wrapper.find('textarea').setValue('Hello {{1}}');
    await wrapper.find('input[required]:not([pattern])').setValue('Marcos');
    const submitButton = buttonByText(wrapper, 'Submit to Meta');
    expect(submitButton.attributes('type')).toBe('submit');
    await wrapper.find('[role="dialog"]').trigger('submit');
    await flushPromises();

    expect(whatsappCloudTemplatesAPI.createForInbox).toHaveBeenCalledWith(
      29,
      expect.objectContaining({
        name: 'order_update',
        components: expect.arrayContaining([
          expect.objectContaining({ type: 'BODY', text: 'Hello {{1}}' }),
        ]),
      })
    );
    expect(wrapper.find('[role="dialog"]').exists()).toBe(false);
    wrapper.unmount();
  });

  it('clones reactive flows and saves template variables and quick replies', async () => {
    const flow = reactive({
      id: null,
      inbox_id: 29,
      name: 'Template journey',
      description: '',
      status: 'draft',
      trigger_type: 'keyword',
      trigger_config: { keywords: ['status'] },
      definition: {
        nodes: [
          {
            id: 'trigger',
            type: 'trigger',
            position: { x: 80, y: 220 },
            config: {},
          },
          {
            id: 'message',
            type: 'message',
            position: { x: 420, y: 220 },
            config: {
              mode: 'template',
              template_name: '',
              language: '',
              buttons: [],
              processed_params: {},
            },
          },
          {
            id: 'end',
            type: 'end',
            position: { x: 760, y: 220 },
            config: {},
          },
        ],
        edges: [
          {
            id: 'edge-trigger',
            source: 'trigger',
            target: 'message',
            source_handle: 'default',
          },
          {
            id: 'edge-message',
            source: 'message',
            target: 'end',
            source_handle: 'default',
          },
        ],
      },
    });
    const templates = [
      {
        name: 'order_update',
        language: 'pt_BR',
        category: 'UTILITY',
        status: 'APPROVED',
        components: [
          { type: 'BODY', text: 'Olá {{1}}, seu pedido está pronto.' },
          {
            type: 'BUTTONS',
            buttons: [{ type: 'QUICK_REPLY', text: 'Ver pedido' }],
          },
        ],
      },
    ];

    const wrapper = mount(FlowEditor, {
      props: { flow, templates },
      global: {
        stubs: {
          TeleportWithDirection: TeleportStub,
        },
      },
    });

    await wrapper.find('[data-test-id="flow-node-message"]').trigger('click');
    await nextTick();

    const selects = wrapper.findAll('select');
    await selects[1].setValue('order_update|pt_BR');
    await nextTick();

    expect(
      buttonByText(wrapper, 'Publish').attributes('disabled')
    ).toBeDefined();
    const variableInput = wrapper.find(
      'input[placeholder="Enter the value sent to this contact"]'
    );
    expect(variableInput.exists()).toBe(true);
    await variableInput.setValue('Marcos');
    await nextTick();
    expect(
      buttonByText(wrapper, 'Publish').attributes('disabled')
    ).toBeUndefined();
    await buttonByText(wrapper, 'Save draft').trigger('click');
    await flushPromises();

    const payload = wrapper.emitted('save')[0][0];
    const messageNode = payload.definition.nodes.find(
      node => node.id === 'message'
    );
    expect(messageNode.config.processed_params.body).toEqual({
      1: 'Marcos',
    });
    expect(messageNode.config.processed_params.buttons).toEqual([
      {
        type: 'quick_reply',
        index: 0,
        payload: 'template_reply_0',
      },
    ]);

    wrapper.unmount();
  });

  it('renders condition summaries in Brazilian Portuguese', async () => {
    const testI18n = config.global.plugins.find(
      plugin => plugin?.global?.locale
    );
    const previousLocale = testI18n.global.locale.value;
    testI18n.global.locale.value = 'pt_BR';
    const flow = {
      id: null,
      inbox_id: 29,
      name: 'Funil de condição',
      description: '',
      status: 'draft',
      trigger_type: 'any_message',
      trigger_config: {},
      definition: {
        nodes: [
          {
            id: 'trigger',
            type: 'trigger',
            position: { x: 80, y: 220 },
            config: {},
          },
          {
            id: 'condition',
            type: 'condition',
            position: { x: 420, y: 220 },
            config: {
              field: 'last_button_id',
              operator: 'equals',
              value: 'template_reply_0',
            },
          },
        ],
        edges: [],
      },
    };

    const wrapper = mount(FlowEditor, {
      props: { flow },
      global: {
        stubs: {
          TeleportWithDirection: TeleportStub,
        },
      },
    });

    expect(wrapper.text()).toContain('Último botão selecionado - É igual a');
    expect(wrapper.text()).not.toContain('last_button_id - equals');

    wrapper.unmount();
    testI18n.global.locale.value = previousLocale;
  });

  it('uses an integrated dialog before discarding unsaved flow changes', async () => {
    const flow = {
      id: null,
      inbox_id: 29,
      name: 'Draft journey',
      description: '',
      status: 'draft',
      trigger_type: 'any_message',
      trigger_config: {},
      definition: {
        nodes: [
          {
            id: 'trigger',
            type: 'trigger',
            position: { x: 80, y: 220 },
            config: {},
          },
        ],
        edges: [],
      },
    };
    const confirmSpy = vi.spyOn(window, 'confirm');
    const wrapper = mount(FlowEditor, {
      props: { flow },
      global: {
        stubs: {
          TeleportWithDirection: TeleportStub,
          Dialog: DialogStub,
        },
      },
    });

    await wrapper
      .find('input[aria-label="Flow name"]')
      .setValue('Changed journey');
    await wrapper.find('button[aria-label="Close"]').trigger('click');

    expect(confirmSpy).not.toHaveBeenCalled();
    const dialogs = wrapper.findAll('[role="dialog"]');
    expect(dialogs).toHaveLength(2);
    expect(wrapper.emitted('close')).toBeUndefined();

    await dialogs[1].trigger('submit');
    expect(wrapper.emitted('close')).toHaveLength(1);

    confirmSpy.mockRestore();
    wrapper.unmount();
  });

  it('clears block selection on the empty canvas and supports box selection', async () => {
    const flow = {
      id: null,
      inbox_id: 29,
      name: 'Selection journey',
      description: '',
      status: 'draft',
      trigger_type: 'any_message',
      trigger_config: {},
      definition: {
        nodes: [
          {
            id: 'trigger',
            type: 'trigger',
            position: { x: 80, y: 220 },
            config: {},
          },
          {
            id: 'message',
            type: 'message',
            position: { x: 420, y: 220 },
            config: { mode: 'session', text: 'Hello', buttons: [] },
          },
        ],
        edges: [],
      },
    };
    const wrapper = mount(FlowEditor, {
      props: { flow },
      global: {
        stubs: {
          TeleportWithDirection: TeleportStub,
        },
      },
    });
    const triggerNode = wrapper.find('[data-test-id="flow-node-trigger"]');
    const messageNode = wrapper.find('[data-test-id="flow-node-message"]');
    const canvas = wrapper.find('svg');

    await messageNode.trigger('click');
    expect(messageNode.attributes('aria-pressed')).toBe('true');
    canvas.element.dispatchEvent(
      new MouseEvent('pointerdown', {
        bubbles: true,
        button: 0,
        clientX: 10,
        clientY: 10,
      })
    );
    window.dispatchEvent(
      new MouseEvent('pointerup', { clientX: 10, clientY: 10 })
    );
    await nextTick();
    expect(messageNode.attributes('aria-pressed')).toBe('false');

    canvas.element.dispatchEvent(
      new MouseEvent('pointerdown', {
        bubbles: true,
        button: 2,
        clientX: 10,
        clientY: 10,
      })
    );
    window.dispatchEvent(
      new MouseEvent('pointermove', { clientX: 900, clientY: 600 })
    );
    window.dispatchEvent(
      new MouseEvent('pointerup', { clientX: 900, clientY: 600 })
    );
    await nextTick();

    expect(triggerNode.attributes('aria-pressed')).toBe('true');
    expect(messageNode.attributes('aria-pressed')).toBe('true');
    expect(wrapper.text()).toContain('2 blocks selected');

    messageNode.element.dispatchEvent(
      new MouseEvent('pointerdown', {
        bubbles: true,
        button: 0,
        ctrlKey: true,
        clientX: 500,
        clientY: 300,
      })
    );
    window.dispatchEvent(
      new MouseEvent('pointerup', { clientX: 500, clientY: 300 })
    );
    messageNode.element.dispatchEvent(
      new MouseEvent('click', {
        bubbles: true,
        ctrlKey: true,
        detail: 1,
      })
    );
    await nextTick();
    expect(triggerNode.attributes('aria-pressed')).toBe('true');
    expect(messageNode.attributes('aria-pressed')).toBe('false');

    wrapper.unmount();
  });

  it('uses compact mobile flow layout and touch-friendly editor actions', () => {
    const flow = {
      id: null,
      inbox_id: 29,
      name: 'Responsive journey',
      description: '',
      status: 'draft',
      trigger_type: 'any_message',
      trigger_config: {},
      definition: {
        nodes: [
          {
            id: 'trigger',
            type: 'trigger',
            position: { x: 80, y: 220 },
            config: {},
          },
        ],
        edges: [],
      },
    };
    const wrapper = mount(FlowEditor, {
      props: { flow },
      global: {
        stubs: {
          TeleportWithDirection: TeleportStub,
        },
      },
    });

    const toolbox = wrapper.find('aside .grid-cols-2');
    const canvas = wrapper.find('svg');
    const closeButton = wrapper.find('button[aria-label="Close"]');

    expect(toolbox.exists()).toBe(true);
    expect(toolbox.classes()).toContain('sm:grid-cols-3');
    expect(canvas.classes()).toContain('size-full');
    expect(wrapper.text()).toContain('100%');
    expect(wrapper.find('.i-lucide-scan').exists()).toBe(true);
    expect(closeButton.classes()).toContain('size-11');

    wrapper.unmount();
  });

  it('stacks template actions on narrow screens', () => {
    const wrapper = mount(TemplatesPanel, {
      props: {
        inbox: { id: 29 },
        templates: [],
      },
      global: {
        stubs: {
          Dialog: DialogStub,
        },
      },
    });
    const syncButton = buttonByText(wrapper, 'Sync from Meta');
    const newButton = buttonByText(wrapper, 'New template');

    expect(syncButton.element.parentElement.classList).toContain('grid');
    expect(syncButton.classes()).toContain('w-full');
    expect(newButton.classes()).toContain('w-full');

    wrapper.unmount();
  });

  it('keeps cost calculation separate from broadcast submission', async () => {
    const wrapper = mount(BroadcastsPanel, {
      props: {
        inbox: { id: 29 },
        templates: [
          {
            name: 'hello_world',
            language: 'en_US',
            category: 'UTILITY',
            status: 'APPROVED',
            components: [{ type: 'BODY', text: 'Hello' }],
          },
        ],
        labels: [{ id: 1, title: 'Cliente' }],
        campaigns: [],
      },
      global: {
        stubs: {
          Dialog: DialogStub,
        },
      },
    });

    await buttonByText(wrapper, 'New broadcast').trigger('click');
    await nextTick();

    expect(wrapper.find('[role="dialog"]').attributes('width')).toBe('3xl');
    const estimateButton = buttonByText(wrapper, 'Calculate estimate');
    expect(estimateButton.exists()).toBe(true);
    expect(estimateButton.attributes('type')).toBe('button');

    wrapper.unmount();
  });

  it('prepares a pasted contact list without AI', async () => {
    whatsappCloudAudienceImportsAPI.create.mockResolvedValue({
      data: {
        imported: 2,
        created: 2,
        updated: 0,
        ignored: 0,
        invalid: 0,
        duplicates: 0,
        contact_ids: [91, 92],
      },
    });
    const wrapper = mount(BroadcastsPanel, {
      props: {
        inbox: { id: 29 },
        templates: [
          {
            name: 'hello_world',
            language: 'en_US',
            category: 'UTILITY',
            status: 'APPROVED',
            components: [{ type: 'BODY', text: 'Hello' }],
          },
        ],
        labels: [],
        campaigns: [],
      },
      global: {
        stubs: {
          Dialog: DialogStub,
        },
      },
    });

    await buttonByText(wrapper, 'New broadcast').trigger('click');
    await wrapper
      .find('input[name="whatsapp-audience-consent"]')
      .setValue(true);
    await buttonByText(wrapper, 'Paste list').trigger('click');
    await wrapper
      .find('textarea[name="pasted-whatsapp-contacts"]')
      .setValue('63999991111\n63888882222');
    await buttonByText(wrapper, 'Prepare audience').trigger('click');
    await flushPromises();

    expect(whatsappCloudAudienceImportsAPI.create).toHaveBeenCalledWith({
      inboxId: 29,
      contacts: [
        { phone_number: '+5563999991111', name: '', company_name: '' },
        { phone_number: '+5563888882222', name: '', company_name: '' },
      ],
      consentConfirmed: true,
    });
    expect(wrapper.text()).toContain('2 contact(s) ready');
    wrapper.unmount();
  });

  it('submits a complete broadcast from its visible action button', async () => {
    const wrapper = mount(BroadcastsPanel, {
      props: {
        inbox: { id: 29 },
        templates: [
          {
            name: 'hello_world',
            language: 'en_US',
            category: 'UTILITY',
            status: 'APPROVED',
            components: [{ type: 'BODY', text: 'Hello' }],
          },
        ],
        labels: [{ id: 1, title: 'Cliente' }],
        campaigns: [],
      },
      global: {
        stubs: {
          Dialog: DialogStub,
        },
      },
    });

    await buttonByText(wrapper, 'New broadcast').trigger('click');
    await nextTick();
    await wrapper.find('input:not([type])').setValue('Test broadcast');
    await wrapper.find('select:not([multiple])').setValue('hello_world|en_US');
    await wrapper.findAll('input[type="checkbox"]')[1].setValue(true);
    await wrapper
      .find('input[type="datetime-local"]')
      .setValue('2099-01-01T12:00');
    await wrapper.find('input[type="checkbox"]').setValue(true);
    await nextTick();

    const createButton = buttonByText(wrapper, 'Schedule broadcast');
    expect(createButton.attributes('type')).toBe('submit');
    expect(createButton.attributes('disabled')).toBeUndefined();
    await wrapper.find('[role="dialog"]').trigger('submit');
    await flushPromises();

    expect(wrapper.find('[role="dialog"]').exists()).toBe(false);
    wrapper.unmount();
  });
});
