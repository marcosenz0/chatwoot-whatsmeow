import { mount, flushPromises } from '@vue/test-utils';
import { reactive } from 'vue';
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import ConversationsAPI from 'dashboard/api/conversations';
import InboxesAPI from 'dashboard/api/inboxes';
import CallsAPI from 'dashboard/api/whatsmeowCalls';
import WhatsmeowConversationCall from '../WhatsmeowConversationCall.vue';

const mocks = vi.hoisted(() => ({
  route: null,
  push: vi.fn(),
  replace: vi.fn(),
}));
vi.mock('vue-router', () => ({
  useRoute: () => mocks.route,
  useRouter: () => mocks,
}));
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({ accountId: { value: 2 } }),
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/api/conversations', () => ({ default: { show: vi.fn() } }));
vi.mock('dashboard/api/inboxes', () => ({ default: { show: vi.fn() } }));
vi.mock('dashboard/api/whatsmeowCalls', () => ({
  default: { createSession: vi.fn(), getAll: vi.fn() },
}));

let wrapper;
let sockets;
let play;
let pause;
const incoming = {
  account_id: 2,
  conversation_id: 2170,
  source_id: 'ring-1',
  direction: 'incoming',
  status: 'ringing',
  video: false,
};

beforeEach(() => {
  mocks.route = reactive({ params: { accountId: '2' }, query: {} });
  sockets = [];
  vi.stubGlobal(
    'WebSocket',
    class {
      static OPEN = 1;

      readyState = 1;

      constructor() {
        sockets.push(this);
        queueMicrotask(() => this.onopen());
      }

      close = vi.fn();

      send = vi.fn();
    }
  );
  play = vi.spyOn(HTMLMediaElement.prototype, 'play').mockResolvedValue();
  pause = vi
    .spyOn(HTMLMediaElement.prototype, 'pause')
    .mockImplementation(() => {});
  ConversationsAPI.show.mockResolvedValue({
    data: {
      id: 2170,
      inbox_id: 27,
      whatsmeow_call_available: true,
      meta: {
        sender: { name: 'Contato teste', phone_number: '+5500000000000' },
      },
    },
  });
  InboxesAPI.show.mockResolvedValue({
    data: { id: 27, name: 'Inbox teste', channel_type: 'Channel::Whatsmeow' },
  });
  CallsAPI.createSession.mockResolvedValue({
    data: { url: 'https://calls.test/calls/27', token: 'test-token' },
  });
  CallsAPI.getAll.mockResolvedValue({ data: { payload: [] } });
  wrapper = mount(WhatsmeowConversationCall, {
    global: {
      stubs: {
        Teleport: true,
        WhatsmeowCallWindow: {
          template: '<section><slot name="header"/><slot/></section>',
        },
        NextButton: {
          props: ['label'],
          template: '<button>{{ label }}<slot/></button>',
        },
      },
    },
  });
});
afterEach(() => {
  wrapper.unmount();
  vi.restoreAllMocks();
  vi.unstubAllGlobals();
});

it('receives on the dashboard without an open conversation, rings and stops after ending', async () => {
  emitter.emit(BUS_EVENTS.WHATSMEOW_CALL_UPDATED, incoming);
  await flushPromises();
  expect(sockets).toHaveLength(1);
  sockets[0].onmessage({
    data: JSON.stringify({ event: 'incoming', call_id: 'ring-1' }),
  });
  await flushPromises();
  expect(wrapper.text()).toContain('Contato teste');
  expect(wrapper.text()).toContain('Inbox teste');
  expect(play).toHaveBeenCalled();
  pause.mockClear();
  emitter.emit(BUS_EVENTS.WHATSMEOW_CALL_UPDATED, {
    ...incoming,
    status: 'missed',
  });
  await flushPromises();
  expect(pause).toHaveBeenCalled();
  expect(wrapper.text()).toContain('CONVERSATION.WHATSMEOW_CALL.ENDED');
});

it('keeps the call window when navigating and does not ring twice for duplicate notifications', async () => {
  emitter.emit(BUS_EVENTS.WHATSMEOW_CALL_UPDATED, incoming);
  await flushPromises();
  sockets[0].onmessage({
    data: JSON.stringify({ event: 'incoming', call_id: 'ring-1' }),
  });
  await flushPromises();
  mocks.route.params.conversation_id = '999';
  emitter.emit(BUS_EVENTS.WHATSMEOW_CALL_UPDATED, incoming);
  await flushPromises();
  expect(sockets).toHaveLength(1);
  expect(wrapper.text()).toContain('Contato teste');
  expect(play).toHaveBeenCalledTimes(1);
});

it('does not open a stale pending call after its terminal event arrives during the conversation fetch', async () => {
  let resolveConversation;
  ConversationsAPI.show.mockImplementation(
    () =>
      new Promise(resolve => {
        resolveConversation = resolve;
      })
  );
  emitter.emit(BUS_EVENTS.WHATSMEOW_CALL_UPDATED, incoming);
  await flushPromises();
  emitter.emit(BUS_EVENTS.WHATSMEOW_CALL_UPDATED, {
    ...incoming,
    status: 'missed',
  });
  resolveConversation({ data: { inbox_id: 27 } });
  await flushPromises();
  expect(sockets).toHaveLength(0);
  expect(play).not.toHaveBeenCalled();
});

it('offers an explicit sound button when the browser blocks autoplay', async () => {
  play.mockRejectedValueOnce(new DOMException('Blocked', 'NotAllowedError'));
  emitter.emit(BUS_EVENTS.WHATSMEOW_CALL_UPDATED, incoming);
  await flushPromises();
  sockets[0].onmessage({
    data: JSON.stringify({ event: 'incoming', call_id: 'ring-1' }),
  });
  await flushPromises();
  const button = wrapper
    .findAll('button')
    .find(item => item.text().includes('ENABLE_RINGTONE'));
  expect(button).toBeDefined();
  await button.trigger('click');
  await flushPromises();
  expect(wrapper.text()).not.toContain('ENABLE_RINGTONE');
});

it('recovers ringing calls on reconnect and ignores another account', async () => {
  emitter.emit(BUS_EVENTS.WHATSMEOW_CALL_UPDATED, {
    ...incoming,
    account_id: 3,
  });
  await flushPromises();
  expect(sockets).toHaveLength(0);
  CallsAPI.getAll.mockResolvedValue({ data: { payload: [incoming] } });
  emitter.emit(BUS_EVENTS.WEBSOCKET_RECONNECT);
  await flushPromises();
  expect(sockets).toHaveLength(1);
});
