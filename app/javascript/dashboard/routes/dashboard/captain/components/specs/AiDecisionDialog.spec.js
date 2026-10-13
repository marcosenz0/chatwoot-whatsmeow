import { mount, flushPromises } from '@vue/test-utils';
import API from 'dashboard/api/marcosxAi';
import AiDecisionDialog from '../AiDecisionDialog.vue';

const push = vi.hoisted(() => vi.fn());
vi.mock('vue-router', () => ({
  useRoute: () => ({ params: { accountId: '1' } }),
  useRouter: () => ({ push }),
}));
vi.mock('dashboard/api/marcosxAi', () => ({
  default: { getConversationDecision: vi.fn() },
}));

it('labels legacy sources and opens the matching current instruction without putting prompt text in the URL', async () => {
  API.getConversationDecision.mockResolvedValue({
    data: {
      note: 'Human attention requested',
      assistant: { id: 3, name: 'Support' },
      snapshot: null,
      sources: [
        {
          field: 'editorial',
          section: 'prompt',
          editable: true,
          text: 'Continue helping.\nPeça atendimento humano para verificar detalhes.',
        },
      ],
    },
  });
  const wrapper = mount(AiDecisionDialog, {
    props: { conversationId: 7, messageId: 42 },
    global: {
      stubs: {
        Dialog: {
          setup(_, { expose }) {
            expose({ open() {}, close() {} });
          },
          template: '<div><slot /></div>',
        },
      },
    },
  });
  await flushPromises();
  expect(API.getConversationDecision).toHaveBeenCalledWith(7, 42, {
    signal: expect.any(AbortSignal),
  });
  expect(wrapper.text()).toContain('MARCOX_AI.DECISION.LEGACY');
  expect(wrapper.text()).toContain(
    'Peça atendimento humano para verificar detalhes.'
  );
  await wrapper
    .findAll('button')
    .find(button => button.text().includes('MARCOX_AI.DECISION.GO_EXCERPT'))
    .trigger('click');
  expect(push).toHaveBeenCalledWith({
    path: '/app/accounts/1/captain/overview',
    query: { agent: 3, section: 'prompt', focus: 'editorial' },
    state: {
      marcosxAiExcerpt: 'Peça atendimento humano para verificar detalhes.',
    },
  });
  await wrapper.get('input').setValue('inexistente');
  expect(
    wrapper
      .findAll('button')
      .some(button => button.text().includes('MARCOX_AI.DECISION.GO_EXCERPT'))
  ).toBe(false);
  wrapper.unmount();
});
